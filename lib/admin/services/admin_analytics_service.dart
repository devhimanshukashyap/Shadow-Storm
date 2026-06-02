// lib/admin/services/admin_analytics_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Analytics Service
// F2: Platform metrics, revenue analytics, user growth, tournament health
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────
// REVENUE PERIOD
// ─────────────────────────────────────────────
enum RevenuePeriod { today, sevenDays, thirtyDays, allTime }

extension RevenuePeriodExt on RevenuePeriod {
  String get label {
    switch (this) {
      case RevenuePeriod.today:      return 'Today';
      case RevenuePeriod.sevenDays:  return '7 Days';
      case RevenuePeriod.thirtyDays: return '30 Days';
      case RevenuePeriod.allTime:    return 'All Time';
    }
  }

  DateTime? get since {
    final now = DateTime.now();
    switch (this) {
      case RevenuePeriod.today:
        return DateTime(now.year, now.month, now.day);
      case RevenuePeriod.sevenDays:
        return now.subtract(const Duration(days: 7));
      case RevenuePeriod.thirtyDays:
        return now.subtract(const Duration(days: 30));
      case RevenuePeriod.allTime:
        return null;
    }
  }
}

// ─────────────────────────────────────────────
// PLATFORM METRICS MODEL
// ─────────────────────────────────────────────
class PlatformMetrics {
  // Users
  final int totalUsers;
  final int activeUsersToday;
  final int newUsersToday;
  final int newUsersThisWeek;
  final int newUsersThisMonth;
  final int frozenAccounts;
  final int adminAccounts;

  // Tournaments
  final int totalTournaments;
  final int upcomingTournaments;
  final int liveTournaments;
  final int completedTournaments;
  final int cancelledTournaments;

  // Transactions
  final int pendingDeposits;
  final int pendingWithdrawals;
  final double totalDepositVolume;
  final double totalWithdrawalVolume;
  final double totalPrizeDistributed;
  final double totalEntryFeeCollected;
  final double totalWalletBalance;

  // Tournament health
  final int missingCredentials;
  final int missingRevealTime;
  final int shouldBeLive;
  final int shouldBeCompleted;
  final int fullTournaments;
  final int underfilled;
  final int awaitingPrizes;

  const PlatformMetrics({
    required this.totalUsers,
    required this.activeUsersToday,
    required this.newUsersToday,
    required this.newUsersThisWeek,
    required this.newUsersThisMonth,
    required this.frozenAccounts,
    required this.adminAccounts,
    required this.totalTournaments,
    required this.upcomingTournaments,
    required this.liveTournaments,
    required this.completedTournaments,
    required this.cancelledTournaments,
    required this.pendingDeposits,
    required this.pendingWithdrawals,
    required this.totalDepositVolume,
    required this.totalWithdrawalVolume,
    required this.totalPrizeDistributed,
    required this.totalEntryFeeCollected,
    required this.totalWalletBalance,
    required this.missingCredentials,
    required this.missingRevealTime,
    required this.shouldBeLive,
    required this.shouldBeCompleted,
    required this.fullTournaments,
    required this.underfilled,
    required this.awaitingPrizes,
  });

  double get netPlatformBalance =>
      totalDepositVolume - totalWithdrawalVolume - totalPrizeDistributed;

  double get platformProfit =>
      totalEntryFeeCollected - totalPrizeDistributed;

  int get totalTournamentAlerts =>
      missingCredentials + shouldBeLive + shouldBeCompleted + awaitingPrizes;

  static PlatformMetrics empty() => const PlatformMetrics(
    totalUsers: 0, activeUsersToday: 0,
    newUsersToday: 0, newUsersThisWeek: 0, newUsersThisMonth: 0,
    frozenAccounts: 0, adminAccounts: 0,
    totalTournaments: 0, upcomingTournaments: 0, liveTournaments: 0,
    completedTournaments: 0, cancelledTournaments: 0,
    pendingDeposits: 0, pendingWithdrawals: 0,
    totalDepositVolume: 0, totalWithdrawalVolume: 0,
    totalPrizeDistributed: 0, totalEntryFeeCollected: 0,
    totalWalletBalance: 0,
    missingCredentials: 0, missingRevealTime: 0,
    shouldBeLive: 0, shouldBeCompleted: 0,
    fullTournaments: 0, underfilled: 0, awaitingPrizes: 0,
  );
}

// ─────────────────────────────────────────────
// REVENUE SNAPSHOT MODEL
// ─────────────────────────────────────────────
class RevenueSnapshot {
  final double depositVolume;
  final double withdrawalVolume;
  final double entryFeeCollected;
  final double prizeDistributed;
  final double netBalance;
  final int    approvedDeposits;
  final int    approvedWithdrawals;

  const RevenueSnapshot({
    required this.depositVolume,
    required this.withdrawalVolume,
    required this.entryFeeCollected,
    required this.prizeDistributed,
    required this.netBalance,
    required this.approvedDeposits,
    required this.approvedWithdrawals,
  });

  double get platformProfit => entryFeeCollected - prizeDistributed;
}

// ─────────────────────────────────────────────
// TOURNAMENT HEALTH ITEM
// ─────────────────────────────────────────────
class TournamentHealthItem {
  final String  id;
  final String  title;
  final String  status;
  final int     joinedPlayers;
  final int     maxPlayers;
  final bool    hasRoomId;
  final bool    hasRoomPassword;
  final bool    hasRevealTime;
  final bool    prizesDistributed;
  final Timestamp? startTime;

  const TournamentHealthItem({
    required this.id,
    required this.title,
    required this.status,
    required this.joinedPlayers,
    required this.maxPlayers,
    required this.hasRoomId,
    required this.hasRoomPassword,
    required this.hasRevealTime,
    required this.prizesDistributed,
    this.startTime,
  });

  factory TournamentHealthItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final roomId = (d['roomId'] as String?) ?? '';
    final roomPw = (d['roomPassword'] as String?) ?? '';
    return TournamentHealthItem(
      id:               doc.id,
      title:            (d['title'] as String?) ?? 'Unnamed',
      status:           (d['status'] as String?) ?? 'upcoming',
      joinedPlayers:    (d['joinedPlayers'] as num?)?.toInt() ?? 0,
      maxPlayers:       (d['maxPlayers'] as num?)?.toInt() ?? 0,
      hasRoomId:        roomId.isNotEmpty,
      hasRoomPassword:  roomPw.isNotEmpty,
      hasRevealTime:    d['roomRevealTime'] != null,
      prizesDistributed:(d['prizesDistributed'] as bool?) ?? false,
      startTime:         d['startTime'] as Timestamp?,
    );
  }

  bool get isFull          => maxPlayers > 0 && joinedPlayers >= maxPlayers;
  bool get isUnderfilled   => maxPlayers > 0 && joinedPlayers < (maxPlayers * 0.5);
  bool get shouldBeLive    => status == 'upcoming' && startTime != null &&
      startTime!.toDate().isBefore(DateTime.now());
  bool get shouldBeCompleted => status == 'live' && startTime != null &&
      startTime!.toDate().isBefore(DateTime.now().subtract(const Duration(hours: 3)));
  bool get needsCredentials  => (status == 'upcoming' || status == 'live') && !hasRoomId;
  bool get awaitsPrizes      => status == 'live' && !prizesDistributed;
}

// ─────────────────────────────────────────────
// USER GROWTH MODEL
// ─────────────────────────────────────────────
class UserGrowthData {
  final int today;
  final int thisWeek;
  final int thisMonth;
  final List<DailyCount> last30Days;

  const UserGrowthData({
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.last30Days,
  });
}

class DailyCount {
  final DateTime date;
  final int count;
  const DailyCount({required this.date, required this.count});
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────
class AdminAnalyticsService {
  AdminAnalyticsService._();
  static final AdminAnalyticsService instance = AdminAnalyticsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────
  // FULL PLATFORM METRICS (one-time snapshot)
  // ──────────────────────────────────────────────────────
  Future<PlatformMetrics> getPlatformMetrics() async {
    final now     = DateTime.now();
    final today   = DateTime(now.year, now.month, now.day);
    final week    = now.subtract(const Duration(days: 7));
    final month   = now.subtract(const Duration(days: 30));

    // Parallel fetch
    final results = await Future.wait([
      _db.collection('users').get(),
      _db.collection('tournaments').get(),
      _db.collectionGroup('deposit_requests').get(),
      _db.collectionGroup('withdraw_requests').get(),
    ]);

    final userDocs        = results[0] as QuerySnapshot;
    final tournamentDocs  = results[1] as QuerySnapshot;
    final depositDocs     = results[2] as QuerySnapshot;
    final withdrawalDocs  = results[3] as QuerySnapshot;

    // ── Users ──────────────────────────────────
    int totalUsers = userDocs.docs.length;
    int newToday = 0, newWeek = 0, newMonth = 0;
    int frozen = 0, admins = 0;
    double totalWallet = 0;

    for (final doc in userDocs.docs) {
      final d = doc.data() as Map<String, dynamic>;
      if ((d['isFrozen'] as bool?) ?? false) frozen++;
      if ((d['isAdmin']  as bool?) ?? false) admins++;
      totalWallet += (d['walletBalance'] as num?)?.toDouble() ?? 0;

      final created = d['createdAt'] as Timestamp?;
      if (created != null) {
        final dt = created.toDate().toLocal();
        if (!dt.isBefore(today))  newToday++;
        if (!dt.isBefore(week))   newWeek++;
        if (!dt.isBefore(month))  newMonth++;
      }
    }

    // ── Tournaments ────────────────────────────
    int upcoming = 0, live = 0, completed = 0, cancelled = 0;
    double totalEntryFee = 0, totalPrizes = 0;
    int missingCreds = 0, missingReveal = 0;
    int shouldLive = 0, shouldComplete = 0;
    int fullT = 0, underfilled = 0, awaitPrizes = 0;

    for (final doc in tournamentDocs.docs) {
      final item = TournamentHealthItem.fromDoc(doc);
      final d    = doc.data() as Map<String, dynamic>;

      switch (item.status) {
        case 'upcoming':  upcoming++;  break;
        case 'live':      live++;      break;
        case 'completed': completed++; break;
        case 'cancelled': cancelled++; break;
      }

      if (item.status != 'cancelled') {
        final fee     = (d['entryFee']     as num?)?.toDouble() ?? 0;
        final joined  = item.joinedPlayers;
        totalEntryFee += fee * joined;

        if ((d['prizesDistributed'] as bool?) == true) {
          totalPrizes += (d['prizePool'] as num?)?.toDouble() ?? 0;
        }
      }

      if (item.needsCredentials) missingCreds++;
      if ((item.status == 'upcoming' || item.status == 'live') && !item.hasRevealTime) missingReveal++;
      if (item.shouldBeLive)      shouldLive++;
      if (item.shouldBeCompleted) shouldComplete++;
      if (item.isFull)            fullT++;
      if (item.isUnderfilled && item.status == 'upcoming') underfilled++;
      if (item.awaitsPrizes)      awaitPrizes++;
    }

    // ── Transactions ───────────────────────────
    int pendingDeps = 0, pendingWds = 0;
    double depVolume = 0, wdVolume = 0;

    for (final doc in depositDocs.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final status = (d['status'] as String?) ?? '';
      if (status == 'pending')  pendingDeps++;
      if (status == 'approved') depVolume += (d['amount'] as num?)?.toDouble() ?? 0;
    }

    for (final doc in withdrawalDocs.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final status = (d['status'] as String?) ?? '';
      if (status == 'pending')  pendingWds++;
      if (status == 'approved') wdVolume += (d['amount'] as num?)?.toDouble() ?? 0;
    }

    return PlatformMetrics(
      totalUsers:            totalUsers,
      activeUsersToday:      newToday, // proxy — users who signed up today
      newUsersToday:         newToday,
      newUsersThisWeek:      newWeek,
      newUsersThisMonth:     newMonth,
      frozenAccounts:        frozen,
      adminAccounts:         admins,
      totalTournaments:      tournamentDocs.docs.length,
      upcomingTournaments:   upcoming,
      liveTournaments:       live,
      completedTournaments:  completed,
      cancelledTournaments:  cancelled,
      pendingDeposits:       pendingDeps,
      pendingWithdrawals:    pendingWds,
      totalDepositVolume:    depVolume,
      totalWithdrawalVolume: wdVolume,
      totalPrizeDistributed: totalPrizes,
      totalEntryFeeCollected: totalEntryFee,
      totalWalletBalance:    totalWallet,
      missingCredentials:    missingCreds,
      missingRevealTime:     missingReveal,
      shouldBeLive:          shouldLive,
      shouldBeCompleted:     shouldComplete,
      fullTournaments:       fullT,
      underfilled:           underfilled,
      awaitingPrizes:        awaitPrizes,
    );
  }

  // ──────────────────────────────────────────────────────
  // REVENUE SNAPSHOT FOR A PERIOD
  // ──────────────────────────────────────────────────────
  Future<RevenueSnapshot> getRevenueSnapshot(RevenuePeriod period) async {
    final since = period.since;

    Query<Map<String, dynamic>> depQ = _db.collectionGroup('deposit_requests');
    Query<Map<String, dynamic>> wdQ  = _db.collectionGroup('withdraw_requests');

    if (since != null) {
      final ts = Timestamp.fromDate(since);
      depQ = depQ.where('createdAt', isGreaterThanOrEqualTo: ts);
      wdQ  = wdQ.where('createdAt',  isGreaterThanOrEqualTo: ts);
    }

    final results = await Future.wait([depQ.get(), wdQ.get()]);
    final depDocs = results[0].docs;
    final wdDocs  = results[1].docs;

    double depVol = 0; int approvedDeps = 0;
    for (final doc in depDocs) {
      final d = doc.data();
      if ((d['status'] as String?) == 'approved') {
        depVol += (d['amount'] as num?)?.toDouble() ?? 0;
        approvedDeps++;
      }
    }

    double wdVol = 0; int approvedWds = 0;
    for (final doc in wdDocs) {
      final d = doc.data();
      if ((d['status'] as String?) == 'approved') {
        wdVol += (d['amount'] as num?)?.toDouble() ?? 0;
        approvedWds++;
      }
    }

    // Entry fees + prizes for period
    Query<Map<String, dynamic>> tQ = _db.collection('tournaments');
    if (since != null) {
      tQ = tQ.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }
    final tSnap = await tQ.get();
    double entryFees = 0, prizes = 0;
    for (final doc in tSnap.docs) {
      final d = doc.data();
      final fee    = (d['entryFee']      as num?)?.toDouble() ?? 0;
      final joined = (d['joinedPlayers'] as num?)?.toInt() ?? 0;
      entryFees += fee * joined;
      if ((d['prizesDistributed'] as bool?) == true) {
        prizes += (d['prizePool'] as num?)?.toDouble() ?? 0;
      }
    }

    return RevenueSnapshot(
      depositVolume:      depVol,
      withdrawalVolume:   wdVol,
      entryFeeCollected:  entryFees,
      prizeDistributed:   prizes,
      netBalance:         depVol - wdVol - prizes,
      approvedDeposits:   approvedDeps,
      approvedWithdrawals: approvedWds,
    );
  }

  // ──────────────────────────────────────────────────────
  // USER GROWTH DATA
  // ──────────────────────────────────────────────────────
  Future<UserGrowthData> getUserGrowth() async {
    final now   = DateTime.now();
    final since = now.subtract(const Duration(days: 30));

    final snap = await _db
        .collection('users')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();

    final today    = DateTime(now.year, now.month, now.day);
    final weekAgo  = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    int dayCount = 0, weekCount = 0, monthCount = 0;
    final Map<String, int> dailyCounts = {};

    for (final doc in snap.docs) {
      final d  = doc.data();
      final ts = d['createdAt'] as Timestamp?;
      if (ts == null) continue;
      final dt = ts.toDate().toLocal();
      if (!dt.isBefore(today))    dayCount++;
      if (!dt.isBefore(weekAgo))  weekCount++;
      if (!dt.isBefore(monthAgo)) monthCount++;

      final key = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
      dailyCounts[key] = (dailyCounts[key] ?? 0) + 1;
    }

    final last30 = List.generate(30, (i) {
      final d   = today.subtract(Duration(days: 29 - i));
      final key = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      return DailyCount(date: d, count: dailyCounts[key] ?? 0);
    });

    return UserGrowthData(
      today:      dayCount,
      thisWeek:   weekCount,
      thisMonth:  monthCount,
      last30Days: last30,
    );
  }

  // ──────────────────────────────────────────────────────
  // TOURNAMENT HEALTH ITEMS (for operations panel)
  // ──────────────────────────────────────────────────────
  Stream<List<TournamentHealthItem>> tournamentHealthStream() {
    return _db
        .collection('tournaments')
        .where('status', whereIn: ['upcoming', 'live'])
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TournamentHealthItem.fromDoc(d))
            .toList());
  }

  // ──────────────────────────────────────────────────────
  // BADGE COUNTS STREAM (for sidebar)
  // ──────────────────────────────────────────────────────
  Stream<Map<String, int>> badgeCountsStream() {
    // Combine pending deposits, withdrawals, and tournament alerts
    return _db.collectionGroup('deposit_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((_depSnap) async {
      final wdSnap = await _db
          .collectionGroup('withdraw_requests')
          .where('status', isEqualTo: 'pending')
          .get();
      final tSnap = await _db
          .collection('tournaments')
          .where('status', whereIn: ['upcoming', 'live'])
          .get();

      int tAlerts = 0;
      for (final doc in tSnap.docs) {
        final item = TournamentHealthItem.fromDoc(doc);
        if (item.needsCredentials)  tAlerts++;
        if (item.shouldBeLive)      tAlerts++;
        if (item.shouldBeCompleted) tAlerts++;
        if (item.awaitsPrizes)      tAlerts++;
      }

      return {
        'deposits':    _depSnap.docs.length,
        'withdrawals': wdSnap.docs.length,
        'tournaments': tAlerts,
      };
    });
  }
}