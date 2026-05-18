// lib/admin/services/admin_tournament_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Tournament Service
// Full tournament lifecycle management:
//   createTournament, updateTournament, updateStatus,
//   distributePrizes (WriteBatch), cancelWithRefund (WriteBatch),
//   room credential management, feature toggle
// NEVER import this from the main app — admin-only
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/app_secrets.dart';
import '../auth/admin_auth_service.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

class AdminTournament {
  final String    id;
  final String    title;
  final String    subtitle;
  final String?   bannerUrl;
  final double    prizePool;
  final double    entryFee;
  final int       maxPlayers;
  final int       joinedPlayers;
  final String    status;         // 'upcoming' | 'live' | 'completed' | 'cancelled'
  final String    tournamentType; // 'battle_royale' | 'clash_squad' | 'lone_wolf' | 'league'
  final String    mode;           // 'Squad' | 'Duo' | 'Solo'
  final String    map;
  final Timestamp? startTime;
  final bool      featured;
  final String?   roomId;
  final String?   roomPassword;
  final Timestamp? roomRevealTime;
  final String?   rules;
  final String    rewardType;     // 'survival' | 'kill' | 'position' | 'mixed'
  final double    killReward;
  final double    survivalReward;
  final Map<String, dynamic> positions; // rank → amount
  final String?   rewardDescription;
  final int       minimumLevel;
  final Timestamp? createdAt;
  final String    createdBy;
  final bool      prizesDistributed;

  const AdminTournament({
    required this.id,
    required this.title,
    required this.subtitle,
    this.bannerUrl,
    required this.prizePool,
    required this.entryFee,
    required this.maxPlayers,
    required this.joinedPlayers,
    required this.status,
    required this.tournamentType,
    required this.mode,
    required this.map,
    this.startTime,
    required this.featured,
    this.roomId,
    this.roomPassword,
    this.roomRevealTime,
    this.rules,
    required this.rewardType,
    required this.killReward,
    required this.survivalReward,
    required this.positions,
    this.rewardDescription,
    required this.minimumLevel,
    this.createdAt,
    required this.createdBy,
    required this.prizesDistributed,
  });

  factory AdminTournament.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AdminTournament(
      id:                 doc.id,
      title:              (d['title']              as String?) ?? 'Unnamed',
      subtitle:           (d['subtitle']           as String?) ?? '',
      bannerUrl:           d['bannerUrl']           as String?,
      prizePool:          (d['prizePool']           as num?)?.toDouble()  ?? 0.0,
      entryFee:           (d['entryFee']            as num?)?.toDouble()  ?? 0.0,
      maxPlayers:         (d['maxPlayers']          as num?)?.toInt()     ?? 0,
      joinedPlayers:      (d['joinedPlayers']       as num?)?.toInt()     ?? 0,
      status:             (d['status']              as String?) ?? 'upcoming',
      tournamentType:     (d['tournamentType']      as String?) ?? 'battle_royale',
      mode:               (d['mode']               as String?) ?? 'Squad',
      map:                (d['map']                as String?) ?? 'Bermuda',
      startTime:           d['startTime']           as Timestamp?,
      featured:           (d['featured']            as bool?)   ?? false,
      roomId:              d['roomId']              as String?,
      roomPassword:        d['roomPassword']        as String?,
      roomRevealTime:      d['roomRevealTime']      as Timestamp?,
      rules:               d['rules']               as String?,
      rewardType:         (d['rewardType']          as String?) ?? 'position',
      killReward:         (d['killReward']          as num?)?.toDouble()  ?? 0.0,
      survivalReward:     (d['survivalReward']      as num?)?.toDouble()  ?? 0.0,
      positions:          (d['positions']           as Map<String, dynamic>?) ?? {},
      rewardDescription:   d['rewardDescription']   as String?,
      minimumLevel:       (d['minimumLevel']        as num?)?.toInt()     ?? 0,
      createdAt:           d['createdAt']           as Timestamp?,
      createdBy:          (d['createdBy']           as String?) ?? '',
      prizesDistributed:  (d['prizesDistributed']   as bool?)   ?? false,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'title':             title,
    'subtitle':          subtitle,
    if (bannerUrl != null) 'bannerUrl': bannerUrl,
    'prizePool':         prizePool,
    'entryFee':          entryFee,
    'maxPlayers':        maxPlayers,
    'joinedPlayers':     joinedPlayers,
    'status':            status,
    'tournamentType':    tournamentType,
    'mode':              mode,
    'map':               map,
    if (startTime != null) 'startTime': startTime,
    'featured':          featured,
    if (roomId != null) 'roomId': roomId,
    if (roomPassword != null) 'roomPassword': roomPassword,
    if (roomRevealTime != null) 'roomRevealTime': roomRevealTime,
    if (rules != null) 'rules': rules,
    'rewardType':        rewardType,
    'killReward':        killReward,
    'survivalReward':    survivalReward,
    'positions':         positions,
    if (rewardDescription != null) 'rewardDescription': rewardDescription,
    'minimumLevel':      minimumLevel,
    'prizesDistributed': false,
    'createdAt':         FieldValue.serverTimestamp(),
    'createdBy':         createdBy,
  };
}

class AdminParticipant {
  final String    uid;
  final String    name;
  final String    ign;
  final String    email;
  final Timestamp? joinedAt;
  final String    status;   // 'registered' | 'disqualified'
  final int       placement;
  final int       kills;
  final double    winnings;

  const AdminParticipant({
    required this.uid,
    required this.name,
    required this.ign,
    required this.email,
    this.joinedAt,
    required this.status,
    required this.placement,
    required this.kills,
    required this.winnings,
  });

  factory AdminParticipant.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AdminParticipant(
      uid:       doc.id,
      name:      (d['name']      as String?) ?? (d['userName'] as String?) ?? 'Unknown',
      ign:       (d['ign']       as String?) ?? '',
      email:     (d['email']     as String?) ?? (d['userEmail'] as String?) ?? '',
      joinedAt:   d['joinedAt']  as Timestamp?,
      status:    (d['status']    as String?) ?? 'registered',
      placement: (d['placement'] as num?)?.toInt()    ?? 0,
      kills:     (d['kills']     as num?)?.toInt()    ?? 0,
      winnings:  (d['winnings']  as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PrizeEntry {
  final String uid;
  final String playerName;
  final double amount;
  final int    placement;

  const PrizeEntry({
    required this.uid,
    required this.playerName,
    required this.amount,
    required this.placement,
  });
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────
class AdminTournamentService {
  AdminTournamentService._();
  static final AdminTournamentService instance = AdminTournamentService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Helpers ──────────────────────────────────
  String get _adminUid   => AdminAuthService.instance.currentUser?.uid   ?? 'unknown';
  String get _adminEmail => AdminAuthService.instance.currentUser?.email ?? 'Unknown Admin';

  // ──────────────────────────────────────────────────────
  // STREAM: all tournaments (realtime, ordered by startTime desc)
  // ──────────────────────────────────────────────────────
  Stream<List<AdminTournament>> tournamentsStream({String? statusFilter}) {
    Query<Map<String, dynamic>> q = _db.collection('tournaments');
    if (statusFilter != null && statusFilter != 'all') {
      q = q.where('status', isEqualTo: statusFilter);
    }
    q = q.orderBy('createdAt', descending: true);
    return q.snapshots().map((snap) =>
        snap.docs.map((d) => AdminTournament.fromDoc(d)).toList());
  }

  // ──────────────────────────────────────────────────────
  // STREAM: participants for a tournament
  // ──────────────────────────────────────────────────────
  Stream<List<AdminParticipant>> participantsStream(String tournamentId) {
    return _db
        .collection('tournaments')
        .doc(tournamentId)
        .collection('participants')
        .orderBy('joinedAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AdminParticipant.fromDoc(d)).toList());
  }

  // ──────────────────────────────────────────────────────
  // CREATE TOURNAMENT
  // ──────────────────────────────────────────────────────
  Future<String> createTournament(Map<String, dynamic> data) async {
    data['createdBy']         = _adminUid;
    data['createdAt']         = FieldValue.serverTimestamp();
    data['joinedPlayers']     = 0;
    data['prizesDistributed'] = false;
    data.putIfAbsent('status', () => 'upcoming');

    final docRef = await _db.collection('tournaments').add(data);
    final logRef  = _db.collection('admin_logs').doc();
    final batch   = _db.batch();

    batch.set(logRef, {
      'action':     'tournament_created',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  docRef.id,
      'details': {
        'tournamentId': docRef.id,
        'title':        data['title'] ?? '',
        'prizePool':    data['prizePool'] ?? 0,
        'entryFee':     data['entryFee'] ?? 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    _fireTournamentCreatedWebhook(
      id:        docRef.id,
      title:     (data['title'] as String?) ?? 'New Tournament',
      prizePool: (data['prizePool'] as num?)?.toDouble() ?? 0.0,
      entryFee:  (data['entryFee']  as num?)?.toDouble() ?? 0.0,
      status:    (data['status']    as String?) ?? 'upcoming',
    );

    return docRef.id;
  }

  // ──────────────────────────────────────────────────────
  // UPDATE TOURNAMENT (fields only — not status)
  // ──────────────────────────────────────────────────────
  Future<void> updateTournament(String id, Map<String, dynamic> updates) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('tournaments').doc(id).update(updates);

    final logRef = _db.collection('admin_logs').doc();
    await logRef.set({
      'action':     'tournament_updated',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  id,
      'details': {
        'tournamentId': id,
        'updatedFields': updates.keys.toList(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ──────────────────────────────────────────────────────
  // UPDATE STATUS (validated one-direction transitions)
  // upcoming → live → completed
  // any → cancelled (before live)
  // ──────────────────────────────────────────────────────
  Future<void> updateStatus(String id, String newStatus) async {
    final snap = await _db.collection('tournaments').doc(id).get();
    if (!snap.exists) throw Exception('Tournament not found.');
    final current = (snap.data() ?? {})['status'] as String? ?? 'upcoming';

    _validateStatusTransition(current, newStatus);

    final batch  = _db.batch();
    final tRef   = _db.collection('tournaments').doc(id);
    final logRef = _db.collection('admin_logs').doc();

    batch.update(tRef, {
      'status':    newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(logRef, {
      'action':     'tournament_status_changed',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  id,
      'details': {
        'tournamentId': id,
        'fromStatus':   current,
        'toStatus':     newStatus,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  void _validateStatusTransition(String from, String to) {
    const valid = {
      'upcoming':  {'live', 'cancelled'},
      'live':      {'completed'},
      'completed': <String>{},
      'cancelled': <String>{},
    };
    final allowed = valid[from] ?? {};
    if (!allowed.contains(to)) {
      throw Exception(
          'Invalid status transition: $from → $to. '
          'Allowed from "$from": ${allowed.isEmpty ? "none" : allowed.join(", ")}');
    }
  }

  // ──────────────────────────────────────────────────────
  // FEATURE / UN-FEATURE TOGGLE
  // ──────────────────────────────────────────────────────
  Future<void> setFeatured(String id, String title, bool featured) async {
    final batch  = _db.batch();
    final tRef   = _db.collection('tournaments').doc(id);
    final logRef = _db.collection('admin_logs').doc();

    batch.update(tRef, {'featured': featured, 'updatedAt': FieldValue.serverTimestamp()});
    batch.set(logRef, {
      'action':     featured ? 'tournament_featured' : 'tournament_unfeatured',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  id,
      'details': {'tournamentId': id, 'title': title, 'featured': featured},
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // DELETE TOURNAMENT (only upcoming with 0 participants)
  // ──────────────────────────────────────────────────────
  Future<void> deleteTournament(String id, String title) async {
    final snap = await _db.collection('tournaments').doc(id).get();
    if (!snap.exists) throw Exception('Tournament not found.');
    final data = snap.data() ?? {};

    if (data['status'] != 'upcoming') {
      throw Exception('Only upcoming tournaments can be deleted. Cancel it first.');
    }
    if ((data['joinedPlayers'] as num?)?.toInt() != 0) {
      throw Exception('Cannot delete — participants are already registered. Cancel with refund instead.');
    }

    final batch  = _db.batch();
    final tRef   = _db.collection('tournaments').doc(id);
    final logRef = _db.collection('admin_logs').doc();

    batch.delete(tRef);
    batch.set(logRef, {
      'action':     'tournament_deleted',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  id,
      'details': {'tournamentId': id, 'title': title},
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // UPDATE ROOM CREDENTIALS
  // ──────────────────────────────────────────────────────
  Future<void> updateRoomCredentials({
    required String id,
    required String title,
    required String? roomId,
    required String? roomPassword,
    Timestamp? roomRevealTime,
  }) async {
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (roomId        != null) updates['roomId']          = roomId;
    if (roomPassword  != null) updates['roomPassword']    = roomPassword;
    if (roomRevealTime != null) updates['roomRevealTime'] = roomRevealTime;

    final batch  = _db.batch();
    final tRef   = _db.collection('tournaments').doc(id);
    final logRef = _db.collection('admin_logs').doc();

    batch.update(tRef, updates);
    batch.set(logRef, {
      'action':     'room_credentials_updated',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  id,
      'details': {
        'tournamentId': id,
        'title':        title,
        'hasRoomId':    roomId != null,
        'hasPassword':  roomPassword != null,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    _fireRoomCredentialsWebhook(id: id, title: title, roomId: roomId ?? '', adminEmail: _adminEmail);
  }

  // ──────────────────────────────────────────────────────
  // UPDATE PARTICIPANT RESULT (placement, kills, winnings)
  // ──────────────────────────────────────────────────────
  Future<void> updateParticipantResult({
    required String tournamentId,
    required String uid,
    required int    placement,
    required int    kills,
    required double winnings,
  }) async {
    await _db
        .collection('tournaments')
        .doc(tournamentId)
        .collection('participants')
        .doc(uid)
        .update({
      'placement': placement,
      'kills':     kills,
      'winnings':  winnings,
    });
  }

  // ──────────────────────────────────────────────────────
  // DISQUALIFY PARTICIPANT
  // ──────────────────────────────────────────────────────
  Future<void> disqualifyParticipant({
    required String tournamentId,
    required String uid,
    required String playerName,
  }) async {
    final batch  = _db.batch();
    final pRef   = _db.collection('tournaments').doc(tournamentId)
                      .collection('participants').doc(uid);
    final logRef = _db.collection('admin_logs').doc();

    batch.update(pRef, {'status': 'disqualified'});
    batch.set(logRef, {
      'action':     'participant_disqualified',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  uid,
      'details': {
        'tournamentId': tournamentId,
        'playerName':   playerName,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // REMOVE PARTICIPANT
  // ──────────────────────────────────────────────────────
  Future<void> removeParticipant({
    required String tournamentId,
    required String uid,
    required String playerName,
    required double entryFee,
    required bool   refund,
  }) async {
    final batch  = _db.batch();
    final pRef   = _db.collection('tournaments').doc(tournamentId)
                      .collection('participants').doc(uid);
    final tRef   = _db.collection('tournaments').doc(tournamentId);
    final logRef = _db.collection('admin_logs').doc();

    batch.delete(pRef);
    batch.update(tRef, {'joinedPlayers': FieldValue.increment(-1)});

    if (refund && entryFee > 0) {
      final userRef = _db.collection('users').doc(uid);
      final txnRef  = userRef.collection('transactions').doc();
      batch.update(userRef, {'walletBalance': FieldValue.increment(entryFee)});
      batch.set(txnRef, {
        'type':         'refund',
        'amount':       entryFee,
        'status':       'completed',
        'description':  'Entry fee refunded — removed from tournament',
        'tournamentId': tournamentId,
        'createdAt':    FieldValue.serverTimestamp(),
      });
    }

    batch.set(logRef, {
      'action':     'participant_removed',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  uid,
      'details': {
        'tournamentId': tournamentId,
        'playerName':   playerName,
        'refunded':     refund,
        'entryFee':     entryFee,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // DISTRIBUTE PRIZES — WriteBatch
  // 1. For each winner: walletBalance += amount, totalEarnings += amount
  // 2. For each winner: create transactions/{id} type=winnings
  // 3. Create admin_logs entry action=prize_distributed
  // 4. Set tournament status = 'completed', prizesDistributed = true
  // 5. Fire Discord embed
  // ──────────────────────────────────────────────────────
  Future<void> distributePrizes({
    required String           tournamentId,
    required String           tournamentTitle,
    required List<PrizeEntry> entries,
  }) async {
    if (entries.isEmpty) throw Exception('No prize entries provided.');

    // Guard: prevent double distribution
    final snap = await _db.collection('tournaments').doc(tournamentId).get();
    if (!snap.exists) throw Exception('Tournament not found.');
    final data = snap.data() ?? {};
    if (data['prizesDistributed'] == true) {
      throw Exception('Prizes have already been distributed for this tournament.');
    }

    final tRef   = _db.collection('tournaments').doc(tournamentId);
    final logRef = _db.collection('admin_logs').doc();

    // WriteBatch supports up to 500 ops; for very large tournaments
    // with 100+ winners call in chunks. Normal tournaments <50 winners.
    final batch = _db.batch();

    double totalDistributed = 0.0;

    for (final entry in entries) {
      final userRef = _db.collection('users').doc(entry.uid);
      final txnRef  = userRef.collection('transactions').doc();

      batch.update(userRef, {
        'walletBalance': FieldValue.increment(entry.amount),
        'totalEarnings': FieldValue.increment(entry.amount),
      });

      batch.set(txnRef, {
        'type':         'winnings',
        'amount':       entry.amount,
        'status':       'completed',
        'description':  'Tournament winnings — $tournamentTitle (Rank ${entry.placement})',
        'tournamentId': tournamentId,
        'createdAt':    FieldValue.serverTimestamp(),
      });

      // Update participant result
      final pRef = tRef.collection('participants').doc(entry.uid);
      batch.update(pRef, {
        'placement': entry.placement,
        'winnings':  entry.amount,
        'status':    'winner',
      });

      totalDistributed += entry.amount;
    }

    // Mark tournament completed + distributed
    batch.update(tRef, {
      'status':            'completed',
      'prizesDistributed': true,
      'updatedAt':         FieldValue.serverTimestamp(),
    });

    // Admin log
    batch.set(logRef, {
      'action':     'prize_distributed',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  tournamentId,
      'details': {
        'tournamentId':     tournamentId,
        'tournamentTitle':  tournamentTitle,
        'winnersCount':     entries.length,
        'totalDistributed': totalDistributed,
        'winners': entries.map((e) => {
          'uid':        e.uid,
          'name':       e.playerName,
          'amount':     e.amount,
          'placement':  e.placement,
        }).toList(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    _firePrizeDistributedWebhook(
      tournamentId:     tournamentId,
      tournamentTitle:  tournamentTitle,
      entries:          entries,
      totalDistributed: totalDistributed,
    );
  }

  // ──────────────────────────────────────────────────────
  // CANCEL WITH REFUND — WriteBatch
  // 1. Read all participants
  // 2. For each: walletBalance += entryFee
  // 3. For each: create transactions/{id} type=refund
  // 4. Set tournament status = 'cancelled'
  // 5. Create admin_logs entry action=tournament_cancelled
  // 6. Fire Discord webhook
  // ──────────────────────────────────────────────────────
  Future<void> cancelWithRefund({
    required String tournamentId,
    required String tournamentTitle,
    required double entryFee,
  }) async {
    final snap = await _db.collection('tournaments').doc(tournamentId).get();
    if (!snap.exists) throw Exception('Tournament not found.');
    final tData = snap.data() ?? {};

    final currentStatus = (tData['status'] as String?) ?? 'upcoming';
    if (currentStatus == 'completed' || currentStatus == 'cancelled') {
      throw Exception('Cannot cancel — tournament is already $currentStatus.');
    }

    // Read all participants
    final participantSnap = await _db
        .collection('tournaments')
        .doc(tournamentId)
        .collection('participants')
        .get();

    final tRef   = _db.collection('tournaments').doc(tournamentId);
    final logRef = _db.collection('admin_logs').doc();

    final batch = _db.batch();
    int refundCount = 0;

    if (entryFee > 0) {
      for (final pDoc in participantSnap.docs) {
        final uid     = pDoc.id;
        final pData   = pDoc.data();
        final pName   = (pData['name'] as String?) ?? (pData['userName'] as String?) ?? 'Unknown';
        final userRef = _db.collection('users').doc(uid);
        final txnRef  = userRef.collection('transactions').doc();

        batch.update(userRef, {
          'walletBalance': FieldValue.increment(entryFee),
        });

        batch.set(txnRef, {
          'type':         'refund',
          'amount':       entryFee,
          'status':       'completed',
          'description':  'Entry fee refunded — $tournamentTitle cancelled',
          'tournamentId': tournamentId,
          'playerName':   pName,
          'createdAt':    FieldValue.serverTimestamp(),
        });

        refundCount++;
      }
    }

    batch.update(tRef, {
      'status':    'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(logRef, {
      'action':     'tournament_cancelled',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  tournamentId,
      'details': {
        'tournamentId':   tournamentId,
        'tournamentTitle': tournamentTitle,
        'refundCount':    refundCount,
        'entryFee':       entryFee,
        'totalRefunded':  refundCount * entryFee,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    _fireCancellationWebhook(
      tournamentId:   tournamentId,
      tournamentTitle: tournamentTitle,
      refundCount:    refundCount,
      entryFee:       entryFee,
    );
  }

  // ──────────────────────────────────────────────────────
  // DUPLICATE TOURNAMENT
  // ──────────────────────────────────────────────────────
  Future<String> duplicateTournament(AdminTournament source) async {
    final newData = source.toCreateMap();
    newData['title']         = '${source.title} (Copy)';
    newData['status']        = 'upcoming';
    newData['joinedPlayers'] = 0;
    newData['featured']      = false;
    newData['prizesDistributed'] = false;
    // Clear room info for safety
    newData.remove('roomId');
    newData.remove('roomPassword');
    newData.remove('roomRevealTime');

    return createTournament(newData);
  }

  // ──────────────────────────────────────────────────────
  // ANALYTICS SNAPSHOT (one-time read)
  // ──────────────────────────────────────────────────────
  Future<TournamentAnalytics> getAnalytics() async {
    final snap = await _db.collection('tournaments').get();
    int upcoming = 0, live = 0, completed = 0, cancelled = 0;
    double totalPrize = 0, totalEntry = 0, totalDistributed = 0;

    for (final doc in snap.docs) {
      final d = doc.data();
      final status  = (d['status'] as String?) ?? 'upcoming';
      final prize   = (d['prizePool']     as num?)?.toDouble() ?? 0.0;
      final fee     = (d['entryFee']      as num?)?.toDouble() ?? 0.0;
      final joined  = (d['joinedPlayers'] as num?)?.toInt()    ?? 0;
      final paid    = (d['prizesDistributed'] as bool?) ?? false;

      switch (status) {
        case 'upcoming':  upcoming++;  break;
        case 'live':      live++;      break;
        case 'completed': completed++; break;
        case 'cancelled': cancelled++; break;
      }

      totalPrize   += prize;
      totalEntry   += fee * joined;
      if (paid) totalDistributed += prize;
    }

    return TournamentAnalytics(
      total:            snap.docs.length,
      upcoming:         upcoming,
      live:             live,
      completed:        completed,
      cancelled:        cancelled,
      totalPrizePools:  totalPrize,
      totalEntryCollected: totalEntry,
      totalDistributed: totalDistributed,
    );
  }

  // ──────────────────────────────────────────────────────
  // DISCORD WEBHOOKS
  // ──────────────────────────────────────────────────────
  void _fireTournamentCreatedWebhook({
    required String id,
    required String title,
    required double prizePool,
    required double entryFee,
    required String status,
  }) {
    _sendWebhookAsync(
      webhook: AppSecrets.depositWebhook,
      payload: {
        'embeds': [{
          'title': '🏆  New Tournament Created',
          'color': 0xFFCC44,
          'fields': [
            {'name': '🎮 Title',       'value': title,                               'inline': true},
            {'name': '🆔 ID',          'value': '`$id`',                             'inline': true},
            {'name': '💰 Prize Pool',  'value': '₹${prizePool.toStringAsFixed(0)}',  'inline': true},
            {'name': '🎟 Entry Fee',   'value': entryFee > 0 ? '₹${entryFee.toStringAsFixed(0)}' : 'FREE', 'inline': true},
            {'name': '📊 Status',      'value': status.toUpperCase(),                'inline': true},
            {'name': '👮 Created by',  'value': _adminEmail,                         'inline': true},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Tournament Management'},
        }],
      },
    ).catchError((e) => debugPrint('[AdminTournamentService] webhook error: $e'));
  }

  void _firePrizeDistributedWebhook({
    required String           tournamentId,
    required String           tournamentTitle,
    required List<PrizeEntry> entries,
    required double           totalDistributed,
  }) {
    final topWinners = entries
        .where((e) => e.placement <= 3)
        .map((e) => '#${e.placement} ${e.playerName}: ₹${e.amount.toStringAsFixed(0)}')
        .join('\n');

    _sendWebhookAsync(
      webhook: AppSecrets.depositWebhook,
      payload: {
        'embeds': [{
          'title': '🎁  Prizes Distributed',
          'color': 0x44FF99,
          'fields': [
            {'name': '🏆 Tournament',    'value': tournamentTitle,                          'inline': true},
            {'name': '👥 Winners',       'value': entries.length.toString(),                'inline': true},
            {'name': '💰 Total Paid',    'value': '₹${totalDistributed.toStringAsFixed(0)}','inline': true},
            if (topWinners.isNotEmpty) {'name': '🥇 Top Winners', 'value': topWinners, 'inline': false},
            {'name': '👮 Distributed by','value': _adminEmail,                             'inline': true},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Prize Distribution'},
        }],
      },
    ).catchError((e) => debugPrint('[AdminTournamentService] webhook error: $e'));
  }

  void _fireCancellationWebhook({
    required String tournamentId,
    required String tournamentTitle,
    required int    refundCount,
    required double entryFee,
  }) {
    _sendWebhookAsync(
      webhook: AppSecrets.withdrawWebhook,
      payload: {
        'embeds': [{
          'title': '❌  Tournament Cancelled + Refunds Issued',
          'color': 0xFF4466,
          'fields': [
            {'name': '🏆 Tournament',     'value': tournamentTitle,                               'inline': true},
            {'name': '💸 Refunds Issued', 'value': refundCount.toString(),                        'inline': true},
            {'name': '💰 Per Refund',     'value': entryFee > 0 ? '₹${entryFee.toStringAsFixed(0)}' : 'FREE', 'inline': true},
            {'name': '💵 Total Refunded', 'value': '₹${(refundCount * entryFee).toStringAsFixed(0)}', 'inline': true},
            {'name': '👮 Cancelled by',   'value': _adminEmail,                                  'inline': true},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Tournament Cancellation'},
        }],
      },
    ).catchError((e) => debugPrint('[AdminTournamentService] webhook error: $e'));
  }

  void _fireRoomCredentialsWebhook({
    required String id,
    required String title,
    required String roomId,
    required String adminEmail,
  }) {
    _sendWebhookAsync(
      webhook: AppSecrets.depositWebhook,
      payload: {
        'embeds': [{
          'title': '🔑  Room Credentials Updated',
          'color': 0x9D55FF,
          'fields': [
            {'name': '🏆 Tournament', 'value': title,       'inline': true},
            {'name': '🆔 ID',         'value': '`$id`',     'inline': true},
            {'name': '👮 Updated by', 'value': adminEmail,  'inline': true},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Room Management'},
        }],
      },
    ).catchError((e) => debugPrint('[AdminTournamentService] webhook error: $e'));
  }

  Future<void> _sendWebhookAsync({
    required String webhook,
    required Map<String, dynamic> payload,
  }) async {
    await http.post(
      Uri.parse(webhook),
      headers: {'Content-Type': 'application/json'},
      body:    jsonEncode(payload),
    );
  }
}

// ─────────────────────────────────────────────
// ANALYTICS MODEL
// ─────────────────────────────────────────────
class TournamentAnalytics {
  final int    total;
  final int    upcoming;
  final int    live;
  final int    completed;
  final int    cancelled;
  final double totalPrizePools;
  final double totalEntryCollected;
  final double totalDistributed;

  const TournamentAnalytics({
    required this.total,
    required this.upcoming,
    required this.live,
    required this.completed,
    required this.cancelled,
    required this.totalPrizePools,
    required this.totalEntryCollected,
    required this.totalDistributed,
  });
}