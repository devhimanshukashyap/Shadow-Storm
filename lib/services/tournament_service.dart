// lib/services/tournament_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Tournament Service (Phase F2.5 / PRE-F3)
//
// Changes from Phase F1:
//   PRIORITY 0 — joinWithTeam() now stores ALL team slots in the participant
//     document, not just slot 0. The teamSlots array in Firestore contains
//     every slot submitted by the player (leader + teammates).
//
//     Fields stored per slot:
//       slotIndex, gameUid, ign, userId (if known), readableId (if known)
//
//     Validation extended:
//       • All required slots must be non-null.
//       • Non-leader slots must have non-empty gameUid.
//       • Duplicate gameUid check across all slots.
//       • Slot count must meet tournament.requiredSlots minimum.
//
//   All other F1 behavior (atomic transaction, 9-step join, isRoomRevealed,
//   streams, cache invalidation) kept exactly as-is.
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
  // REALTIME STREAMS (unchanged from F1)
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
  // PARTICIPANT / JOIN STREAMS (unchanged from F1)
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
  // (unchanged from F1)
  // ──────────────────────────────────────────────────────

  bool isRoomRevealed(TournamentModel t) {
    if (t.status == TournamentStatus.completed) return false;
    if (t.roomId == null || t.roomId!.isEmpty) return false;

    final now = DateTime.now();

    if (t.roomRevealTime != null) {
      return now.isAfter(t.roomRevealTime!);
    }

    if (t.startTime != null) {
      return now.isAfter(t.startTime!.subtract(const Duration(minutes: 30)));
    }

    return true;
  }

  // ──────────────────────────────────────────────────────
  // SOLO JOIN WRAPPER
  // ──────────────────────────────────────────────────────

  /// Solo join: builds a single-slot team from user profile and delegates to joinWithTeam().
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
  // PRIORITY 0 + F1 — FULL ATOMIC REGISTRATION TRANSACTION
  //
  // Steps (all-or-nothing, unchanged from F1):
  //   1. Validate tournament exists
  //   2. Validate status == 'upcoming'
  //   3. Validate joinedPlayers < maxPlayers
  //   4. Validate user NOT already registered (duplicate prevention)
  //   5. Validate walletBalance >= entryFee
  //   6. Deduct walletBalance from user document
  //   7. Increment joinedPlayers on tournament document
  //   8. Create participant sub-document (now stores ALL team slots)
  //   9. Create transaction record (type: 'tournament_entry')
  //
  // PRIORITY 0 changes in Step 8:
  //   • teamSlots array now contains every slot (leader + all teammates).
  //   • Each slot stored as: { slotIndex, gameUid, ign, userId?, readableId? }
  //   • teamSize field added for quick admin visibility.
  //   • All teammate IGNs stored in teamIgNs[] for Firestore query convenience.
  // ──────────────────────────────────────────────────────

  Future<({bool success, String? error})> joinWithTeam({
    required String         tournamentId,
    required List<TeamSlot> slots,
    Map<String, dynamic>    profile = const {},
  }) async {
    final user = _auth.currentUser;
    if (user == null) return (success: false, error: 'Not logged in.');
    if (slots.isEmpty) return (success: false, error: 'No team slots provided.');

    // ── Client-side pre-validation ─────────────────────────────────────────

    // All non-leader slots must have a non-empty gameUid.
    for (final slot in slots) {
      if (slot.slotIndex > 0 && slot.gameUid.trim().isEmpty) {
        return (
          success: false,
          error: 'Player slot ${slot.slotIndex + 1} is missing a Game UID.',
        );
      }
    }

    // Duplicate gameUid check across all filled slots.
    final filledUids = slots
        .where((s) => s.gameUid.trim().isNotEmpty)
        .map((s) => s.gameUid.trim())
        .toList();
    if (filledUids.toSet().length != filledUids.length) {
      return (success: false, error: 'Duplicate Game UIDs found in your team.');
    }

    // ── Firestore references ──────────────────────────────────────────────

    final tRef           = _db.collection(_col).doc(tournamentId);
    final participantRef = tRef.collection('participants').doc(user.uid);
    final userRef        = _db.collection('users').doc(user.uid);

    try {
      await _db.runTransaction((txn) async {

        // ── Step 1: Tournament exists ────────────────────────────────────
        final tSnap = await txn.get(tRef);
        if (!tSnap.exists) throw Exception('Tournament not found.');

        final tData         = tSnap.data()!;
        final status        = (tData['status']        as String?) ?? 'upcoming';
        final maxPlayers    = (tData['maxPlayers']    as num?)?.toInt() ?? 0;
        final joinedPlayers = (tData['joinedPlayers'] as num?)?.toInt() ?? 0;
        final entryFee      = (tData['entryFee']      as num?)?.toDouble() ?? 0.0;
        final tTitle        = (tData['title']         as String?) ?? 'Tournament';
        final requiredSlots = (tData['requiredSlots'] as num?)?.toInt() ?? 1;

        // ── Step 2: Status must be upcoming ─────────────────────────────
        if (status != 'upcoming') {
          throw Exception('Tournament is no longer accepting registrations.');
        }

        // ── Step 3: Slots available ──────────────────────────────────────
        if (joinedPlayers >= maxPlayers) {
          throw Exception('Tournament is full.');
        }

        // ── Step 4: Not already registered ──────────────────────────────
        final participantSnap = await txn.get(participantRef);
        if (participantSnap.exists) {
          throw Exception('You are already registered for this tournament.');
        }

        // ── Step 5: Wallet balance check ─────────────────────────────────
        final uSnap = await txn.get(userRef);
        if (!uSnap.exists) throw Exception('User profile not found.');

        final uData   = uSnap.data()!;
        final balance = (uData['walletBalance'] as num?)?.toDouble() ?? 0.0;

        if (balance < entryFee) {
          throw Exception(
            'Insufficient wallet balance. '
            'Required: ₹${entryFee.toStringAsFixed(2)}, '
            'Available: ₹${balance.toStringAsFixed(2)}.',
          );
        }

        // Validate minimum slot count.
        if (slots.length < requiredSlots) {
          throw Exception(
            'This tournament requires at least $requiredSlots player(s) per team.',
          );
        }

        // ── Step 6: Deduct wallet balance ────────────────────────────────
        if (entryFee > 0) {
          txn.update(userRef, {
            'walletBalance': FieldValue.increment(-entryFee),
          });
        }

        // ── Step 7: Increment joinedPlayers ──────────────────────────────
        txn.update(tRef, {'joinedPlayers': FieldValue.increment(1)});

        // ── Step 8: Create participant document ──────────────────────────
        //
        // PRIORITY 0: Store ALL slots (leader + all teammates).
        // Each slot serialised via TeamSlot.toMap().
        // Additional convenience fields for admin panel queries.

        // Build the serialised slot list.
        final slotsData = slots.map((s) => s.toMap()).toList();

        // Build teammate IGN list (all slots including leader) for quick display.
        final teamIgns = slots.map((s) => s.ign.trim()).toList();

        // Build teammate UID list (non-empty gameUids) for admin search.
        final teamUids = slots
            .where((s) => s.gameUid.trim().isNotEmpty)
            .map((s) => s.gameUid.trim())
            .toList();

        txn.set(participantRef, {
          // Leader identity (slot 0 always the joining user).
          'userId':     user.uid,
          'userName':   (profile['name']       as String?) ?? user.displayName ?? 'Unknown',
          'userEmail':  (profile['email']      as String?) ?? user.email       ?? '',
          'readableId': profile['readableId']  as String?,
          'ign':        slots.first.ign,

          // PRIORITY 0: Full team slot data.
          'teamSlots':  slotsData,
          'teamSize':   slots.length,
          'teamIgns':   teamIgns,
          'teamUids':   teamUids,

          // Result fields (set to defaults; updated by admin after match).
          'joinedAt':   FieldValue.serverTimestamp(),
          'status':     'registered',
          'placement':  0,
          'kills':      0,
          'winnings':   0.0,
        });

        // ── Step 9: Create transaction record ────────────────────────────
        if (entryFee > 0) {
          final txnDocRef = userRef.collection('transactions').doc();
          txn.set(txnDocRef, {
            'type':         'tournament_entry',
            'amount':       entryFee,
            'status':       'completed',
            'description':  'Tournament Entry - $tTitle',
            'tournamentId': tournamentId,
            'createdAt':    FieldValue.serverTimestamp(),
            'isCredit':     false,
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
  // PLAYER LOOKUP HELPERS (unchanged from F1)
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
  // ONE-TIME READ (unchanged from F1)
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
  // CACHE REFRESH (unchanged from F1)
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