// lib/services/user_activity_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — User Activity Service
//
// Centralizes activity tracking and recent-activity reading.
// Profile screen and any other consumer reads from this service.
// Activity data is derived from:
//   • users/{uid}/transactions (deposits, withdrawals, winnings, refunds, entries)
//   • tournaments/{id}/participants/{uid} (join/win events)
//
// No separate activity collection is written — we read from existing
// Firestore data to avoid double-writes.
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────
// ACTIVITY ITEM MODEL
// ─────────────────────────────────────────────

enum ActivityType {
  joinedTournament,
  wonTournament,
  depositApproved,
  withdrawalApproved,
  refund,
  adminAdjustment,
  tournamentEntry,
}

class ActivityItem {
  final ActivityType type;
  final String       title;
  final String       subtitle;
  final double?      amount;
  final DateTime     createdAt;
  final String?      tournamentId;

  const ActivityItem({
    required this.type,
    required this.title,
    required this.subtitle,
    this.amount,
    required this.createdAt,
    this.tournamentId,
  });

  factory ActivityItem.fromTransaction(DocumentSnapshot doc) {
    final d         = doc.data() as Map<String, dynamic>? ?? {};
    final type      = d['type']        as String? ?? '';
    final amount    = (d['amount']     as num?)?.toDouble() ?? 0.0;
    final desc      = d['description'] as String? ?? '';
    final tId       = d['tournamentId'] as String?;
    final createdAt = (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now();

    ActivityType actType;
    String title;
    String subtitle;

    switch (type) {
      case 'deposit':
        actType  = ActivityType.depositApproved;
        title    = 'Deposit Approved';
        subtitle = desc.isNotEmpty ? desc : '₹${amount.toStringAsFixed(0)} added to wallet';
        break;
      case 'withdrawal':
        actType  = ActivityType.withdrawalApproved;
        title    = 'Withdrawal Approved';
        subtitle = desc.isNotEmpty ? desc : '₹${amount.toStringAsFixed(0)} withdrawn';
        break;
      case 'winnings':
        actType  = ActivityType.wonTournament;
        title    = 'Tournament Won';
        subtitle = desc.isNotEmpty ? desc : '₹${amount.toStringAsFixed(0)} prize credited';
        break;
      case 'refund':
        actType  = ActivityType.refund;
        title    = 'Refund Received';
        subtitle = desc.isNotEmpty ? desc : '₹${amount.toStringAsFixed(0)} refunded';
        break;
      case 'tournament_entry':
        actType  = ActivityType.tournamentEntry;
        title    = 'Tournament Joined';
        subtitle = desc.isNotEmpty ? desc : '₹${amount.toStringAsFixed(0)} entry fee paid';
        break;
      case 'manual_adjustment':
        actType  = ActivityType.adminAdjustment;
        title    = 'Balance Adjusted';
        subtitle = desc.isNotEmpty ? desc : 'Admin balance adjustment';
        break;
      default:
        actType  = ActivityType.tournamentEntry;
        title    = _capitalize(type.replaceAll('_', ' '));
        subtitle = desc.isNotEmpty ? desc : '';
    }

    return ActivityItem(
      type:         actType,
      title:        title,
      subtitle:     subtitle,
      amount:       amount > 0 ? amount : null,
      createdAt:    createdAt,
      tournamentId: tId,
    );
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ─────────────────────────────────────────────
// USER ACTIVITY SERVICE
// ─────────────────────────────────────────────

class UserActivityService {
  UserActivityService._();
  static final UserActivityService instance = UserActivityService._();

  final FirebaseFirestore _db   = FirebaseFirestore.instance;
  final FirebaseAuth      _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ── Recent Activity Stream ────────────────────────────────────────────────
  //
  // Returns the 20 most recent activity items derived from the transactions
  // subcollection. This is a realtime stream — updates whenever a new
  // transaction is written (deposit approved, prize distributed, etc.).
  //
  // Filters: only show activity types that are meaningful to the player.
  // Excludes: pending deposits / pending withdrawals (not yet processed).

  Stream<List<ActivityItem>> recentActivityStream({int limit = 20}) {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final items = <ActivityItem>[];
          for (final doc in snap.docs) {
            try {
              final d      = doc.data();
              final _   = d['type'] as String? ?? '';
              final status = d['status'] as String? ?? '';

              // Only show completed/processed transactions.
              // Skip pending tournament_entry rows with no status.
              if (status == 'pending') continue;

              items.add(ActivityItem.fromTransaction(doc));
            } catch (e) {
              debugPrint('[UserActivityService] parse error: $e');
            }
          }
          return items;
        });
  }

  // ── One-time fetch ────────────────────────────────────────────────────────

  Future<List<ActivityItem>> getRecentActivity({int limit = 20}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final items = <ActivityItem>[];
      for (final doc in snap.docs) {
        try {
          final d      = doc.data();
          final status = d['status'] as String? ?? '';
          if (status == 'pending') continue;
          items.add(ActivityItem.fromTransaction(doc));
        } catch (_) {}
      }
      return items;
    } catch (e) {
      debugPrint('[UserActivityService] getRecentActivity error: $e');
      return [];
    }
  }

  // ── Log tournament join ───────────────────────────────────────────────────
  //
  // Called after a successful joinWithTeam() transaction.
  // The tournament_entry transaction is already written by TournamentService;
  // this optionally adds a 'joined_tournament' marker if needed for rich
  // activity display. Currently we derive join events from tournament_entry
  // transactions, so this is a no-op — the hook exists for future use.

  Future<void> logTournamentJoin({
    required String tournamentId,
    required String tournamentTitle,
  }) async {
    // Derived from tournament_entry transactions — no separate write needed.
    // Keeping this hook for future custom activity log entries.
    debugPrint('[UserActivityService] join logged: $tournamentTitle');
  }
}