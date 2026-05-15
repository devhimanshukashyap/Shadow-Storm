// lib/models/tournament_model.dart
// ─────────────────────────────────────────────
// TOURNAMENT MODEL
// Mirrors Firestore document structure exactly.
// All fields are nullable so partial documents
// don't crash the app.
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

// ── Status Enum ──────────────────────────────
enum TournamentStatus { upcoming, live, completed }

TournamentStatus statusFromString(String? s) {
  switch (s) {
    case 'live':      return TournamentStatus.live;
    case 'completed': return TournamentStatus.completed;
    default:          return TournamentStatus.upcoming;
  }
}

String statusToString(TournamentStatus s) {
  switch (s) {
    case TournamentStatus.live:      return 'live';
    case TournamentStatus.completed: return 'completed';
    case TournamentStatus.upcoming:  return 'upcoming';
  }
}

// ── Position Reward Model ────────────────────
// Stores per-rank prize amounts, e.g. { "1": 5000, "2": 3000 }
class PositionReward {
  final int rank;
  final double amount;

  const PositionReward({required this.rank, required this.amount});

  factory PositionReward.fromMap(MapEntry<String, dynamic> entry) {
    return PositionReward(
      rank:   int.tryParse(entry.key) ?? 0,
      amount: (entry.value as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {rank.toString(): amount};
}

// ── Main Tournament Model ────────────────────
class TournamentModel {
  final String id;

  // Basic info
  final String title;
  final String subtitle;
  final String? bannerUrl;

  // Tournament config (admin-configurable)
  final String tournamentType; // 'battle_royale' | 'clash_squad' | 'lone_wolf'
  final String mode;           // e.g. 'Squad', 'Duo', 'Solo'
  final String map;            // e.g. 'Bermuda', 'Kalahari'

  // Entry & prize
  final double entryFee;
  final double prizePool;

  // Slots
  final int maxPlayers;
  final int joinedPlayers;

  // Room info (revealed before match starts)
  final String? roomId;
  final String? roomPassword;

  // Rules & rewards
  final String? rules;
  final String rewardType; // 'survival' | 'kill' | 'position' | 'mixed'
  final double killReward;
  final double survivalReward;
  final List<PositionReward> positions; // rank-based prize distribution

  // Scheduling
  final TournamentStatus status;
  final DateTime? startTime;
  final bool featured;

  // Meta
  final DateTime? createdAt;

  const TournamentModel({
    required this.id,
    required this.title,
    required this.subtitle,
    this.bannerUrl,
    required this.tournamentType,
    required this.mode,
    required this.map,
    required this.entryFee,
    required this.prizePool,
    required this.maxPlayers,
    required this.joinedPlayers,
    this.roomId,
    this.roomPassword,
    this.rules,
    required this.rewardType,
    required this.killReward,
    required this.survivalReward,
    required this.positions,
    required this.status,
    this.startTime,
    required this.featured,
    this.createdAt,
  });

  // ── Factory: build from Firestore snapshot ──
  factory TournamentModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};

    // Parse positions map: { "1": 5000, "2": 3000, ... }
    final rawPositions = d['positions'] as Map<String, dynamic>? ?? {};
    final positionList = rawPositions.entries
        .map((e) => PositionReward.fromMap(e))
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));

    return TournamentModel(
      id:              doc.id,
      title:           d['title']          as String? ?? 'Unnamed Tournament',
      subtitle:        d['subtitle']       as String? ?? '',
      bannerUrl:       d['bannerUrl']      as String?,
      tournamentType:  d['tournamentType'] as String? ?? 'battle_royale',
      mode:            d['mode']           as String? ?? 'Squad',
      map:             d['map']            as String? ?? 'Bermuda',
      entryFee:        (d['entryFee']      as num?)?.toDouble() ?? 0.0,
      prizePool:       (d['prizePool']     as num?)?.toDouble() ?? 0.0,
      maxPlayers:      (d['maxPlayers']    as num?)?.toInt()    ?? 0,
      joinedPlayers:   (d['joinedPlayers'] as num?)?.toInt()    ?? 0,
      roomId:          d['roomId']         as String?,
      roomPassword:    d['roomPassword']   as String?,
      rules:           d['rules']          as String?,
      rewardType:      d['rewardType']     as String? ?? 'position',
      killReward:      (d['killReward']    as num?)?.toDouble() ?? 0.0,
      survivalReward:  (d['survivalReward'] as num?)?.toDouble() ?? 0.0,
      positions:       positionList,
      status:          statusFromString(d['status'] as String?),
      startTime:       (d['startTime'] as Timestamp?)?.toDate(),
      featured:        d['featured'] as bool? ?? false,
      createdAt:       (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  // ── Computed helpers ─────────────────────────

  /// Formatted entry fee for display, e.g. "₹99" or "FREE"
  String get entryFeeDisplay =>
      entryFee <= 0 ? 'FREE' : '₹${_formatAmount(entryFee)}';

  /// Formatted prize pool, e.g. "₹2,50,000"
  String get prizePoolDisplay => '₹${_formatAmount(prizePool)}';

  /// Slots remaining
  int get slotsLeft => maxPlayers - joinedPlayers;

  /// Is tournament almost full (< 20% slots remain)
  bool get isAlmostFull => slotsLeft > 0 && slotsLeft < (maxPlayers * 0.2).ceil();

  /// Fill percentage for progress bar (0.0 – 1.0)
  double get fillPercent =>
      maxPlayers > 0 ? (joinedPlayers / maxPlayers).clamp(0.0, 1.0) : 0.0;

  /// Human-readable start time or status label
  String get startTimeDisplay {
    if (status == TournamentStatus.live) return 'LIVE NOW';
    if (startTime == null) return 'TBD';

    final now  = DateTime.now();
    final diff = startTime!.difference(now);

    if (diff.inDays == 0) {
      final h = startTime!.hour;
      final m = startTime!.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final h12    = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return 'Today • $h12:$m $period';
    } else if (diff.inDays == 1) {
      return 'Tomorrow • ${_timeStr(startTime!)}';
    } else {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[startTime!.weekday - 1]} • ${_timeStr(startTime!)}';
    }
  }

  /// Display mode string, e.g. "Squad • Battle Royale"
  String get modeDisplay {
    final typeLabel = {
      'battle_royale': 'Battle Royale',
      'clash_squad':   'Clash Squad',
      'lone_wolf':     '1v1',
    }[tournamentType] ?? tournamentType;
    return '$mode • $typeLabel';
  }

  // ── Private helpers ──────────────────────────
  String _timeStr(DateTime dt) {
    final h      = dt.hour;
    final m      = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m $period';
  }

  /// Indian number formatting: 250000 → "2,50,000"
  String _formatAmount(double amount) {
    if (amount >= 100000) {
      // Lakh formatting
      final lakh     = amount ~/ 100000;
      final thousand = (amount % 100000) ~/ 1000;
      final rest     = (amount % 1000).toInt();
      if (rest == 0 && thousand == 0) return '$lakh,00,000';
      if (rest == 0) return '$lakh,${thousand.toString().padLeft(2, '0')},000';
      return '$lakh,${thousand.toString().padLeft(2, '0')},${rest.toString().padLeft(3, '0')}';
    } else if (amount >= 1000) {
      final t = amount ~/ 1000;
      final r = (amount % 1000).toInt();
      return r == 0 ? '$t,000' : '$t,${r.toString().padLeft(3, '0')}';
    }
    return amount.toInt().toString();
  }
}