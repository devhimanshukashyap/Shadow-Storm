// lib/services/cache_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Cache Service (Phase P1)
//
// Architecture:
//   • In-memory cache — instant reads, zero Firestore cost
//   • TTL per entry — automatic staleness detection
//   • SharedPreferences hooks — optional persistence across sessions
//   • Typed cache keys — no magic strings scattered across files
//   • Thread-safe: all ops synchronous on in-memory layer
//
// Usage:
//   CacheService.instance.set(CacheKey.profile, data, ttl: Duration(minutes: 5));
//   CacheService.instance.get<Map>(CacheKey.profile);
//   CacheService.instance.invalidate(CacheKey.profile);
//   CacheService.instance.invalidateGroup(CacheGroup.tournaments);
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// CACHE KEYS
// ─────────────────────────────────────────────

/// All cache keys in one place. No magic strings.
enum CacheKey {
  // User
  profile,
  profileStats,

  // Tournaments
  featuredTournament,
  liveTournaments,
  upcomingTournaments,
  allTournaments,
  joinedTournamentIds,

  // Rankings
  leaderboard,

  // Settings
  adminSettings,
  maintenanceMode,
  walletSettings,
}

/// Groups allow bulk invalidation — e.g. when admin updates tournaments.
enum CacheGroup { user, tournaments, settings, rankings }

// Map each key to its group
const _keyGroups = <CacheKey, CacheGroup>{
  CacheKey.profile:             CacheGroup.user,
  CacheKey.profileStats:        CacheGroup.user,
  CacheKey.featuredTournament:  CacheGroup.tournaments,
  CacheKey.liveTournaments:     CacheGroup.tournaments,
  CacheKey.upcomingTournaments: CacheGroup.tournaments,
  CacheKey.allTournaments:      CacheGroup.tournaments,
  CacheKey.joinedTournamentIds: CacheGroup.user,
  CacheKey.leaderboard:         CacheGroup.rankings,
  CacheKey.adminSettings:       CacheGroup.settings,
  CacheKey.maintenanceMode:     CacheGroup.settings,
  CacheKey.walletSettings:      CacheGroup.settings,
};

// Default TTLs per key
const _defaultTtls = <CacheKey, Duration>{
  CacheKey.profile:             Duration(minutes: 10),
  CacheKey.profileStats:        Duration(minutes: 5),
  CacheKey.featuredTournament:  Duration(minutes: 3),
  CacheKey.liveTournaments:     Duration(seconds: 30), // live — keep fresh
  CacheKey.upcomingTournaments: Duration(minutes: 5),
  CacheKey.allTournaments:      Duration(minutes: 5),
  CacheKey.joinedTournamentIds: Duration(minutes: 2),
  CacheKey.leaderboard:         Duration(minutes: 10),
  CacheKey.adminSettings:       Duration(minutes: 5),
  CacheKey.maintenanceMode:     Duration(minutes: 1), // critical — keep fresh
  CacheKey.walletSettings:      Duration(minutes: 5),
};

// ─────────────────────────────────────────────
// CACHE ENTRY
// ─────────────────────────────────────────────

class _CacheEntry<T> {
  final T       value;
  final DateTime expiresAt;

  const _CacheEntry({required this.value, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// ─────────────────────────────────────────────
// CACHE SERVICE
// ─────────────────────────────────────────────

class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  // In-memory store
  final Map<CacheKey, _CacheEntry<dynamic>> _store = {};

  // SharedPreferences reference (initialized lazily)
  SharedPreferences? _prefs;

  // Keys that should be persisted to SharedPreferences
  static const _persistedKeys = <CacheKey>{
    CacheKey.adminSettings,
    CacheKey.maintenanceMode,
    CacheKey.walletSettings,
  };

  // ── Initialization ──────────────────────────

  /// Call once at app startup (e.g. in main() or SplashScreen).
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadPersistedEntries();
    } catch (e) {
      debugPrint('[CacheService] init error: $e');
    }
  }

  // ── Core API ────────────────────────────────

  /// Store [value] under [key]. Uses [ttl] if provided, else default TTL.
  void set<T>(
    CacheKey key,
    T value, {
    Duration? ttl,
  }) {
    final duration = ttl ?? _defaultTtls[key] ?? const Duration(minutes: 5);
    _store[key] = _CacheEntry<T>(
      value: value,
      expiresAt: DateTime.now().add(duration),
    );
    if (_persistedKeys.contains(key)) {
      _persistEntry(key, value);
    }
  }

  /// Get cached value for [key]. Returns null if missing or expired.
  T? get<T>(CacheKey key) {
    final entry = _store[key];
    if (entry == null || entry.isExpired) {
      _store.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  /// Returns true if [key] has a valid (non-expired) cache entry.
  bool has(CacheKey key) => get(key) != null;

  /// Remove single key.
  void invalidate(CacheKey key) {
    _store.remove(key);
    if (_persistedKeys.contains(key)) {
      _prefs?.remove('cache_${key.name}');
    }
  }

  /// Remove all keys in a [group].
  void invalidateGroup(CacheGroup group) {
    final keys = _keyGroups.entries
        .where((e) => e.value == group)
        .map((e) => e.key)
        .toList();
    for (final key in keys) {
      invalidate(key);
    }
  }

  /// Wipe everything — use on sign-out.
  void clear() {
    _store.clear();
    for (final key in _persistedKeys) {
      _prefs?.remove('cache_${key.name}');
    }
    debugPrint('[CacheService] Cache cleared.');
  }

  /// Returns age of the cached entry, or null if not cached.
  Duration? age(CacheKey key) {
    final entry = _store[key];
    if (entry == null) return null;
    final defaultTtl = _defaultTtls[key] ?? const Duration(minutes: 5);
    return defaultTtl - entry.expiresAt.difference(DateTime.now());
  }

  // ── SharedPreferences persistence ──────────

  void _persistEntry<T>(CacheKey key, T value) {
    try {
      final json = jsonEncode({
        'value':     value,
        'expiresAt': DateTime.now()
            .add(_defaultTtls[key] ?? const Duration(minutes: 5))
            .toIso8601String(),
      });
      _prefs?.setString('cache_${key.name}', json);
    } catch (e) {
      debugPrint('[CacheService] persist error for ${key.name}: $e');
    }
  }

  void _loadPersistedEntries() {
    if (_prefs == null) return;
    for (final key in _persistedKeys) {
      try {
        final raw = _prefs!.getString('cache_${key.name}');
        if (raw == null) continue;
        final map       = jsonDecode(raw) as Map<String, dynamic>;
        final expiresAt = DateTime.parse(map['expiresAt'] as String);
        if (DateTime.now().isBefore(expiresAt)) {
          _store[key] = _CacheEntry(
            value:     map['value'],
            expiresAt: expiresAt,
          );
        }
      } catch (e) {
        debugPrint('[CacheService] load error for ${key.name}: $e');
      }
    }
  }

  // ── Debug ───────────────────────────────────

  /// Print current cache state — dev builds only.
  void debugDump() {
    if (!kDebugMode) return;
    debugPrint('[CacheService] ─── Cache Dump ───');
    for (final entry in _store.entries) {
      final expired = entry.value.isExpired ? 'EXPIRED' : 'valid';
      debugPrint('  ${entry.key.name}: $expired');
    }
  }
}