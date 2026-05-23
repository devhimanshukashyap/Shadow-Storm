// lib/models/tournament_model.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Tournament Model (v3)
//
// Changes from v2:
//   • requiredSlots / maxSlots fields (team-size control)
//   • New tournamentType values: '2v2', '1v1_arena', 'lose_to_win',
//     'sniper', 'custom_league' added to _typeLabel / status helpers
//   • roomRevealTime, cancelledStatus, minimumLevel unchanged
//   • copyWith extended with requiredSlots / maxSlots
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

// ── Status Enum ──────────────────────────────
enum TournamentStatus { upcoming, live, completed, cancelled }

TournamentStatus statusFromString(String? s) {
  switch (s) {
    case 'live':      return TournamentStatus.live;
    case 'completed': return TournamentStatus.completed;
    case 'cancelled': return TournamentStatus.cancelled;
    default:          return TournamentStatus.upcoming;
  }
}

String statusToString(TournamentStatus s) {
  switch (s) {
    case TournamentStatus.live:      return 'live';
    case TournamentStatus.completed: return 'completed';
    case TournamentStatus.cancelled: return 'cancelled';
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
  final String tournamentType;
  // Valid values:
  //   'battle_royale' | 'clash_squad' | '2v2' | 'lone_wolf' |
  //   'lose_to_win'   | 'custom_league' | '1v1_arena' | 'sniper'
  final String mode; // 'Squad' | 'Duo' | 'Solo' | '2v2' | '1v1'
  final String map;

  // Entry & prize
  final double entryFee;
  final double prizePool;

  // Slots
  final int maxPlayers;
  final int joinedPlayers;

  // Team slot config (new v3)
  final int requiredSlots; // min players per team to register (1 = solo)
  final int maxSlots;      // max players per team (flexible for squad: 2–4)

  // Room credentials
  final String?   roomId;
  final String?   roomPassword;
  final DateTime? roomRevealTime;

  // Rules & rewards
  final String?              rules;
  final String               rewardType;
  final double               killReward;
  final double               survivalReward;
  final List<PositionReward> positions;
  final String?              rewardDescription;

  // Scheduling
  final TournamentStatus status;
  final DateTime?        startTime;
  final bool             featured;

  // Access control
  final int minimumLevel;

  // Meta
  final bool      prizesDistributed;
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
    this.requiredSlots = 1,
    this.maxSlots      = 1,
    this.roomId,
    this.roomPassword,
    this.roomRevealTime,
    this.rules,
    required this.rewardType,
    required this.killReward,
    required this.survivalReward,
    required this.positions,
    this.rewardDescription,
    required this.status,
    this.startTime,
    required this.featured,
    this.minimumLevel      = 0,
    this.prizesDistributed = false,
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
      requiredSlots:     (d['requiredSlots']    as num?)?.toInt()    ?? 1,
      maxSlots:          (d['maxSlots']         as num?)?.toInt()    ?? 1,
      roomId:            d['roomId']            as String?,
      roomPassword:      d['roomPassword']      as String?,
      roomRevealTime:    (d['roomRevealTime']   as Timestamp?)?.toDate(),
      rules:             d['rules']             as String?,
      rewardType:        d['rewardType']        as String? ?? 'position',
      killReward:        (d['killReward']       as num?)?.toDouble() ?? 0.0,
      survivalReward:    (d['survivalReward']   as num?)?.toDouble() ?? 0.0,
      positions:         positionList,
      rewardDescription: d['rewardDescription'] as String?,
      status:            statusFromString(d['status'] as String?),
      startTime:         (d['startTime'] as Timestamp?)?.toDate(),
      featured:          d['featured'] as bool? ?? false,
      minimumLevel:      (d['minimumLevel']     as num?)?.toInt()    ?? 0,
      prizesDistributed: d['prizesDistributed'] as bool? ?? false,
      createdAt:         (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  // ── copyWith ─────────────────────────────────
  TournamentModel copyWith({
    int?              joinedPlayers,
    String?           roomId,
    String?           roomPassword,
    TournamentStatus? status,
    int?              requiredSlots,
    int?              maxSlots,
  }) {
    return TournamentModel(
      id:                id,
      title:             title,
      subtitle:          subtitle,
      bannerUrl:         bannerUrl,
      tournamentType:    tournamentType,
      mode:              mode,
      map:               map,
      entryFee:          entryFee,
      prizePool:         prizePool,
      maxPlayers:        maxPlayers,
      joinedPlayers:     joinedPlayers    ?? this.joinedPlayers,
      requiredSlots:     requiredSlots    ?? this.requiredSlots,
      maxSlots:          maxSlots         ?? this.maxSlots,
      roomId:            roomId           ?? this.roomId,
      roomPassword:      roomPassword     ?? this.roomPassword,
      roomRevealTime:    roomRevealTime,
      rules:             rules,
      rewardType:        rewardType,
      killReward:        killReward,
      survivalReward:    survivalReward,
      positions:         positions,
      rewardDescription: rewardDescription,
      status:            status           ?? this.status,
      startTime:         startTime,
      featured:          featured,
      minimumLevel:      minimumLevel,
      prizesDistributed: prizesDistributed,
      createdAt:         createdAt,
    );
  }

  // ── Computed helpers ─────────────────────────

  bool get isTeamTournament => requiredSlots > 1;

  String get entryFeeDisplay =>
      entryFee <= 0 ? 'FREE' : '₹${_formatAmount(entryFee)}';

  String get prizePoolDisplay => '₹${_formatAmount(prizePool)}';

  int get slotsLeft => maxPlayers - joinedPlayers;

  bool get isAlmostFull =>
      slotsLeft > 0 && slotsLeft < (maxPlayers * 0.2).ceil();

  bool get isFull => slotsLeft <= 0;

  double get fillPercent =>
      maxPlayers > 0 ? (joinedPlayers / maxPlayers).clamp(0.0, 1.0) : 0.0;

  bool get isActive =>
      status == TournamentStatus.upcoming || status == TournamentStatus.live;

  bool get isCompleted => status == TournamentStatus.completed;

  bool get isCancelled => status == TournamentStatus.cancelled;

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

  String get typeLabelDisplay => _typeLabel(tournamentType);

  /// Human-readable team size string e.g. "Solo", "Duo", "Squad (4)"
  String get teamSizeDisplay {
    if (requiredSlots == 1) return 'Solo';
    if (requiredSlots == 2) return 'Duo';
    if (requiredSlots == 4) return 'Squad';
    return '$requiredSlots Players';
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'battle_royale':  return 'Battle Royale';
      case 'clash_squad':    return 'Clash Squad';
      case '2v2':            return '2v2 Arena';
      case 'lone_wolf':      return 'Lone Wolf';
      case 'lose_to_win':    return 'Lose To Win';
      case 'custom_league':  return 'Custom League';
      case '1v1_arena':      return '1v1 Arena';
      case 'sniper':         return 'Sniper Challenge';
      default:               return type;
    }
  }

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