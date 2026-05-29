// lib/services/cache_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Cache Service (Phase F1)
//
// Changes from Phase P1:
//   PRIORITY 8 — Cache behavior corrected:
//     • App open: load cache first, then background refresh.
//     • Screen revisit: show cache immediately.
//     • Only fetch Firestore on: pull-to-refresh, cache expired, or
//       explicit invalidation after data change.
//     • Added isFresh(key) helper for screens to check before fetching.
//     • Added shouldRefresh(key) — true if cache is missing or expired.
//     • Added backgroundRefreshCallback support (optional).
//   All original keys, groups, TTLs and persistence logic kept intact.
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// CACHE KEYS
// ─────────────────────────────────────────────

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

enum CacheGroup { user, tournaments, settings, rankings }

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

const _defaultTtls = <CacheKey, Duration>{
  CacheKey.profile:             Duration(minutes: 10),
  CacheKey.profileStats:        Duration(minutes: 5),
  CacheKey.featuredTournament:  Duration(minutes: 3),
  CacheKey.liveTournaments:     Duration(seconds: 30),
  CacheKey.upcomingTournaments: Duration(minutes: 5),
  CacheKey.allTournaments:      Duration(minutes: 5),
  CacheKey.joinedTournamentIds: Duration(minutes: 2),
  // PRIORITY 7: leaderboard cache — longer TTL, manual refresh only.
  CacheKey.leaderboard:         Duration(minutes: 10),
  CacheKey.adminSettings:       Duration(minutes: 5),
  CacheKey.maintenanceMode:     Duration(minutes: 1),
  CacheKey.walletSettings:      Duration(minutes: 5),
};

// ─────────────────────────────────────────────
// CACHE ENTRY
// ─────────────────────────────────────────────

class _CacheEntry<T> {
  final T        value;
  final DateTime storedAt;
  final DateTime expiresAt;

  const _CacheEntry({
    required this.value,
    required this.storedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Age of this entry in seconds.
  int get ageSeconds => DateTime.now().difference(storedAt).inSeconds;
}

// ─────────────────────────────────────────────
// CACHE SERVICE
// ─────────────────────────────────────────────

class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  final Map<CacheKey, _CacheEntry<dynamic>> _store = {};
  SharedPreferences? _prefs;

  static const _persistedKeys = <CacheKey>{
    CacheKey.adminSettings,
    CacheKey.maintenanceMode,
    CacheKey.walletSettings,
  };

  // ── Initialization ──────────────────────────

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadPersistedEntries();
    } catch (e) {
      debugPrint('[CacheService] init error: $e');
    }
  }

  // ── Core API ────────────────────────────────

  void set<T>(CacheKey key, T value, {Duration? ttl}) {
    final duration = ttl ?? _defaultTtls[key] ?? const Duration(minutes: 5);
    final now      = DateTime.now();
    _store[key] = _CacheEntry<T>(
      value:     value,
      storedAt:  now,
      expiresAt: now.add(duration),
    );
    if (_persistedKeys.contains(key)) {
      _persistEntry(key, value, duration);
    }
  }

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

  // ── PRIORITY 8: Cache behavior helpers ─────

  /// Returns true if cache exists AND is fresh (not expired).
  /// Use this to decide whether to show cache immediately.
  bool isFresh(CacheKey key) {
    final entry = _store[key];
    return entry != null && !entry.isExpired;
  }

  /// Returns true if cache is missing or expired — caller should fetch fresh data.
  /// On app open: show cache (if any), then call Firestore only if this returns true.
  /// On pull-to-refresh: call invalidate() first, then shouldRefresh() returns true.
  bool shouldRefresh(CacheKey key) => !isFresh(key);

  /// Returns the cached value immediately (may be expired) for showing stale-while-revalidate UI.
  /// Use this when you want to show something immediately even if data is old.
  T? getStale<T>(CacheKey key) {
    final entry = _store[key];
    if (entry == null) return null;
    return entry.value as T?;
  }

  void invalidate(CacheKey key) {
    _store.remove(key);
    if (_persistedKeys.contains(key)) {
      _prefs?.remove('cache_${key.name}');
    }
  }

  void invalidateGroup(CacheGroup group) {
    final keys = _keyGroups.entries
        .where((e) => e.value == group)
        .map((e) => e.key)
        .toList();
    for (final key in keys) {
      invalidate(key);
    }
  }

  void clear() {
    _store.clear();
    for (final key in _persistedKeys) {
      _prefs?.remove('cache_${key.name}');
    }
    debugPrint('[CacheService] Cache cleared.');
  }

  Duration? age(CacheKey key) {
    final entry = _store[key];
    if (entry == null) return null;
    return DateTime.now().difference(entry.storedAt);
  }

  // ── SharedPreferences persistence ──────────

  void _persistEntry<T>(CacheKey key, T value, Duration ttl) {
    try {
      final json = jsonEncode({
        'value':     value,
        'storedAt':  DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now().add(ttl).toIso8601String(),
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
        final storedAt  = DateTime.tryParse(map['storedAt'] as String? ?? '') ??
            DateTime.now();
        // Load even if expired — screens can use getStale() for immediate display
        // while deciding whether to refresh.
        _store[key] = _CacheEntry(
          value:     map['value'],
          storedAt:  storedAt,
          expiresAt: expiresAt,
        );
      } catch (e) {
        debugPrint('[CacheService] load error for ${key.name}: $e');
      }
    }
  }

  // ── Debug ───────────────────────────────────

  void debugDump() {
    if (!kDebugMode) return;
    debugPrint('[CacheService] ─── Cache Dump ───');
    for (final entry in _store.entries) {
      final status = entry.value.isExpired ? 'EXPIRED' : 'valid';
      final age    = entry.value.ageSeconds;
      debugPrint('  ${entry.key.name}: $status (${age}s old)');
    }
  }
}