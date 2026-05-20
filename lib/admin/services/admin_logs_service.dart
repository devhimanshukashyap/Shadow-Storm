// lib/admin/services/admin_logs_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Logs Service
// Phase 5: Realtime stream, filtering, pagination, CSV export
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../auth/admin_auth_service.dart';

// ─────────────────────────────────────────────
// LOG ENTRY MODEL
// ─────────────────────────────────────────────
class AdminLogEntry {
  final String               id;
  final String               action;
  final String               adminUid;
  final String               adminEmail;
  final String               targetUid;
  final Map<String, dynamic> details;
  final Timestamp?           createdAt;

  const AdminLogEntry({
    required this.id,
    required this.action,
    required this.adminUid,
    required this.adminEmail,
    required this.targetUid,
    required this.details,
    this.createdAt,
  });

  factory AdminLogEntry.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AdminLogEntry(
      id:         doc.id,
      action:     (d['action']     as String?) ?? 'unknown',
      adminUid:   (d['adminUid']   as String?) ?? '',
      adminEmail: (d['adminEmail'] as String?) ?? 'Unknown Admin',
      targetUid:  (d['targetUid']  as String?) ?? '',
      details:    (d['details']    as Map<String, dynamic>?) ?? {},
      createdAt:   d['createdAt']  as Timestamp?,
    );
  }

  /// Matches keyword search across key fields
  bool matchesKeyword(String keyword) {
    if (keyword.isEmpty) return true;
    final kw = keyword.toLowerCase();
    return action.toLowerCase().contains(kw) ||
        adminEmail.toLowerCase().contains(kw) ||
        targetUid.toLowerCase().contains(kw) ||
        details.toString().toLowerCase().contains(kw);
  }

  /// CSV row representation
  String toCsvRow() {
    String escape(String s) => '"${s.replaceAll('"', '""')}"';
    final ts = createdAt?.toDate().toLocal().toIso8601String() ?? '';
    return [
      escape(ts),
      escape(action),
      escape(adminEmail),
      escape(targetUid),
      escape(jsonEncode(details)),
    ].join(',');
  }
}

// ─────────────────────────────────────────────
// FILTER MODEL
// ─────────────────────────────────────────────
class AdminLogsFilter {
  final String?   actionType;   // null = all
  final String?   adminUid;     // null = all
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String    keyword;

  const AdminLogsFilter({
    this.actionType,
    this.adminUid,
    this.dateFrom,
    this.dateTo,
    this.keyword = '',
  });

  AdminLogsFilter copyWith({
    Object? actionType = _sentinel,
    Object? adminUid   = _sentinel,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? keyword,
    bool clearDateFrom = false,
    bool clearDateTo   = false,
    bool clearAction   = false,
    bool clearAdmin    = false,
  }) {
    return AdminLogsFilter(
      actionType: clearAction ? null : (actionType == _sentinel ? this.actionType : actionType as String?),
      adminUid:   clearAdmin  ? null : (adminUid   == _sentinel ? this.adminUid   : adminUid   as String?),
      dateFrom:   clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo:     clearDateTo   ? null : (dateTo   ?? this.dateTo),
      keyword:    keyword ?? this.keyword,
    );
  }

  static const _sentinel = Object();

  bool get hasActiveFilters =>
      actionType != null || adminUid != null ||
      dateFrom != null || dateTo != null || keyword.isNotEmpty;
}

// ─────────────────────────────────────────────
// LOG STATS
// ─────────────────────────────────────────────
class AdminLogsStats {
  final int totalToday;
  final Map<String, int> actionCounts; // action → count (all time)
  final String? mostActiveAdmin;

  const AdminLogsStats({
    required this.totalToday,
    required this.actionCounts,
    this.mostActiveAdmin,
  });
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────
class AdminLogsService {
  AdminLogsService._();
  static final AdminLogsService instance = AdminLogsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int _pageSize = 25;

  String get _adminUid   => AdminAuthService.instance.currentUser?.uid   ?? 'unknown';
  String get _adminEmail => AdminAuthService.instance.currentUser?.email ?? 'Unknown Admin';

  // ──────────────────────────────────────────────────────
  // BASE STREAM (first page, realtime)
  // Returns a stream of first _pageSize logs matching the Firestore query.
  // Keyword / date filtering beyond Firestore index is done client-side.
  // ──────────────────────────────────────────────────────
  Stream<List<AdminLogEntry>> logsStream({
    AdminLogsFilter? filter,
    DocumentSnapshot? startAfter,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('admin_logs');

    // Apply Firestore-native filters (indexed)
    if (filter?.actionType != null) {
      q = q.where('action', isEqualTo: filter!.actionType);
    }
    if (filter?.adminUid != null) {
      q = q.where('adminUid', isEqualTo: filter!.adminUid);
    }

    q = q.orderBy('createdAt', descending: true);

    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }

    q = q.limit(_pageSize);

    return q.snapshots().map((snap) {
      var entries = snap.docs.map((d) => AdminLogEntry.fromDoc(d)).toList();

      // Client-side filters (not indexable without composite index per combo)
      if (filter != null) {
        if (filter.dateFrom != null) {
          entries = entries.where((e) {
            final d = e.createdAt?.toDate();
            return d != null && !d.isBefore(filter.dateFrom!);
          }).toList();
        }
        if (filter.dateTo != null) {
          final endOfDay = filter.dateTo!.add(const Duration(days: 1));
          entries = entries.where((e) {
            final d = e.createdAt?.toDate();
            return d != null && d.isBefore(endOfDay);
          }).toList();
        }
        if (filter.keyword.isNotEmpty) {
          entries = entries.where((e) => e.matchesKeyword(filter.keyword)).toList();
        }
      }

      return entries;
    });
  }

  // ──────────────────────────────────────────────────────
  // LOAD MORE (pagination — returns next page snapshot cursor)
  // ──────────────────────────────────────────────────────
  Future<({List<AdminLogEntry> entries, DocumentSnapshot? lastDoc})> loadMoreLogs({
    required AdminLogsFilter filter,
    required DocumentSnapshot lastDoc,
  }) async {
    Query<Map<String, dynamic>> q = _db.collection('admin_logs');

    if (filter.actionType != null) {
      q = q.where('action', isEqualTo: filter.actionType);
    }
    if (filter.adminUid != null) {
      q = q.where('adminUid', isEqualTo: filter.adminUid);
    }

    q = q.orderBy('createdAt', descending: true)
         .startAfterDocument(lastDoc)
         .limit(_pageSize);

    final snap = await q.get();
    var entries = snap.docs.map((d) => AdminLogEntry.fromDoc(d)).toList();

    if (filter.dateFrom != null) {
      entries = entries.where((e) {
        final d = e.createdAt?.toDate();
        return d != null && !d.isBefore(filter.dateFrom!);
      }).toList();
    }
    if (filter.dateTo != null) {
      final endOfDay = filter.dateTo!.add(const Duration(days: 1));
      entries = entries.where((e) {
        final d = e.createdAt?.toDate();
        return d != null && d.isBefore(endOfDay);
      }).toList();
    }
    if (filter.keyword.isNotEmpty) {
      entries = entries.where((e) => e.matchesKeyword(filter.keyword)).toList();
    }

    return (
      entries: entries,
      lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
    );
  }

  // ──────────────────────────────────────────────────────
  // STATS STREAM (today count + action breakdown)
  // ──────────────────────────────────────────────────────
  Stream<AdminLogsStats> statsStream() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return _db
        .collection('admin_logs')
        .orderBy('createdAt', descending: true)
        .limit(500) // reasonable cap for stats
        .snapshots()
        .map((snap) {
      int todayCount = 0;
      final actionCounts = <String, int>{};
      final adminCounts  = <String, int>{};

      for (final doc in snap.docs) {
        final entry = AdminLogEntry.fromDoc(doc);
        actionCounts[entry.action] = (actionCounts[entry.action] ?? 0) + 1;
        adminCounts[entry.adminEmail] = (adminCounts[entry.adminEmail] ?? 0) + 1;

        final dt = entry.createdAt?.toDate().toLocal();
        if (dt != null && !dt.isBefore(startOfDay)) todayCount++;
      }

      String? topAdmin;
      if (adminCounts.isNotEmpty) {
        topAdmin = adminCounts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
      }

      return AdminLogsStats(
        totalToday:     todayCount,
        actionCounts:   actionCounts,
        mostActiveAdmin: topAdmin,
      );
    });
  }

  // ──────────────────────────────────────────────────────
  // DISTINCT ADMIN EMAILS (for filter dropdown)
  // ──────────────────────────────────────────────────────
  Future<List<({String uid, String email})>> getDistinctAdmins() async {
    final snap = await _db
        .collection('admin_logs')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();

    final seen = <String, String>{}; // uid → email
    for (final doc in snap.docs) {
      final d = doc.data();
      final uid   = (d['adminUid']   as String?) ?? '';
      final email = (d['adminEmail'] as String?) ?? '';
      if (uid.isNotEmpty) seen[uid] = email;
    }

    return seen.entries
        .map((e) => (uid: e.key, email: e.value))
        .toList();
  }

  // ──────────────────────────────────────────────────────
  // EXPORT CSV
  // ──────────────────────────────────────────────────────
  Future<String> exportCsv({AdminLogsFilter? filter}) async {
    Query<Map<String, dynamic>> q = _db.collection('admin_logs');

    if (filter?.actionType != null) {
      q = q.where('action', isEqualTo: filter!.actionType);
    }
    if (filter?.adminUid != null) {
      q = q.where('adminUid', isEqualTo: filter!.adminUid);
    }
    if (filter?.dateFrom != null) {
      q = q.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(filter!.dateFrom!));
    }
    if (filter?.dateTo != null) {
      q = q.where('createdAt',
          isLessThan: Timestamp.fromDate(
              filter!.dateTo!.add(const Duration(days: 1))));
    }

    q = q.orderBy('createdAt', descending: true).limit(1000);

    final snap = await q.get();
    var entries = snap.docs.map((d) => AdminLogEntry.fromDoc(d)).toList();

    if (filter != null && filter.keyword.isNotEmpty) {
      entries = entries.where((e) => e.matchesKeyword(filter.keyword)).toList();
    }

    final header = 'Timestamp,Action,Admin Email,Target UID,Details';
    final rows   = entries.map((e) => e.toCsvRow()).join('\n');
    return '$header\n$rows';
  }

  // ──────────────────────────────────────────────────────
  // PURGE OLD LOGS (> 90 days)
  // ──────────────────────────────────────────────────────
  Future<int> purgeOldLogs() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final snap   = await _db
        .collection('admin_logs')
        .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
        .limit(500)
        .get();

    if (snap.docs.isEmpty) return 0;

    // Delete in batches of 500
    int deleted = 0;
    var batch   = _db.batch();
    int count   = 0;

    for (final doc in snap.docs) {
      batch.delete(doc.reference);
      count++;
      deleted++;
      if (count == 499) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();

    // Log the purge itself
    await _db.collection('admin_logs').add({
      'action':     'logs_purged',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  'system',
      'details': {
        'deletedCount': deleted,
        'olderThanDays': 90,
        'cutoffDate': cutoff.toIso8601String(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    return deleted;
  }

  // ──────────────────────────────────────────────────────
  // WRITE LOG ENTRY (utility — used by other services)
  // ──────────────────────────────────────────────────────
  static Future<void> writeLog({
    required WriteBatch batch,
    required FirebaseFirestore db,
    required String adminUid,
    required String adminEmail,
    required String action,
    required String targetUid,
    required Map<String, dynamic> details,
  }) async {
    final ref = db.collection('admin_logs').doc();
    batch.set(ref, {
      'action':     action,
      'adminUid':   adminUid,
      'adminEmail': adminEmail,
      'targetUid':  targetUid,
      'details':    details,
      'createdAt':  FieldValue.serverTimestamp(),
    });
  }
}

// ─────────────────────────────────────────────
// LOG ACTION TYPES (constants for UI)
// ─────────────────────────────────────────────
abstract class LogActions {
  static const all = [
    'deposit_approved',
    'deposit_rejected',
    'withdrawal_approved',
    'withdrawal_rejected',
    'balance_adjusted',
    'admin_promoted',
    'admin_demoted',
    'account_frozen',
    'account_unfrozen',
    'tournament_created',
    'tournament_updated',
    'tournament_status_changed',
    'tournament_featured',
    'tournament_unfeatured',
    'tournament_deleted',
    'tournament_cancelled',
    'prize_distributed',
    'room_credentials_updated',
    'participant_disqualified',
    'participant_removed',
    'settings_updated',
    'maintenance_enabled',
    'maintenance_disabled',
    'wallets_frozen',
    'wallets_unfrozen',
    'logs_purged',
    'suspicious_activity_detected',
  ];

  static const Map<String, String> labels = {
    'deposit_approved':           'Deposit Approved',
    'deposit_rejected':           'Deposit Rejected',
    'withdrawal_approved':        'Withdrawal Approved',
    'withdrawal_rejected':        'Withdrawal Rejected',
    'balance_adjusted':           'Balance Adjusted',
    'admin_promoted':             'Admin Promoted',
    'admin_demoted':              'Admin Demoted',
    'account_frozen':             'Account Frozen',
    'account_unfrozen':           'Account Unfrozen',
    'tournament_created':         'Tournament Created',
    'tournament_updated':         'Tournament Updated',
    'tournament_status_changed':  'Status Changed',
    'tournament_featured':        'Tournament Featured',
    'tournament_unfeatured':      'Tournament Unfeatured',
    'tournament_deleted':         'Tournament Deleted',
    'tournament_cancelled':       'Tournament Cancelled',
    'prize_distributed':          'Prizes Distributed',
    'room_credentials_updated':   'Room Credentials',
    'participant_disqualified':   'Player Disqualified',
    'participant_removed':        'Player Removed',
    'settings_updated':           'Settings Updated',
    'maintenance_enabled':        'Maintenance ON',
    'maintenance_disabled':       'Maintenance OFF',
    'wallets_frozen':             'Wallets Frozen',
    'wallets_unfrozen':           'Wallets Unfrozen',
    'logs_purged':                'Logs Purged',
    'suspicious_activity_detected': 'Suspicious Activity',
  };
}