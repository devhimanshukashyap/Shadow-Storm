// lib/models/team_slot_model.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Team Slot Model (Phase F2.5 / PRE-F3)
//
// Represents one player slot in a team registration.
// Slot 0 is always the squad leader (auto-filled from user profile).
// Slots 1+ are filled manually by the leader for teammates.
//
// Stored in Firestore at:
//   tournaments/{id}/participants/{uid}/teamSlots[]
// ─────────────────────────────────────────────

class TeamSlot {
  final int     slotIndex;   // 0 = squad leader (always the joining user)
  final String  gameUid;     // in-game UID
  final String  ign;         // in-game name
  final String? userId;      // Firebase UID — only set for slot 0 or registered SS users
  final String? readableId;  // SSP-XXXXXX — only set for registered SS users

  const TeamSlot({
    required this.slotIndex,
    required this.gameUid,
    required this.ign,
    this.userId,
    this.readableId,
  });

  /// Slot 0 is always the joining user — auto-filled, non-editable.
  bool get isLeader => slotIndex == 0;

  /// True only when this slot belongs to a registered SS user (has a Firebase UID).
  bool get isRegisteredUser => userId != null;

  Map<String, dynamic> toMap() => {
    'slotIndex':                    slotIndex,
    'gameUid':                      gameUid,
    'ign':                          ign,
    if (userId     != null) 'userId':     userId,
    if (readableId != null) 'readableId': readableId,
  };

  factory TeamSlot.fromMap(Map<String, dynamic> d, int index) => TeamSlot(
    slotIndex:  index,
    gameUid:    (d['gameUid']    as String?) ?? '',
    ign:        (d['ign']        as String?) ?? '',
    userId:     d['userId']      as String?,
    readableId: d['readableId']  as String?,
  );

  TeamSlot copyWith({
    String? gameUid,
    String? ign,
    String? userId,
    String? readableId,
  }) => TeamSlot(
    slotIndex:  slotIndex,
    gameUid:    gameUid    ?? this.gameUid,
    ign:        ign        ?? this.ign,
    userId:     userId     ?? this.userId,
    readableId: readableId ?? this.readableId,
  );

  @override
  String toString() => 'TeamSlot(idx=$slotIndex, uid=$gameUid, ign=$ign)';
}