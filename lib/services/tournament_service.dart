// lib/services/tournament_service.dart
// ─────────────────────────────────────────────
// TOURNAMENT SERVICE
// All Firestore queries live here.
// UI widgets just call these methods — no
// Firestore logic leaks into screen files.
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tournament_model.dart';

class TournamentService {
  // Singleton so we always reuse the same instance
  TournamentService._();
  static final TournamentService instance = TournamentService._();

  // Firestore reference
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collection name — change here if you rename it in Firestore
  static const String _collection = 'tournaments';

  // ────────────────────────────────────────────
  // REAL-TIME STREAMS
  // Use these in StreamBuilder widgets so the
  // UI updates automatically when data changes.
  // ────────────────────────────────────────────

  /// Stream of the single featured tournament.
  /// Returns null if no featured tournament exists.
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

  /// Stream of all LIVE tournaments, ordered by start time.
  Stream<List<TournamentModel>> liveTournamentsStream() {
    return _db
        .collection(_collection)
        .where('status', isEqualTo: 'live')
        .orderBy('startTime')
        .snapshots()
        .map(_docsToList);
  }

  /// Stream of upcoming tournaments (not featured, not live).
  /// Pass [limit] to cap how many cards appear.
  Stream<List<TournamentModel>> upcomingTournamentsStream({int limit = 10}) {
    return _db
        .collection(_collection)
        .where('status', isEqualTo: 'upcoming')
        .orderBy('startTime')
        .limit(limit)
        .snapshots()
        .map(_docsToList);
  }

  /// Stream for ALL tournaments — useful for an "Events" tab.
  Stream<List<TournamentModel>> allTournamentsStream() {
    return _db
        .collection(_collection)
        .orderBy('startTime')
        .snapshots()
        .map(_docsToList);
  }

  /// ✅ NEW: Real-time stream for a single tournament by ID.
  /// Used in TournamentDetailsScreen to keep joinedPlayers count fresh.
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

  /// Fetch a single tournament by ID.
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

  /// Increment joinedPlayers atomically.
  /// Call this after writing the participant document.
  /// Returns true on success.
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
  // Used by the Events tab to show joined tournaments
  // ────────────────────────────────────────────

  /// ✅ NEW: Stream of all tournaments the user has joined.
  /// Queries collectionGroup 'participants' filtered by userId.
  ///
  /// IMPORTANT: You must create a Firestore composite index for this query.
  /// Firestore will log a direct link to create it when you first run it.
  ///
  /// Firestore structure:
  ///   tournaments/{tournamentId}/participants/{userId}
  ///     - userId: String
  ///     - userName: String
  ///     - userEmail: String
  ///     - joinedAt: Timestamp
  ///     - status: String ('registered' | 'playing' | 'eliminated' | 'winner')
  Stream<List<TournamentModel>> joinedTournamentsStream(String userId) {
    // Step 1: Listen to participant records for this user
    return _db
        .collectionGroup('participants')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((participantSnap) async {
          // Step 2: Extract tournament IDs from participant documents
          final tournamentIds = participantSnap.docs
              .map((doc) => doc.reference.parent.parent?.id)
              .whereType<String>()
              .toList();

          if (tournamentIds.isEmpty) return <TournamentModel>[];

          // Step 3: Fetch tournament documents in a batch
          // Firestore 'whereIn' supports up to 30 items
          final chunks = <List<String>>[];
          for (var i = 0; i < tournamentIds.length; i += 30) {
            chunks.add(tournamentIds.sublist(
              i, i + 30 > tournamentIds.length ? tournamentIds.length : i + 30,
            ));
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
              _log('joinedTournamentsStream batch fetch', e);
            }
          }

          // Sort by start time
          tournaments.sort((a, b) {
            if (a.startTime == null && b.startTime == null) return 0;
            if (a.startTime == null) return 1;
            if (b.startTime == null) return -1;
            return a.startTime!.compareTo(b.startTime!);
          });

          return tournaments;
        });
  }

  // ────────────────────────────────────────────
  // PRIVATE HELPERS
  // ────────────────────────────────────────────

  /// Convert a QuerySnapshot into a typed list,
  /// skipping any documents that fail to parse.
  List<TournamentModel> _docsToList(QuerySnapshot snap) {
    final result = <TournamentModel>[];
    for (final doc in snap.docs) {
      try {
        result.add(TournamentModel.fromFirestore(doc));
      } catch (e) {
        _log('parsing doc ${doc.id}', e);
        // Skip bad documents instead of crashing
      }
    }
    return result;
  }

  void _log(String context, Object e) {
    // Replace with your logging solution
    // ignore: avoid_print
    print('[TournamentService] Error in $context: $e');
  }
}