// lib/services/tournament_service.dart
// ─────────────────────────────────────────────
// TOURNAMENT SERVICE  (v2)
// New additions:
//   • joinedTournamentIdsStream — lightweight set of joined IDs
//     used by HomeScreen to render joined-state badges without
//     fetching full tournament documents
//   • filteredTournamentsStream — used by AllTournamentsScreen
//     to support status + type filtering in real-time
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tournament_model.dart';

class TournamentService {
  TournamentService._();
  static final TournamentService instance = TournamentService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'tournaments';

  // ────────────────────────────────────────────
  // REAL-TIME STREAMS — HOME SCREEN
  // ────────────────────────────────────────────

  /// Single featured tournament (upcoming, featured=true).
  Stream<TournamentModel?> featuredTournamentStream() {
    return _db
        .collection(_collection)
        .where('featured', isEqualTo: true)
        .where('status', isEqualTo: 'upcoming')
        .orderBy('startTime')
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return TournamentModel.fromFirestore(snap.docs.first);
        });
  }

  /// All LIVE tournaments ordered by start time.
  Stream<List<TournamentModel>> liveTournamentsStream() {
    return _db
        .collection(_collection)
        .where('status', isEqualTo: 'live')
        .orderBy('startTime')
        .snapshots()
        .map(_docsToList);
  }

  /// Upcoming tournaments (not live, not completed).
  Stream<List<TournamentModel>> upcomingTournamentsStream({int limit = 20}) {
    return _db
        .collection(_collection)
        .where('status', isEqualTo: 'upcoming')
        .orderBy('startTime')
        .limit(limit)
        .snapshots()
        .map(_docsToList);
  }

  /// All tournaments — used as base for AllTournamentsScreen.
  Stream<List<TournamentModel>> allTournamentsStream() {
    return _db
        .collection(_collection)
        .orderBy('startTime')
        .snapshots()
        .map(_docsToList);
  }

  /// ✅ NEW: All tournaments filtered by status and/or type.
  /// Both parameters are optional — pass null to skip that filter.
  ///
  /// statusFilter: 'live' | 'upcoming' | 'completed' | null
  /// typeFilter:   'battle_royale' | 'clash_squad' | 'lone_wolf' | 'league' | null
  ///
  /// NOTE: Multiple inequality filters need a Firestore composite index.
  /// Client-side filtering is used here for simplicity and index-free operation.
  Stream<List<TournamentModel>> filteredTournamentsStream({
    String? statusFilter,
    String? typeFilter,
    int limit = 50,
  }) {
    // Start with a broad query, then filter client-side to avoid index explosion.
    Query<Map<String, dynamic>> query = _db.collection(_collection);

    // Apply status server-side (uses the existing index)
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

  /// Real-time stream for a single tournament by ID.
  Stream<TournamentModel?> tournamentByIdStream(String id) {
    return _db
        .collection(_collection)
        .doc(id)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return TournamentModel.fromFirestore(snap);
        });
  }

  // ────────────────────────────────────────────
  // ONE-TIME FETCHES
  // ────────────────────────────────────────────

  Future<TournamentModel?> getTournamentById(String id) async {
    try {
      final doc = await _db.collection(_collection).doc(id).get();
      if (!doc.exists) return null;
      return TournamentModel.fromFirestore(doc);
    } catch (e) {
      _log('getTournamentById($id)', e);
      return null;
    }
  }

  // ────────────────────────────────────────────
  // PLAYER ACTIONS
  // ────────────────────────────────────────────

  /// Atomically increment joinedPlayers counter.
  /// Call AFTER writing the participant sub-document.
  Future<bool> joinTournament(String tournamentId) async {
    try {
      await _db.collection(_collection).doc(tournamentId).update({
        'joinedPlayers': FieldValue.increment(1),
      });
      return true;
    } catch (e) {
      _log('joinTournament($tournamentId)', e);
      return false;
    }
  }

  // ────────────────────────────────────────────
  // PARTICIPANT QUERIES
  // ────────────────────────────────────────────

  /// Full tournament list the user has joined.
  /// Used by the Events tab.
  Stream<List<TournamentModel>> joinedTournamentsStream(String userId) {
    return _db
        .collectionGroup('participants')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((participantSnap) async {
          final tournamentIds = participantSnap.docs
              .map((doc) => doc.reference.parent.parent?.id)
              .whereType<String>()
              .toList();

          if (tournamentIds.isEmpty) return <TournamentModel>[];

          final chunks = <List<String>>[];
          for (var i = 0; i < tournamentIds.length; i += 30) {
            final end = (i + 30 > tournamentIds.length)
                ? tournamentIds.length
                : i + 30;
            chunks.add(tournamentIds.sublist(i, end));
          }

          final tournaments = <TournamentModel>[];
          for (final chunk in chunks) {
            try {
              final snap = await _db
                  .collection(_collection)
                  .where(FieldPath.documentId, whereIn: chunk)
                  .get();
              tournaments.addAll(_docsToList(snap));
            } catch (e) {
              _log('joinedTournamentsStream batch', e);
            }
          }

          tournaments.sort((a, b) {
            if (a.startTime == null && b.startTime == null) return 0;
            if (a.startTime == null) return 1;
            if (b.startTime == null) return -1;
            return a.startTime!.compareTo(b.startTime!);
          });

          return tournaments;
        });
  }

  /// ✅ NEW: Lightweight stream — only tournament IDs the user has joined.
  ///
  /// Used by HomeScreen to show "JOINED" badges on cards without
  /// fetching full tournament data. Much cheaper than
  /// joinedTournamentsStream for a list-view use-case.
  ///
  /// Requires the same collectionGroup index as joinedTournamentsStream.
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

  // ────────────────────────────────────────────
  // PRIVATE HELPERS
  // ────────────────────────────────────────────

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

  void _log(String ctx, Object e) {
    // ignore: avoid_print
    print('[TournamentService] Error in $ctx: $e');
  }
}