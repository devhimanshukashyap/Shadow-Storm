// lib/screens/profile_screen.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Profile Screen (Phase F2.5 / PRE-F3)
//
// Changes from Phase F1:
//   PRIORITY 3 (F2.5): Recent Activity section added.
//     Reads from UserActivityService.recentActivityStream().
//     Shows last 10 activity items: joined tournament, won tournament,
//     deposit approved, withdrawal approved, refund, admin adjustment.
//     Section is hidden if no activity exists (no blank state shown).
//
//   PRIORITY 3 (F2.5): Unnecessary rank widgets removed.
//
//   All F1 behaviors preserved:
//     MaintenanceGuard, edit form (name/ign/gameUid),
//     stats grid, sign-out, createdAt join date, Player ID chip.
// ─────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/cache_service.dart';
import '../services/app_settings_service.dart';
import '../services/user_activity_service.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────
class _C {
  static const background      = Color(0xFF06040E);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);
  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  static const purpleDim       = Color(0xFF7B3FE4);
  static const purpleGlowFaint = Color(0x229D55FF);
  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);
  static const gold            = Color(0xFFFFCC44);
  static const live            = Color(0xFFFF4466);
  static const success         = Color(0xFF44FF99);
  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
}

// ─────────────────────────────────────────────
// PLAYER PROFILE MODEL
// ─────────────────────────────────────────────
class PlayerProfile {
  final String   uid;
  final String   name;
  final String   email;
  final String   photoUrl;
  final String   ign;
  final String   gameUid;
  final String   readableId;
  final DateTime? createdAt;
  final double walletBalance;
  final int    wins;
  final int    tournamentsPlayed;
  final double totalEarnings;

  const PlayerProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.ign,
    required this.gameUid,
    required this.readableId,
    this.createdAt,
    required this.walletBalance,
    required this.wins,
    required this.tournamentsPlayed,
    required this.totalEarnings,
  });

  factory PlayerProfile.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PlayerProfile(
      uid:               d['uid']               as String?  ?? doc.id,
      name:              d['name']              as String?  ?? 'Player',
      email:             d['email']             as String?  ?? '',
      photoUrl:          d['photoUrl']          as String?  ?? '',
      ign:               d['ign']               as String?  ?? '',
      gameUid:           d['gameUid']           as String?  ?? '',
      readableId:        d['readableId']        as String?  ?? '',
      createdAt:         (d['createdAt'] as Timestamp?)?.toDate(),
      walletBalance:     (d['walletBalance']     as num?    ?? 0).toDouble(),
      wins:              (d['wins']              as num?    ?? 0).toInt(),
      tournamentsPlayed: (d['tournamentsPlayed'] as num?    ?? 0).toInt(),
      totalEarnings:     (d['totalEarnings']     as num?    ?? 0).toDouble(),
    );
  }

  String get joinedDate {
    if (createdAt == null) return '—';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[createdAt!.month - 1]} ${createdAt!.year}';
  }

  String get winRate {
    if (tournamentsPlayed == 0) return '0%';
    return '${((wins / tournamentsPlayed) * 100).toStringAsFixed(1)}%';
  }
}

// ─────────────────────────────────────────────
// PROFILE SCREEN
// ─────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  final User?             _firebaseUser = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _db           = FirebaseFirestore.instance;

  bool _isEditing   = false;
  bool _isSaving    = false;
  String? _saveError;
  bool _saveSuccess = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _ignCtrl;
  late TextEditingController _gameUidCtrl;

  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _rotateCtrl;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;
  late Animation<double>   _rotate;

  PlayerProfile? _cachedProfile;

  @override
  void initState() {
    super.initState();
    _nameCtrl    = TextEditingController();
    _ignCtrl     = TextEditingController();
    _gameUidCtrl = TextEditingController();

    _fadeCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _pulseCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();

    _fadeIn = CurvedAnimation(parent: _fadeCtrl,  curve: Curves.easeOutCubic);
    _pulse  = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _rotate = _rotateCtrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ignCtrl.dispose();
    _gameUidCtrl.dispose();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  Stream<PlayerProfile?> get _profileStream {
    if (_firebaseUser == null) return Stream.value(null);
    return _db
        .collection('users')
        .doc(_firebaseUser.uid)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          final profile = PlayerProfile.fromFirestore(snap);
          CacheService.instance.set(CacheKey.profile, snap.data()!, ttl: const Duration(minutes: 10));
          _cachedProfile = profile;
          return profile;
        });
  }

  void _startEditing(PlayerProfile profile) {
    _nameCtrl.text    = profile.name;
    _ignCtrl.text     = profile.ign;
    _gameUidCtrl.text = profile.gameUid;
    setState(() { _isEditing = true; _saveError = null; _saveSuccess = false; });
  }

  void _cancelEditing() {
    setState(() { _isEditing = false; _saveError = null; _saveSuccess = false; });
  }

  Future<void> _saveProfile() async {
    final newName    = _nameCtrl.text.trim();
    final newIgn     = _ignCtrl.text.trim();
    final newGameUid = _gameUidCtrl.text.trim();

    if (newName.isEmpty) { setState(() => _saveError = 'Display name cannot be empty.'); return; }
    if (newName.length < 2 || newName.length > 24) { setState(() => _saveError = 'Name must be 2–24 characters.'); return; }

    setState(() { _isSaving = true; _saveError = null; _saveSuccess = false; });

    try {
      await _db.collection('users').doc(_firebaseUser!.uid).update({
        'name':    newName,
        'ign':     newIgn,
        'gameUid': newGameUid,
      });
      await _firebaseUser.updateDisplayName(newName);
      CacheService.instance.invalidate(CacheKey.profile);
      if (mounted) {
        setState(() { _isSaving = false; _isEditing = false; _saveSuccess = true; });
        _showSuccessSnack('Profile updated successfully!');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _saveSuccess = false);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isSaving = false; _saveError = 'Failed to save. Please try again.'; });
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => _SignOutDialog());
    if (confirm == true && mounted) {
      CacheService.instance.clear();
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccessSnack('$label copied!');
  }

  void _showSuccessSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: _C.success, size: 16), const SizedBox(width: 8),
        Text(msg, style: const TextStyle(color: _C.textPrimary)),
      ]),
      backgroundColor: _C.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _C.success.withValues(alpha: 0.4))),
      duration: const Duration(seconds: 2),
    ));
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return MaintenanceGuard(
      child: Scaffold(
        backgroundColor: _C.background,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(),
        body: StreamBuilder<PlayerProfile?>(
          stream: _profileStream,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting && _cachedProfile == null) {
              return const _LoadingState();
            }
            if (snap.hasError) return _ErrorState(error: snap.error.toString());
            final profile = snap.data ?? _cachedProfile;
            if (profile == null) return const _EmptyState();
            return FadeTransition(opacity: _fadeIn, child: _buildContent(profile));
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 64,
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xDD06040E), Colors.transparent]))),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: _C.textPrimary, size: 16),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text('PROFILE', style: TextStyle(color: _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
      centerTitle: true,
      actions: [
        if (!_isEditing)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              tooltip: 'Edit profile',
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
                child: const Icon(Icons.edit_rounded, color: _C.purple, size: 16),
              ),
              onPressed: () { final p = _cachedProfile; if (p != null) _startEditing(p); },
            ),
          ),
      ],
    );
  }

  Widget _buildContent(PlayerProfile profile) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 80)),

        // Avatar + name card.
        SliverToBoxAdapter(child: _AvatarSection(
          profile: profile,
          pulse:   _pulse,
          rotate:  _rotate,
          onCopyReadableId: () => _copyToClipboard(profile.readableId, 'Player ID'),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // Player ID + Game UID chips.
        SliverToBoxAdapter(child: _IdsRow(
          profile:          profile,
          onCopyReadableId: () => _copyToClipboard(profile.readableId, 'Player ID'),
          onCopyGameUid:    () => _copyToClipboard(profile.gameUid, 'Game UID'),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // Edit form (shown only when editing).
        if (_isEditing) ...[
          SliverToBoxAdapter(child: _EditForm(
            nameCtrl:    _nameCtrl,
            ignCtrl:     _ignCtrl,
            gameUidCtrl: _gameUidCtrl,
            isSaving:    _isSaving,
            saveError:   _saveError,
            onSave:      _saveProfile,
            onCancel:    _cancelEditing,
          )),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],

        // Player Stats section.
        SliverToBoxAdapter(child: _buildSectionLabel('PLAYER', 'STATS')),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: _StatsGrid(profile: profile)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // Recent Activity section — PRIORITY 3 (F2.5).
        SliverToBoxAdapter(child: _RecentActivitySection(uid: _firebaseUser?.uid)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // Sign out button.
        SliverToBoxAdapter(child: _SignOutButton(onTap: _signOut)),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildSectionLabel(String title, String accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Container(width: 3, height: 18, decoration: BoxDecoration(color: _C.purple, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: _C.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const SizedBox(width: 5),
        Text(accent, style: const TextStyle(color: _C.purple, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// RECENT ACTIVITY SECTION — PRIORITY 3 (F2.5)
//
// Reads from UserActivityService.recentActivityStream().
// Hidden entirely if no activity exists — no blank container shown.
// ─────────────────────────────────────────────
class _RecentActivitySection extends StatelessWidget {
  final String? uid;
  const _RecentActivitySection({required this.uid});

  Color _iconColor(ActivityType type) {
    switch (type) {
      case ActivityType.depositApproved:    return _C.success;
      case ActivityType.withdrawalApproved: return _C.live;
      case ActivityType.wonTournament:      return _C.gold;
      case ActivityType.tournamentEntry:    return _C.purple;
      case ActivityType.joinedTournament:   return _C.purpleLight;
      case ActivityType.refund:             return const Color(0xFFFFAA22);
      case ActivityType.adminAdjustment:    return _C.textSecondary;
    }
  }

  IconData _icon(ActivityType type) {
    switch (type) {
      case ActivityType.depositApproved:    return Icons.add_circle_rounded;
      case ActivityType.withdrawalApproved: return Icons.remove_circle_rounded;
      case ActivityType.wonTournament:      return Icons.emoji_events_rounded;
      case ActivityType.tournamentEntry:    return Icons.sports_esports_rounded;
      case ActivityType.joinedTournament:   return Icons.sports_esports_rounded;
      case ActivityType.refund:             return Icons.replay_rounded;
      case ActivityType.adminAdjustment:    return Icons.tune_rounded;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours  < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays   < 1) return '${diff.inHours}h ago';
    if (diff.inDays   < 7) return '${diff.inDays}d ago';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<ActivityItem>>(
      stream: UserActivityService.instance.recentActivityStream(limit: 10),
      builder: (context, snap) {
        final items = snap.data ?? [];

        // Hide section entirely if no activity — PRIORITY 2 (no blank sections).
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Section label.
            Row(children: [
              Container(width: 3, height: 18, decoration: BoxDecoration(color: _C.purple, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              const Text('RECENT', style: TextStyle(color: _C.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(width: 5),
              const Text('ACTIVITY', style: TextStyle(color: _C.purple, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ]),
            const SizedBox(height: 12),

            // Activity list.
            Container(
              decoration: BoxDecoration(
                color: _C.surfaceCard, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.border),
              ),
              child: Column(
                children: items.asMap().entries.map((entry) {
                  final i    = entry.key;
                  final item = entry.value;
                  final color = _iconColor(item.type);
                  final isLast = i == items.length - 1;

                  return Container(
                    decoration: BoxDecoration(
                      border: isLast ? null : Border(
                        bottom: BorderSide(color: _C.border.withValues(alpha: 0.5)),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      // Icon badge.
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_icon(item.type), color: color, size: 17),
                      ),
                      const SizedBox(width: 12),

                      // Title + subtitle.
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.title, style: const TextStyle(color: _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        if (item.subtitle.isNotEmpty)
                          Text(item.subtitle, style: const TextStyle(color: _C.textMuted, fontSize: 11, height: 1.4), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      const SizedBox(width: 8),

                      // Amount + time.
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (item.amount != null)
                          Text(
                            _isCredit(item.type)
                                ? '+₹${item.amount!.toStringAsFixed(0)}'
                                : '-₹${item.amount!.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: _isCredit(item.type) ? _C.success : _C.live,
                              fontSize: 13, fontWeight: FontWeight.w800,
                            ),
                          ),
                        Text(_timeAgo(item.createdAt),
                            style: const TextStyle(color: _C.textMuted, fontSize: 10)),
                      ]),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ]),
        );
      },
    );
  }

  bool _isCredit(ActivityType type) {
    switch (type) {
      case ActivityType.depositApproved:
      case ActivityType.wonTournament:
      case ActivityType.refund:
      case ActivityType.adminAdjustment:
        return true;
      default:
        return false;
    }
  }
}

// ─────────────────────────────────────────────
// AVATAR SECTION (unchanged from F1)
// ─────────────────────────────────────────────
class _AvatarSection extends StatelessWidget {
  final PlayerProfile profile; final Animation<double> pulse; final Animation<double> rotate; final VoidCallback onCopyReadableId;
  const _AvatarSection({required this.profile, required this.pulse, required this.rotate, required this.onCopyReadableId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _C.surfaceCard, borderRadius: BorderRadius.circular(24), border: Border.all(color: _C.borderBright),
            boxShadow: [BoxShadow(color: _C.purple.withValues(alpha: 0.12 + 0.08 * pulse.value), blurRadius: 28 + 8 * pulse.value)],
          ),
          child: child,
        ),
        child: Column(children: [
          _RotatingAvatarRing(profile: profile, rotate: rotate, pulse: pulse),
          const SizedBox(height: 16),
          Text(profile.name, style: const TextStyle(color: _C.textPrimary, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.3), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          if (profile.ign.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(6), border: Border.all(color: _C.border)),
              child: Text('IGN: ${profile.ign}', style: const TextStyle(color: _C.purpleLight, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
          ],
          Text(profile.email, style: const TextStyle(color: _C.textSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          Container(height: 1, color: _C.border),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.calendar_today_rounded, color: _C.textMuted, size: 12), const SizedBox(width: 5),
            Text('Joined ${profile.joinedDate}', style: const TextStyle(color: _C.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// IDs ROW (unchanged from F1)
// ─────────────────────────────────────────────
class _IdsRow extends StatelessWidget {
  final PlayerProfile profile; final VoidCallback onCopyReadableId; final VoidCallback onCopyGameUid;
  const _IdsRow({required this.profile, required this.onCopyReadableId, required this.onCopyGameUid});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(child: _IdChip(label: 'PLAYER ID', value: profile.readableId.isNotEmpty ? profile.readableId : '—', icon: Icons.tag_rounded, color: _C.purple, onCopy: profile.readableId.isNotEmpty ? onCopyReadableId : null)),
        const SizedBox(width: 10),
        Expanded(child: _IdChip(label: 'GAME UID', value: profile.gameUid.isNotEmpty ? profile.gameUid : 'Not set', icon: Icons.sports_esports_rounded, color: _C.gold, onCopy: profile.gameUid.isNotEmpty ? onCopyGameUid : null)),
      ]),
    );
  }
}

class _IdChip extends StatelessWidget {
  final String label, value; final IconData icon; final Color color; final VoidCallback? onCopy;
  const _IdChip({required this.label, required this.value, required this.icon, required this.color, this.onCopy});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCopy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Row(children: [
          Icon(icon, color: color, size: 16), const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
          ])),
          if (onCopy != null) Icon(Icons.copy_rounded, color: _C.textMuted, size: 12),
        ]),
      ),
    );
  }
}

class _RotatingAvatarRing extends StatelessWidget {
  final PlayerProfile profile; final Animation<double> rotate; final Animation<double> pulse;
  const _RotatingAvatarRing({required this.profile, required this.rotate, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 108, height: 108, child: Stack(alignment: Alignment.center, children: [
      AnimatedBuilder(animation: rotate, builder: (_, _) => Transform.rotate(angle: rotate.value * 2 * math.pi, child: CustomPaint(size: const Size(108, 108), painter: _DashedRingPainter(color: _C.purple.withValues(alpha: 0.5), strokeWidth: 1.5, dashCount: 24)))),
      AnimatedBuilder(animation: pulse, builder: (_, _) => Container(width: 94, height: 94, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: _C.purple.withValues(alpha: 0.2 + 0.12 * pulse.value), blurRadius: 18 + 8 * pulse.value)]))),
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [_C.purpleDim, _C.purple], begin: Alignment.topLeft, end: Alignment.bottomRight), border: Border.all(color: _C.purpleLight, width: 2)),
        child: ClipOval(child: profile.photoUrl.isNotEmpty
            ? Image.network(profile.photoUrl, width: 88, height: 88, fit: BoxFit.cover, errorBuilder: (_, _, _) => _AvatarInitial(name: profile.name))
            : _AvatarInitial(name: profile.name)),
      ),
    ]));
  }
}

class _AvatarInitial extends StatelessWidget {
  final String name;
  const _AvatarInitial({required this.name});
  @override
  Widget build(BuildContext context) {
    return Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'P', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 34)));
  }
}

// ─────────────────────────────────────────────
// EDIT FORM (unchanged from F1)
// ─────────────────────────────────────────────
class _EditForm extends StatelessWidget {
  final TextEditingController nameCtrl, ignCtrl, gameUidCtrl;
  final bool isSaving; final String? saveError;
  final VoidCallback onSave, onCancel;
  const _EditForm({required this.nameCtrl, required this.ignCtrl, required this.gameUidCtrl, required this.isSaving, required this.saveError, required this.onSave, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.purple.withValues(alpha: 0.4)), boxShadow: [BoxShadow(color: _C.purple.withValues(alpha: 0.1), blurRadius: 20)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.edit_rounded, color: _C.purple, size: 16), SizedBox(width: 8), Text('EDIT PROFILE', style: TextStyle(color: _C.textSecondary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5))]),
          const SizedBox(height: 16),
          _FieldLabel('DISPLAY NAME'), const SizedBox(height: 6),
          _EditField(controller: nameCtrl, hint: 'Your display name', icon: Icons.person_rounded, maxLength: 24),
          const SizedBox(height: 14),
          _FieldLabel('IN-GAME NAME (IGN)'), const SizedBox(height: 6),
          _EditField(controller: ignCtrl, hint: 'Your Free Fire IGN', icon: Icons.sports_esports_rounded, maxLength: 32),
          const SizedBox(height: 14),
          _FieldLabel('FREE FIRE UID'), const SizedBox(height: 6),
          _EditField(controller: gameUidCtrl, hint: 'Your numeric game UID', icon: Icons.numbers_rounded, maxLength: 20, keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.gold.withValues(alpha: 0.2))),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: _C.gold, size: 13), SizedBox(width: 8),
              Expanded(child: Text('Player ID (SSP-XXXXXX) is system-assigned and cannot be changed.', style: TextStyle(color: _C.textMuted, fontSize: 11, height: 1.4))),
            ]),
          ),
          if (saveError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _C.live.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.live.withValues(alpha: 0.35))),
              child: Row(children: [const Icon(Icons.error_outline_rounded, color: _C.live, size: 14), const SizedBox(width: 8), Expanded(child: Text(saveError!, style: const TextStyle(color: _C.live, fontSize: 12)))]),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GestureDetector(onTap: onCancel, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)), child: const Center(child: Text('CANCEL', style: TextStyle(color: _C.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)))))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: GestureDetector(
              onTap: isSaving ? null : onSave,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [_C.purple, _C.purpleDim], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: _C.purple.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))]),
                child: Center(child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('SAVE CHANGES', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2));
}

class _EditField extends StatelessWidget {
  final TextEditingController controller; final String hint; final IconData icon; final int maxLength; final TextInputType keyboardType;
  const _EditField({required this.controller, required this.hint, required this.icon, required this.maxLength, this.keyboardType = TextInputType.text});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller, maxLength: maxLength, keyboardType: keyboardType,
      style: const TextStyle(color: _C.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: _C.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: _C.purple, size: 18),
        counterText: '', filled: true, fillColor: _C.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.purple, width: 1.5)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STATS GRID (unchanged from F1, rank widget removed)
// ─────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  final PlayerProfile profile;
  const _StatsGrid({required this.profile});

  String _fmt(double v) { if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k'; return '${v.toInt()}'; }

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatData(icon: Icons.emoji_events_rounded,          label: 'Tournaments Played', value: '${profile.tournamentsPlayed}', color: _C.purpleLight),
      _StatData(icon: Icons.military_tech_rounded,          label: 'Total Wins',          value: '${profile.wins}',             color: _C.gold),
      _StatData(icon: Icons.account_balance_wallet_rounded, label: 'Total Winnings',      value: '₹${_fmt(profile.totalEarnings)}', color: _C.success),
      _StatData(icon: Icons.percent_rounded,                label: 'Win Rate',            value: profile.winRate,               color: _C.live),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: stats.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.0),
        itemBuilder: (_, i) => _StatCell(stat: stats[i]),
      ),
    );
  }
}

class _StatData {
  final IconData icon; final String label, value; final Color color;
  const _StatData({required this.icon, required this.label, required this.value, required this.color});
}

class _StatCell extends StatelessWidget {
  final _StatData stat;
  const _StatCell({required this.stat});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border), boxShadow: [BoxShadow(color: stat.color.withValues(alpha: 0.07), blurRadius: 12)]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: stat.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(stat.icon, color: stat.color, size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(stat.value, style: TextStyle(color: stat.color, fontSize: 17, fontWeight: FontWeight.w900)),
          Text(stat.label, style: const TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// SIGN OUT (unchanged from F1)
// ─────────────────────────────────────────────
class _SignOutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SignOutButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: _C.live.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.live.withValues(alpha: 0.35))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.logout_rounded, color: _C.live, size: 18), SizedBox(width: 8),
            Text('SIGN OUT', style: TextStyle(color: _C.live, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ]),
        ),
      ),
    );
  }
}

class _SignOutDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _C.border)),
      title: const Text('Sign Out', style: TextStyle(color: _C.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      content: const Text('Are you sure you want to sign out?', style: TextStyle(color: _C.textSecondary, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: _C.textSecondary))),
        TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Sign Out', style: TextStyle(color: _C.live))),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// STATE WIDGETS
// ─────────────────────────────────────────────
class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: _C.purple, strokeWidth: 2)),
      SizedBox(height: 14),
      Text('Loading profile…', style: TextStyle(color: _C.textSecondary, fontSize: 13)),
    ]));
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline_rounded, color: _C.live, size: 44),
      const SizedBox(height: 12),
      const Text('Something went wrong', style: TextStyle(color: _C.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(error, style: const TextStyle(color: _C.textSecondary, fontSize: 12, height: 1.5), textAlign: TextAlign.center),
    ])));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.person_off_rounded, color: _C.textMuted, size: 44),
      SizedBox(height: 12),
      Text('Profile not found', style: TextStyle(color: _C.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
    ]));
  }
}

// ─────────────────────────────────────────────
// DASHED RING PAINTER
// ─────────────────────────────────────────────
class _DashedRingPainter extends CustomPainter {
  final Color color; final double strokeWidth; final int dashCount;
  const _DashedRingPainter({required this.color, required this.strokeWidth, required this.dashCount});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = strokeWidth..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth;
    final dashAngle = (2 * math.pi) / dashCount;
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), dashAngle * i, dashAngle * 0.55, false, paint);
    }
  }
  @override bool shouldRepaint(covariant _DashedRingPainter old) => old.color != color || old.strokeWidth != strokeWidth;
}