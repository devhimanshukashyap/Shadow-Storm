// lib/services/teammate_suggestions_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Teammate Suggestions Service
//
// Stores recently used teammate details on-device only (SharedPreferences).
// Never writes to Firebase. Used purely for UX convenience in team slot forms.
//
// Storage structure (SharedPreferences):
//   Key: 'teammates'
//   Value: JSON array of TeammateEntry objects, max 20 entries, newest-first.
//
// Each entry: { gameUid, ign, lastUsed (ISO-8601) }
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// TEAMMATE ENTRY MODEL
// ─────────────────────────────────────────────

class TeammateEntry {
  final String   gameUid;
  final String   ign;
  final DateTime lastUsed;

  const TeammateEntry({
    required this.gameUid,
    required this.ign,
    required this.lastUsed,
  });

  factory TeammateEntry.fromMap(Map<String, dynamic> d) => TeammateEntry(
    gameUid:  d['gameUid']  as String? ?? '',
    ign:      d['ign']      as String? ?? '',
    lastUsed: DateTime.tryParse(d['lastUsed'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'gameUid':  gameUid,
    'ign':      ign,
    'lastUsed': lastUsed.toIso8601String(),
  };
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────

class TeammateSuggestionsService {
  TeammateSuggestionsService._();
  static final TeammateSuggestionsService instance = TeammateSuggestionsService._();

  static const _key     = 'teammates';
  static const _maxSize = 20;

  SharedPreferences? _prefs;

  // ── Init ──────────────────────────────────────

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[TeammateSuggestionsService] init error: $e');
    }
  }

  // ── Read ──────────────────────────────────────

  /// Returns all saved teammates, newest-first.
  List<TeammateEntry> getAll() {
    if (_prefs == null) return [];
    try {
      final raw = _prefs!.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TeammateEntry.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    } catch (e) {
      debugPrint('[TeammateService] getAll error: $e');
      return [];
    }
  }

  /// Returns teammates whose IGN or gameUid contains [query] (case-insensitive).
  List<TeammateEntry> search(String query) {
    if (query.trim().isEmpty) return getAll();
    final q = query.trim().toLowerCase();
    return getAll()
        .where((e) =>
            e.ign.toLowerCase().contains(q) ||
            e.gameUid.toLowerCase().contains(q))
        .toList();
  }

  // ── Write ─────────────────────────────────────

  /// Saves a teammate. Updates lastUsed if already exists, otherwise inserts.
  /// Trims list to _maxSize, removing the oldest entries.
  Future<void> save({required String gameUid, required String ign}) async {
    if (_prefs == null) return;
    if (gameUid.trim().isEmpty) return;

    try {
      final list = getAll();

      // Remove existing entry for this gameUid (dedup by gameUid).
      list.removeWhere((e) => e.gameUid.trim() == gameUid.trim());

      // Insert at front.
      list.insert(0, TeammateEntry(
        gameUid:  gameUid.trim(),
        ign:      ign.trim(),
        lastUsed: DateTime.now(),
      ));

      // Trim to max.
      final trimmed = list.take(_maxSize).toList();

      await _prefs!.setString(
        _key,
        jsonEncode(trimmed.map((e) => e.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('[TeammateService] save error: $e');
    }
  }

  /// Saves all slots from a completed team registration at once.
  /// Skips slot 0 (the leader — already in their own profile).
  Future<void> saveFromSlots(List<dynamic> slots) async {
    // Accepts List<TeamSlot> — we use dynamic to avoid circular import.
    for (final slot in slots) {
      if (slot == null) continue;
      try {
        final index   = slot.slotIndex as int;
        final gameUid = slot.gameUid  as String;
        final ign     = slot.ign      as String;
        if (index == 0) continue; // skip leader
        if (gameUid.trim().isEmpty) continue;
        await save(gameUid: gameUid, ign: ign);
      } catch (_) {}
    }
  }

  /// Removes a specific entry by gameUid.
  Future<void> remove(String gameUid) async {
    if (_prefs == null) return;
    try {
      final list = getAll()..removeWhere((e) => e.gameUid.trim() == gameUid.trim());
      await _prefs!.setString(
        _key,
        jsonEncode(list.map((e) => e.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('[TeammateService] remove error: $e');
    }
  }

  /// Clears all saved teammates.
  Future<void> clear() async {
    await _prefs?.remove(_key);
  }
}