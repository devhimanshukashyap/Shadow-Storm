// lib/services/tournament_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Tournament Service (Phase F1)
//
// Changes from v3:
//   PRIORITY 1 — joinWithTeam() now runs a FULL Firestore transaction:
//     1. Validate tournament exists
//     2. Validate status == 'upcoming'
//     3. Validate joinedPlayers < maxPlayers
//     4. Validate user is not already registered (duplicate check)
//     5. Validate walletBalance >= entryFee
//     6. Deduct walletBalance
//     7. Increment joinedPlayers
//     8. Create participant document (inside transaction via txn.set)
//     9. Create transaction record (type: 'tournament_entry')
//     All 9 steps commit atomically — nothing is written if any step fails.
//
//   PRIORITY 2 — isRoomRevealed() is now the SINGLE source of truth.
//     Both EventsScreen and TournamentDetailsScreen must call this method.
//     No duplicate reveal logic anywhere else.
//     Respects admin-set roomRevealTime if present; falls back to 30min rule.
//
//   All original v3 streams, helpers, and team slot logic kept intact.
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

  final FirebaseFirestore _db   = FirebaseFirestore.instance;
  final FirebaseAuth      _auth = FirebaseAuth.instance;
  static const String _col = 'tournaments';

  // ── Memoized streams ─────────────────────────
  Stream<TournamentModel?>?      _featuredStream;
  Stream<List<TournamentModel>>? _liveStream;
  Stream<List<TournamentModel>>? _upcomingStream;
  Stream<List<TournamentModel>>? _completedStream;

  // ──────────────────────────────────────────────────────
  // REALTIME STREAMS (unchanged from v3)
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
  // PARTICIPANT / JOIN STREAMS (unchanged from v3)
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
  // PRIORITY 2 — ROOM REVEAL SINGLE SOURCE OF TRUTH
  //
  // THIS is the only place reveal logic lives.
  // EventsScreen and TournamentDetailsScreen BOTH call this method.
  // No other reveal logic should exist in any screen.
  //
  // Rules (in priority order):
  //   1. Completed tournaments: never reveal.
  //   2. No roomId set: nothing to reveal.
  //   3. Admin has set roomRevealTime: use that exact time.
  //   4. Fallback: 30 minutes before startTime.
  //   5. No startTime and no roomRevealTime: reveal immediately.
  // ──────────────────────────────────────────────────────
  bool isRoomRevealed(TournamentModel t) {
    // Rule 1: completed tournaments never show room.
    if (t.status == TournamentStatus.completed) return false;

    // Rule 2: no credentials set yet.
    if (t.roomId == null || t.roomId!.isEmpty) return false;

    final now = DateTime.now();

    // Rule 3: admin has explicitly set a reveal time — always respect it.
    if (t.roomRevealTime != null) {
      return now.isAfter(t.roomRevealTime!);
    }

    // Rule 4: fallback to 30 minutes before match start.
    if (t.startTime != null) {
      return now.isAfter(t.startTime!.subtract(const Duration(minutes: 30)));
    }

    // Rule 5: no timing info — reveal.
    return true;
  }

  // ──────────────────────────────────────────────────────
  // PRIORITY 1 — SAFE TOURNAMENT REGISTRATION
  //
  // Full atomic Firestore transaction. All 9 steps or nothing.
  // joinTournament() is a convenience wrapper for solo joins.
  // ──────────────────────────────────────────────────────

  /// Solo join: builds a single-slot team and delegates to joinWithTeam().
  Future<({bool success, String? error})> joinTournament(
    String tournamentId,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return (success: false, error: 'Not logged in.');

    Map<String, dynamic> profile = {};
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      profile = doc.data() ?? {};
    } catch (_) {}

    final slot0 = TeamSlot(
      slotIndex:  0,
      gameUid:    (profile['gameUid']   as String?) ?? '',
      ign:        (profile['ign']       as String?) ?? user.displayName ?? 'Unknown',
      userId:     user.uid,
      readableId: profile['readableId'] as String?,
    );

    return joinWithTeam(
      tournamentId: tournamentId,
      slots:        [slot0],
      profile:      profile,
    );
  }

  /// PRIORITY 1 — Full atomic registration transaction.
  ///
  /// Steps (all-or-nothing):
  ///   1. Validate tournament exists
  ///   2. Validate status == 'upcoming'
  ///   3. Validate joinedPlayers < maxPlayers
  ///   4. Validate user NOT already registered (duplicate prevention)
  ///   5. Validate walletBalance >= entryFee
  ///   6. Deduct walletBalance from user document
  ///   7. Increment joinedPlayers on tournament document
  ///   8. Create participant sub-document
  ///   9. Create transaction record (type: 'tournament_entry')
  Future<({bool success, String? error})> joinWithTeam({
    required String         tournamentId,
    required List<TeamSlot> slots,
    Map<String, dynamic>    profile = const {},
  }) async {
    final user = _auth.currentUser;
    if (user == null) return (success: false, error: 'Not logged in.');
    if (slots.isEmpty) return (success: false, error: 'No team slots provided.');

    // Client-side duplicate gameUid check (UX guard only — server also validates).
    final gameUids = slots.map((s) => s.gameUid).where((u) => u.isNotEmpty).toList();
    if (gameUids.toSet().length != gameUids.length) {
      return (success: false, error: 'Duplicate game UIDs in your team.');
    }

    final tRef           = _db.collection(_col).doc(tournamentId);
    final participantRef = tRef.collection('participants').doc(user.uid);
    final userRef        = _db.collection('users').doc(user.uid);

    try {
      await _db.runTransaction((txn) async {
        // ── Step 1: Tournament exists ──────────────────
        final tSnap = await txn.get(tRef);
        if (!tSnap.exists) throw Exception('Tournament not found.');

        final tData         = tSnap.data()!;
        final status        = (tData['status']        as String?) ?? 'upcoming';
        final maxPlayers    = (tData['maxPlayers']    as num?)?.toInt() ?? 0;
        final joinedPlayers = (tData['joinedPlayers'] as num?)?.toInt() ?? 0;
        final entryFee      = (tData['entryFee']      as num?)?.toDouble() ?? 0.0;
        final tTitle        = (tData['title']         as String?) ?? 'Tournament';
        final requiredSlots = (tData['requiredSlots'] as num?)?.toInt() ?? 1;

        // ── Step 2: Status must be upcoming ───────────
        if (status != 'upcoming') {
          throw Exception('Tournament is no longer accepting registrations.');
        }

        // ── Step 3: Slots available ────────────────────
        if (joinedPlayers >= maxPlayers) {
          throw Exception('Tournament is full.');
        }

        // ── Step 4: Not already registered ────────────
        // PRIORITY 1: Duplicate registration prevention inside transaction.
        final participantSnap = await txn.get(participantRef);
        if (participantSnap.exists) {
          throw Exception('You are already registered for this tournament.');
        }

        // ── Step 5: Wallet balance check ───────────────
        final uSnap = await txn.get(userRef);
        if (!uSnap.exists) throw Exception('User profile not found.');

        final uData  = uSnap.data()!;
        final balance = (uData['walletBalance'] as num?)?.toDouble() ?? 0.0;

        if (balance < entryFee) {
          throw Exception(
            'Insufficient wallet balance. '
            'Required: ₹${entryFee.toStringAsFixed(2)}, '
            'Available: ₹${balance.toStringAsFixed(2)}.',
          );
        }

        // Validate team slot count
        if (slots.length < requiredSlots) {
          throw Exception(
            'This tournament requires at least $requiredSlots player(s) per team.',
          );
        }

        // ── Step 6: Deduct wallet balance ──────────────
        if (entryFee > 0) {
          txn.update(userRef, {
            'walletBalance': FieldValue.increment(-entryFee),
          });
        }

        // ── Step 7: Increment joinedPlayers ───────────
        txn.update(tRef, {'joinedPlayers': FieldValue.increment(1)});

        // ── Step 8: Create participant document ────────
        txn.set(participantRef, {
          'userId':     user.uid,
          'userName':   (profile['name']       as String?) ?? user.displayName ?? 'Unknown',
          'userEmail':  (profile['email']      as String?) ?? user.email       ?? '',
          'readableId': profile['readableId']  as String?,
          'ign':        slots.first.ign,
          'joinedAt':   FieldValue.serverTimestamp(),
          'status':     'registered',
          'placement':  0,
          'kills':      0,
          'winnings':   0.0,
          'teamSlots':  slots.map((s) => s.toMap()).toList(),
        });

        // ── Step 9: Create transaction record ──────────
        // type: 'tournament_entry' as required by spec.
        if (entryFee > 0) {
          final txnDocRef = userRef.collection('transactions').doc();
          txn.set(txnDocRef, {
            'type':        'tournament_entry',
            'amount':      entryFee,
            'status':      'completed',
            'description': 'Tournament Entry - $tTitle',
            'tournamentId': tournamentId,
            'createdAt':   FieldValue.serverTimestamp(),
            'isCredit':    false,
          });
        }
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
  // PLAYER LOOKUP HELPERS (unchanged from v3)
  // ──────────────────────────────────────────────────────

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
  // ONE-TIME READ (unchanged from v3)
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
  // CACHE REFRESH (unchanged from v3)
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