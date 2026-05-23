// lib/services/tournament_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Tournament Service (v3)
//
// Changes from v2:
//   • joinWithTeam() — replaces joinTournament() for team tournaments;
//     writes teamSlots array into participant document
//   • joinTournament() kept as a thin solo wrapper around joinWithTeam()
//   • completedTournamentsStream() — new stream for completed section
//   • lookupPlayerByGameUid() — resolve gameUid → user profile for
//     level-40 validation warning in team slot UI
//   • getUserByReadableId() proxied from AuthService for convenience
//   • All existing streams / cache logic unchanged
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/tournament_model.dart';
import '../models/team_slot_model.dart';
import 'cache_service.dart';

class TournamentService {
  TournamentService._();
  static final TournamentService instance = TournamentService._();

  final FirebaseFirestore _db  = FirebaseFirestore.instance;
  final FirebaseAuth      _auth = FirebaseAuth.instance;
  static const String _col = 'tournaments';

  // ── Memoized streams ─────────────────────────
  Stream<TournamentModel?>?      _featuredStream;
  Stream<List<TournamentModel>>? _liveStream;
  Stream<List<TournamentModel>>? _upcomingStream;
  Stream<List<TournamentModel>>? _completedStream;

  // ──────────────────────────────────────────────────────
  // REALTIME STREAMS
  // ──────────────────────────────────────────────────────

  Stream<TournamentModel?> featuredTournamentStream() {
    _featuredStream ??= _db
        .collection(_col)
        .where('featured', isEqualTo: true)
        .where('status', isEqualTo: 'upcoming')
        .orderBy('startTime')
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isEmpty ? null : TournamentModel.fromFirestore(snap.docs.first))
        .asBroadcastStream();
    return _featuredStream!;
  }

  Stream<List<TournamentModel>> liveTournamentsStream() {
    _liveStream ??= _db
        .collection(_col)
        .where('status', isEqualTo: 'live')
        .orderBy('startTime')
        .snapshots()
        .map(_docsToList)
        .asBroadcastStream();
    return _liveStream!;
  }

  Stream<List<TournamentModel>> upcomingTournamentsStream({int limit = 20}) {
    _upcomingStream ??= _db
        .collection(_col)
        .where('status', isEqualTo: 'upcoming')
        .orderBy('startTime')
        .limit(limit)
        .snapshots()
        .map(_docsToList)
        .asBroadcastStream();
    return _upcomingStream!;
  }

  /// Completed tournaments — shown in the new Completed section on the
  /// home screen when the user selects that status filter.
  Stream<List<TournamentModel>> completedTournamentsStream({int limit = 20}) {
    _completedStream ??= _db
        .collection(_col)
        .where('status', isEqualTo: 'completed')
        .orderBy('startTime', descending: true)
        .limit(limit)
        .snapshots()
        .map(_docsToList)
        .asBroadcastStream();
    return _completedStream!;
  }

  /// Single tournament realtime stream — for the details screen.
  Stream<TournamentModel?> tournamentByIdStream(String id) {
    return _db
        .collection(_col)
        .doc(id)
        .snapshots()
        .map((snap) => snap.exists ? TournamentModel.fromFirestore(snap) : null);
  }

  // ──────────────────────────────────────────────────────
  // FILTERED STREAM (AllTournamentsScreen)
  // ──────────────────────────────────────────────────────

  Stream<List<TournamentModel>> filteredTournamentsStream({
    String? statusFilter,
    String? typeFilter,
    int     limit = 50,
  }) {
    Query<Map<String, dynamic>> query = _db.collection(_col);
    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    query = query.orderBy('startTime').limit(limit);

    return query.snapshots().map((snap) {
      final all = _docsToList(snap);
      if (typeFilter == null || typeFilter == 'all') return all;
      return all.where((t) => t.tournamentType == typeFilter).toList();
    });
  }

  // ──────────────────────────────────────────────────────
  // PARTICIPANT / JOIN STREAMS
  // ──────────────────────────────────────────────────────

  Stream<Set<String>> joinedTournamentIdsStream(String userId) {
    return _db
        .collectionGroup('participants')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => doc.reference.parent.parent?.id)
            .whereType<String>()
            .toSet());
  }

  Stream<List<TournamentModel>> joinedTournamentsStream(String userId) {
    return _db
        .collectionGroup('participants')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((participantSnap) async {
          final ids = participantSnap.docs
              .map((doc) => doc.reference.parent.parent?.id)
              .whereType<String>()
              .toList();

          if (ids.isEmpty) return <TournamentModel>[];

          final tournaments = <TournamentModel>[];
          for (var i = 0; i < ids.length; i += 30) {
            final chunk =
                ids.sublist(i, (i + 30 > ids.length) ? ids.length : i + 30);
            try {
              final snap = await _db
                  .collection(_col)
                  .where(FieldPath.documentId, whereIn: chunk)
                  .get();
              tournaments.addAll(_docsToList(snap));
            } catch (e) {
              _log('joinedTournamentsStream chunk', e);
            }
          }

          tournaments.sort((a, b) {
            if (a.startTime == null) return 1;
            if (b.startTime == null) return -1;
            return a.startTime!.compareTo(b.startTime!);
          });

          return tournaments;
        });
  }

  // ──────────────────────────────────────────────────────
  // ROOM REVEAL LOGIC
  // ──────────────────────────────────────────────────────

  bool isRoomRevealed(TournamentModel t) {
    if (t.status == TournamentStatus.completed) return false;
    if (t.roomId == null || t.roomId!.isEmpty) return false;

    final now = DateTime.now();
    if (t.roomRevealTime != null) return now.isAfter(t.roomRevealTime!);
    if (t.startTime != null) {
      return now.isAfter(t.startTime!.subtract(const Duration(minutes: 30)));
    }
    return true;
  }

  // ──────────────────────────────────────────────────────
  // JOIN — SOLO (convenience wrapper around joinWithTeam)
  // ──────────────────────────────────────────────────────

  /// Solo join: builds a single-slot team from the current user's profile
  /// and delegates to joinWithTeam().
  Future<({bool success, String? error})> joinTournament(
    String tournamentId,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return (success: false, error: 'Not logged in.');

    // Fetch user profile for gameUid, ign, readableId
    Map<String, dynamic> profile = {};
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      profile = doc.data() ?? {};
    } catch (_) {}

    final slot0 = TeamSlot(
      slotIndex:  0,
      gameUid:    (profile['gameUid']    as String?) ?? '',
      ign:        (profile['ign']        as String?) ?? user.displayName ?? 'Unknown',
      userId:     user.uid,
      readableId: profile['readableId']  as String?,
    );

    return joinWithTeam(
      tournamentId: tournamentId,
      slots:        [slot0],
      profile:      profile,
    );
  }

  // ──────────────────────────────────────────────────────
  // JOIN — TEAM
  // ──────────────────────────────────────────────────────

  /// Validates slots, runs atomic counter increment, writes participant doc
  /// with the full teamSlots array.
  ///
  /// [slots] must contain at least one entry (slot 0 = squad leader / current user).
  /// [profile] is the current user's Firestore document data — used to
  ///   denormalize userName, userEmail, readableId into the participant doc.
  Future<({bool success, String? error})> joinWithTeam({
    required String         tournamentId,
    required List<TeamSlot> slots,
    Map<String, dynamic>    profile = const {},
  }) async {
    final user = _auth.currentUser;
    if (user == null) return (success: false, error: 'Not logged in.');
    if (slots.isEmpty) return (success: false, error: 'No team slots provided.');

    // Client-side duplicate gameUid check
    final gameUids = slots.map((s) => s.gameUid).where((u) => u.isNotEmpty).toList();
    if (gameUids.toSet().length != gameUids.length) {
      return (success: false, error: 'Duplicate game UIDs in your team.');
    }

    try {
      final tRef = _db.collection(_col).doc(tournamentId);

      // Atomic validation + increment
      await _db.runTransaction((txn) async {
        final snap = await txn.get(tRef);
        if (!snap.exists) throw Exception('Tournament not found.');

        final data          = snap.data()!;
        final status        = data['status']        as String? ?? 'upcoming';
        final maxPlayers    = (data['maxPlayers']   as num?)?.toInt() ?? 0;
        final joinedPlayers = (data['joinedPlayers'] as num?)?.toInt() ?? 0;
        final requiredSlots = (data['requiredSlots'] as num?)?.toInt() ?? 1;

        if (status != 'upcoming') {
          throw Exception('Tournament is no longer accepting registrations.');
        }
        if (joinedPlayers >= maxPlayers) {
          throw Exception('Tournament is full.');
        }
        if (slots.length < requiredSlots) {
          throw Exception(
            'This tournament requires at least $requiredSlots player(s) per team.',
          );
        }

        txn.update(tRef, {'joinedPlayers': FieldValue.increment(1)});
      });

      // Write participant document
      final participantRef = tRef.collection('participants').doc(user.uid);
      await participantRef.set({
        'userId':     user.uid,
        'userName':   (profile['name']        as String?) ?? user.displayName ?? 'Unknown',
        'userEmail':  (profile['email']        as String?) ?? user.email ?? '',
        'readableId': profile['readableId']    as String?,
        'ign':        slots.first.ign,
        'joinedAt':   FieldValue.serverTimestamp(),
        'status':     'registered',
        'placement':  0,
        'kills':      0,
        'winnings':   0.0,
        'teamSlots':  slots.map((s) => s.toMap()).toList(),
      });

      CacheService.instance.invalidateGroup(CacheGroup.tournaments);
      return (success: true, error: null);
    } catch (e) {
      _log('joinWithTeam($tournamentId)', e);
      return (
        success: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  // ──────────────────────────────────────────────────────
  // PLAYER LOOKUP HELPERS
  // ──────────────────────────────────────────────────────

  /// Look up a registered SS user by their in-game UID.
  /// Used in the team slot UI to show level warning and auto-fill IGN.
  /// Returns null if no registered user has that gameUid.
  /// Requires Firestore index: users → gameUid ASC.
  Future<Map<String, dynamic>?> lookupPlayerByGameUid(String gameUid) async {
    if (gameUid.trim().isEmpty) return null;
    try {
      final snap = await _db
          .collection('users')
          .where('gameUid', isEqualTo: gameUid.trim())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return {'uid': snap.docs.first.id, ...snap.docs.first.data()};
    } catch (e) {
      _log('lookupPlayerByGameUid($gameUid)', e);
      return null;
    }
  }

  /// Look up a registered SS user by their readable ID (e.g. "SS-A7KX3M").
  /// Useful for teammates searching each other before a tournament.
  /// Requires Firestore index: users → readableId ASC.
  Future<Map<String, dynamic>?> getUserByReadableId(String readableId) async {
    if (readableId.trim().isEmpty) return null;
    try {
      final snap = await _db
          .collection('users')
          .where('readableId', isEqualTo: readableId.trim().toUpperCase())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return {'uid': snap.docs.first.id, ...snap.docs.first.data()};
    } catch (e) {
      _log('getUserByReadableId($readableId)', e);
      return null;
    }
  }

  // ──────────────────────────────────────────────────────
  // ONE-TIME READ
  // ──────────────────────────────────────────────────────

  Future<TournamentModel?> getTournamentById(String id) async {
    try {
      final doc = await _db.collection(_col).doc(id).get();
      if (!doc.exists) return null;
      return TournamentModel.fromFirestore(doc);
    } catch (e) {
      _log('getTournamentById($id)', e);
      return null;
    }
  }

  // ──────────────────────────────────────────────────────
  // CACHE REFRESH
  // ──────────────────────────────────────────────────────

  void invalidateTournamentCache() {
    CacheService.instance.invalidateGroup(CacheGroup.tournaments);
    _featuredStream  = null;
    _liveStream      = null;
    _upcomingStream  = null;
    _completedStream = null;
  }

  // ──────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ──────────────────────────────────────────────────────

  List<TournamentModel> _docsToList(QuerySnapshot snap) {
    final result = <TournamentModel>[];
    for (final doc in snap.docs) {
      try {
        result.add(TournamentModel.fromFirestore(doc));
      } catch (e) {
        _log('parsing doc ${doc.id}', e);
      }
    }
    return result;
  }

  void _log(String ctx, Object e) =>
      debugPrint('[TournamentService] Error in $ctx: $e');
}