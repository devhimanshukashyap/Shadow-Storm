// lib/models/tournament_model.dart
// ─────────────────────────────────────────────
// TOURNAMENT MODEL  (v2 — adds rewardDescription)
// Mirrors Firestore document structure exactly.
// All fields nullable so partial docs don't crash.
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
class PositionReward {
  final int    rank;
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
  final String  title;
  final String  subtitle;
  final String? bannerUrl;

  // Tournament config
  // tournamentType: 'battle_royale' | 'clash_squad' | 'lone_wolf' | 'league'
  final String tournamentType;
  final String mode;  // 'Squad' | 'Duo' | 'Solo'
  final String map;   // 'Bermuda' | 'Kalahari' | etc.

  // Entry & prize
  final double entryFee;
  final double prizePool;

  // Slots
  final int maxPlayers;
  final int joinedPlayers;

  // Room info (revealed before match)
  final String? roomId;
  final String? roomPassword;

  // Rules & rewards
  final String? rules;
  final String  rewardType;     // 'survival' | 'kill' | 'position' | 'mixed'
  final double  killReward;
  final double  survivalReward;
  final List<PositionReward> positions;

  // ✅ NEW: Admin-authored reward description / general info text
  // Supports multi-line. Admin fills this in Firestore to explain
  // how rewards work, special rules, prize distribution details, etc.
  final String? rewardDescription;

  // Scheduling
  final TournamentStatus status;
  final DateTime?        startTime;
  final bool             featured;

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
    this.rewardDescription,
    required this.status,
    this.startTime,
    required this.featured,
    this.createdAt,
  });

  // ── Factory: Firestore → model ───────────────
  factory TournamentModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};

    final rawPositions = d['positions'] as Map<String, dynamic>? ?? {};
    final positionList = rawPositions.entries
        .map((e) => PositionReward.fromMap(e))
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));

    return TournamentModel(
      id:                doc.id,
      title:             d['title']             as String? ?? 'Unnamed Tournament',
      subtitle:          d['subtitle']          as String? ?? '',
      bannerUrl:         d['bannerUrl']         as String?,
      tournamentType:    d['tournamentType']    as String? ?? 'battle_royale',
      mode:              d['mode']              as String? ?? 'Squad',
      map:               d['map']               as String? ?? 'Bermuda',
      entryFee:          (d['entryFee']         as num?)?.toDouble() ?? 0.0,
      prizePool:         (d['prizePool']        as num?)?.toDouble() ?? 0.0,
      maxPlayers:        (d['maxPlayers']       as num?)?.toInt()    ?? 0,
      joinedPlayers:     (d['joinedPlayers']    as num?)?.toInt()    ?? 0,
      roomId:            d['roomId']            as String?,
      roomPassword:      d['roomPassword']      as String?,
      rules:             d['rules']             as String?,
      rewardType:        d['rewardType']        as String? ?? 'position',
      killReward:        (d['killReward']       as num?)?.toDouble() ?? 0.0,
      survivalReward:    (d['survivalReward']   as num?)?.toDouble() ?? 0.0,
      positions:         positionList,
      rewardDescription: d['rewardDescription'] as String?,    // ✅ NEW
      status:            statusFromString(d['status'] as String?),
      startTime:         (d['startTime'] as Timestamp?)?.toDate(),
      featured:          d['featured'] as bool? ?? false,
      createdAt:         (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  // ── Computed helpers ─────────────────────────

  String get entryFeeDisplay =>
      entryFee <= 0 ? 'FREE' : '₹${_formatAmount(entryFee)}';

  String get prizePoolDisplay => '₹${_formatAmount(prizePool)}';

  int get slotsLeft => maxPlayers - joinedPlayers;

  bool get isAlmostFull =>
      slotsLeft > 0 && slotsLeft < (maxPlayers * 0.2).ceil();

  double get fillPercent =>
      maxPlayers > 0 ? (joinedPlayers / maxPlayers).clamp(0.0, 1.0) : 0.0;

  String get startTimeDisplay {
    if (status == TournamentStatus.live) return 'LIVE NOW';
    if (startTime == null) return 'TBD';

    final now  = DateTime.now();
    final diff = startTime!.difference(now);

    if (diff.inDays == 0) {
      return 'Today • ${_timeStr(startTime!)}';
    } else if (diff.inDays == 1) {
      return 'Tomorrow • ${_timeStr(startTime!)}';
    } else {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[startTime!.weekday - 1]} • ${_timeStr(startTime!)}';
    }
  }

  String get modeDisplay {
    final typeLabel = _typeLabel(tournamentType);
    return '$mode • $typeLabel';
  }

  /// Human-readable tournament type label
  static String _typeLabel(String type) {
    switch (type) {
      case 'battle_royale': return 'Full Map';
      case 'clash_squad':   return 'Clash Squad';
      case 'lone_wolf':     return 'Lone Wolf';
      case 'league':        return 'League';
      default:              return type;
    }
  }

  String get typeLabelDisplay => _typeLabel(tournamentType);

  // ── Private helpers ──────────────────────────
  String _timeStr(DateTime dt) {
    final h      = dt.hour;
    final m      = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m $period';
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) {
      final lakh     = amount ~/ 100000;
      final thousand = (amount % 100000) ~/ 1000;
      final rest     = (amount % 1000).toInt();
      if (rest == 0 && thousand == 0) return '$lakh,00,000';
      if (rest == 0) {
        return '$lakh,${thousand.toString().padLeft(2, '0')},000';
      }
      return '$lakh,${thousand.toString().padLeft(2, '0')},${rest.toString().padLeft(3, '0')}';
    } else if (amount >= 1000) {
      final t = amount ~/ 1000;
      final r = (amount % 1000).toInt();
      return r == 0 ? '$t,000' : '$t,${r.toString().padLeft(3, '0')}';
    }
    return amount.toInt().toString();
  }
}