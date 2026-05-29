// lib/screens/home_screen.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Home Screen (Phase F1)
//
// Changes from v3:
//   PRIORITY 3: Scaffold is now wrapped with MaintenanceGuard.
//     When maintenanceMode=true, the maintenance screen is shown
//     instead of the home body — including the nav bar.
//   PRIORITY 4: walletFrozen banner updated — tournament join is also
//     blocked when wallet is frozen (message updated accordingly).
//   All original v3 widgets, filters, animations, and navigation intact.
// ─────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/wallet_service.dart';
import '../services/tournament_service.dart';
import '../services/app_settings_service.dart';
import '../services/cache_service.dart';
import '../models/tournament_model.dart';
import 'profile_screen.dart';
import 'tournament_details_screen.dart';
import 'all_tournaments_screen.dart';
import '../screens/events_screen.dart';
import '../screens/wallet_screen.dart';
import '../screens/ranks_screen.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────
class SSColors {
  static const background      = Color(0xFF06040E);
  static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);
  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  static const purpleDim       = Color(0xFF7B3FE4);
  static const purpleDark      = Color(0xFF3C2570);
  static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);
  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);
  static const textOnPurple    = Color(0xFFFFFFFF);
  static const gold            = Color(0xFFFFCC44);
  static const live            = Color(0xFFFF4466);
  static const liveGlow        = Color(0x55FF4466);
  static const success         = Color(0xFF44FF99);
  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
}

class SSTextStyles {
  static const _base = TextStyle(color: SSColors.textPrimary);
  static final displayLarge = _base.copyWith(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5);
  static final titleLarge   = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2);
  static final titleMedium  = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.15);
  static final titleSmall   = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1);
  static final bodyMedium   = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: SSColors.textSecondary);
  static final labelLarge   = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: SSColors.textSecondary);
  static final labelSmall   = _base.copyWith(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: SSColors.textMuted);
  static final monoPrize    = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: SSColors.gold);
}

class _FilterOption {
  final String value, label, emoji;
  const _FilterOption({required this.value, required this.label, required this.emoji});
}

class _StatusOption {
  final String   value, label;
  final Color    color;
  final IconData icon;
  const _StatusOption({required this.value, required this.label, required this.color, required this.icon});
}

const _filterOptions = [
  _FilterOption(value: 'all',           label: 'All',           emoji: '⚡'),
  _FilterOption(value: 'battle_royale', label: 'Battle Royale', emoji: '🗺️'),
  _FilterOption(value: 'clash_squad',   label: 'Clash Squad',   emoji: '⚔️'),
  _FilterOption(value: '2v2',           label: '2v2 Arena',     emoji: '🤝'),
  _FilterOption(value: 'lone_wolf',     label: 'Lone Wolf',     emoji: '🎯'),
  _FilterOption(value: 'lose_to_win',   label: 'Lose To Win',   emoji: '🔄'),
  _FilterOption(value: '1v1_arena',     label: '1v1 Arena',     emoji: '🥊'),
  _FilterOption(value: 'sniper',        label: 'Sniper',        emoji: '🔭'),
  _FilterOption(value: 'custom_league', label: 'League',        emoji: '🏆'),
];

const _statusOptions = [
  _StatusOption(value: 'all',       label: 'All',       color: SSColors.purpleLight, icon: Icons.grid_view_rounded),
  _StatusOption(value: 'live',      label: 'Live',      color: SSColors.live,        icon: Icons.radio_button_checked),
  _StatusOption(value: 'upcoming',  label: 'Upcoming',  color: SSColors.gold,        icon: Icons.schedule_rounded),
  _StatusOption(value: 'completed', label: 'Completed', color: SSColors.textMuted,   icon: Icons.check_circle_outline_rounded),
];

// ─────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _navIndex = 0;

  final AuthService       _authService       = AuthService();
  final TournamentService _tournamentService = TournamentService.instance;
  final WalletService     _walletService     = WalletService.instance;

  User? get _currentUser => _authService.currentUser;
  String? get _userId    => _currentUser?.uid;

  Set<String> _joinedIds = {};
  StreamSubscription<Set<String>>? _joinedSub;

  String _typeFilter   = 'all';
  String _statusFilter = 'all';

  int  _tournamentsPlayed = 0;
  int  _wins              = 0;
  bool _statsLoaded       = false;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))..forward();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _pulse  = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

    if (_userId != null) {
      _joinedSub = _tournamentService
          .joinedTournamentIdsStream(_userId!)
          .listen((ids) {
        if (mounted) setState(() => _joinedIds = ids);
      });
      _loadStats();
    }
    // Warm up settings stream (single shared listener for whole app).
    AppSettingsService.instance.settingsStream.listen((_) {});
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _joinedSub?.cancel();
    super.dispose();
  }

  // PRIORITY 8: Cache-first stats load.
  Future<void> _loadStats() async {
    // Show cache immediately if available.
    final cached = CacheService.instance.get<Map<String, dynamic>>(CacheKey.profileStats);
    if (cached != null) {
      setState(() {
        _tournamentsPlayed = (cached['tournamentsPlayed'] as int?) ?? 0;
        _wins              = (cached['wins'] as int?) ?? 0;
        _statsLoaded       = true;
      });
      // Only fetch fresh if cache is expired.
      if (!CacheService.instance.isFresh(CacheKey.profileStats)) {
        await _fetchFreshStats();
      }
      return;
    }
    // No cache — fetch immediately.
    await _fetchFreshStats();
  }

  Future<void> _fetchFreshStats() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .get(const GetOptions(source: Source.serverAndCache));
      final data = doc.data() ?? {};
      final tp   = (data['tournamentsPlayed'] as num?)?.toInt() ?? 0;
      final w    = (data['wins']              as num?)?.toInt() ?? 0;
      CacheService.instance.set(
        CacheKey.profileStats,
        {'tournamentsPlayed': tp, 'wins': w},
        ttl: const Duration(minutes: 5),
      );
      if (mounted) setState(() { _tournamentsPlayed = tp; _wins = w; _statsLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _statsLoaded = true);
    }
  }

  Future<void> _onRefresh() async {
    // Pull-to-refresh: invalidate cache then reload fresh.
    _tournamentService.invalidateTournamentCache();
    CacheService.instance.invalidate(CacheKey.profileStats);
    _statsLoaded = false;
    await _fetchFreshStats();
  }

  void _openProfile() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));

  void _openWallet() =>
      Navigator.push(context, _fadeRoute(const WalletScreen()));

  void _openRanks() =>
      Navigator.push(context, _fadeRoute(const RanksScreen()));

  void _openTournamentDetails(TournamentModel t) =>
      Navigator.push(context, _fadeRoute(TournamentDetailsScreen(tournament: t)));

  void _openAllTournaments({String? statusFilter, String? typeFilter, String? title}) =>
      Navigator.push(context, _fadeRoute(AllTournamentsScreen(
        title:         title ?? 'All Tournaments',
        initialStatus: statusFilter,
        initialType:   typeFilter,
      )));

  PageRouteBuilder _fadeRoute(Widget page) => PageRouteBuilder(
    pageBuilder: (_, anim, _) => page,
    transitionsBuilder: (_, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 350),
  );

  // ─────────────────────────────────────────────
  // BUILD
  // PRIORITY 3: MaintenanceGuard wraps the entire Scaffold.
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return MaintenanceGuard(
      child: Scaffold(
        backgroundColor: SSColors.background,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(),
        body: FadeTransition(
          opacity: _fadeIn,
          child: _navIndex == 1
              ? const EventsScreen()
              : _buildHomeBody(),
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HOME BODY
  // NOTE: The inner StreamBuilder for settings only handles
  // wallet frozen banner now. Maintenance is handled by MaintenanceGuard above.
  // ─────────────────────────────────────────────
  Widget _buildHomeBody() {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.instance.settingsStream,
      builder: (context, settingsSnap) {
        final settings = settingsSnap.data ?? const AppSettings();

        return RefreshIndicator(
          color: SSColors.purple,
          backgroundColor: SSColors.surfaceCard,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.top + 64 + 12),
              ),

              // PRIORITY 4: Wallet frozen banner.
              if (settings.walletFrozen)
                SliverToBoxAdapter(
                  child: _WalletFrozenBanner(reason: settings.walletFreezeReason),
                ),

              SliverToBoxAdapter(
                child: _StatsBar(
                  tournamentsPlayed: _tournamentsPlayed,
                  wins:              _wins,
                  loaded:            _statsLoaded,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),

              SliverToBoxAdapter(
                child: _StatusFilterRow(
                  selected:  _statusFilter,
                  pulse:     _pulse,
                  onChanged: (v) => setState(() => _statusFilter = v),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              SliverToBoxAdapter(
                child: _FilterChipRow(
                  selected:  _typeFilter,
                  onChanged: (v) => setState(() => _typeFilter = v),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              if (_statusFilter == 'all' || _statusFilter == 'upcoming')
                SliverToBoxAdapter(
                  child: _FeaturedSection(
                    stream:     _tournamentService.featuredTournamentStream(),
                    pulse:      _pulse,
                    joinedIds:  _joinedIds,
                    typeFilter: _typeFilter,
                    onTap:      _openTournamentDetails,
                  ),
                ),

              if (_statusFilter == 'all' || _statusFilter == 'upcoming')
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

              SliverToBoxAdapter(child: _buildFeedHeader()),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              SliverToBoxAdapter(
                child: _TournamentFeedSection(
                  service:      _tournamentService,
                  joinedIds:    _joinedIds,
                  typeFilter:   _typeFilter,
                  statusFilter: _statusFilter,
                  pulse:        _pulse,
                  onTap:        _openTournamentDetails,
                  onSeeAll: () => _openAllTournaments(
                    statusFilter: _statusFilter == 'all' ? null : _statusFilter,
                    typeFilter:   _typeFilter   == 'all' ? null : _typeFilter,
                    title:        _feedTitle,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  String get _feedTitle {
    final statusLabel = switch (_statusFilter) {
      'live'      => 'Live',
      'upcoming'  => 'Upcoming',
      'completed' => 'Completed',
      _           => 'All',
    };
    final typeLabel = _filterOptions
        .firstWhere((o) => o.value == _typeFilter,
            orElse: () => const _FilterOption(value: 'all', label: 'All', emoji: '⚡'))
        .label;
    if (_typeFilter == 'all') return '$statusLabel Tournaments';
    return '$statusLabel $typeLabel Tournaments';
  }

  Widget _buildFeedHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(color: SSColors.purple, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _feedTitle.toUpperCase(),
            style: SSTextStyles.labelLarge.copyWith(fontSize: 12, letterSpacing: 1.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: () => _openAllTournaments(
            statusFilter: _statusFilter == 'all' ? null : _statusFilter,
            typeFilter:   _typeFilter   == 'all' ? null : _typeFilter,
            title:        _feedTitle,
          ),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('See All', style: SSTextStyles.labelLarge.copyWith(
                  color: SSColors.purple, fontSize: 11)),
              const Icon(Icons.chevron_right_rounded, color: SSColors.purple, size: 16),
            ]),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // APP BAR (unchanged from v3)
  // ─────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 64,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xEE06040E), Colors.transparent],
          ),
        ),
      ),
      leadingWidth: 0,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: SSColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SSColors.border),
              boxShadow: [BoxShadow(color: SSColors.purpleGlow, blurRadius: 10)],
            ),
            child: const Center(child: Icon(Icons.bolt_rounded, color: SSColors.purple, size: 22)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SHADOW STORM', style: SSTextStyles.titleSmall.copyWith(
                color: SSColors.purple, letterSpacing: 1.5, fontSize: 11,
              )),
              Text(
                'Welcome, ${_currentUser?.displayName?.split(' ').first ?? 'Striker'}',
                style: SSTextStyles.bodyMedium.copyWith(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )),
          GestureDetector(
            onTap: _openWallet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: SSColors.surfaceCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: SSColors.border),
                boxShadow: [BoxShadow(color: SSColors.purpleGlowFaint, blurRadius: 10)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wallet_rounded, color: SSColors.gold, size: 15),
                const SizedBox(width: 5),
                StreamBuilder<WalletData>(
                  stream: _walletService.walletDataStream(),
                  builder: (_, snap) {
                    final balance = snap.data?.balance ?? 0.0;
                    final loading = snap.connectionState == ConnectionState.waiting;
                    return Text(
                      loading ? '…' : '₹${balance.toStringAsFixed(0)}',
                      style: SSTextStyles.titleSmall.copyWith(
                          color: SSColors.gold, fontSize: 13),
                    );
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _openProfile,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [SSColors.purpleDim, SSColors.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                border: Border.all(color: SSColors.purpleLight, width: 1.5),
                boxShadow: [BoxShadow(color: SSColors.purpleGlow, blurRadius: 10)],
              ),
              child: ClipOval(child: _currentUser?.photoURL != null
                  ? Image.network(_currentUser!.photoURL!,
                      width: 38, height: 38, fit: BoxFit.cover)
                  : Center(child: Text(
                      (_currentUser?.displayName?.isNotEmpty == true)
                          ? _currentUser!.displayName![0].toUpperCase()
                          : 'P',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                    ))),
            ),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BOTTOM NAV (unchanged from v3)
  // ─────────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      _NavItem(icon: Icons.home_rounded,                   label: 'Home'),
      _NavItem(icon: Icons.emoji_events_rounded,           label: 'Events'),
      _NavItem(icon: Icons.leaderboard_rounded,            label: 'Ranks'),
      _NavItem(icon: Icons.account_balance_wallet_rounded, label: 'Wallet'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: SSColors.surface,
        border: const Border(top: BorderSide(color: SSColors.border, width: 1)),
        boxShadow: [BoxShadow(
          color: SSColors.purpleGlow.withValues(alpha: 0.3),
          blurRadius: 20, offset: const Offset(0, -4),
        )],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List.generate(items.length, (i) {
              final active = (i < 2) && (i == _navIndex);
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (i == 2) { _openRanks();  return; }
                    if (i == 3) { _openWallet(); return; }
                    setState(() => _navIndex = i);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: active ? SSColors.purpleGlowFaint : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(items[i].icon,
                          color: active ? SSColors.purple : SSColors.textMuted, size: 22),
                    ),
                    const SizedBox(height: 2),
                    Text(items[i].label, style: SSTextStyles.labelSmall.copyWith(
                      color: active ? SSColors.purple : SSColors.textMuted,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    )),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ALL EXISTING WIDGETS FROM v3 — UNCHANGED
// (StatusFilterRow, FilterChipRow, FeaturedSection,
//  TournamentFeedSection, TournamentListCard, FeaturedBanner,
//  StatsBar, all small reusable widgets, shimmer states, etc.)
// ─────────────────────────────────────────────

class _StatusFilterRow extends StatelessWidget {
  final String             selected;
  final Animation<double>  pulse;
  final void Function(String) onChanged;
  const _StatusFilterRow({required this.selected, required this.pulse, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _statusOptions.map((opt) {
          final active = selected == opt.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opt.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: active ? opt.color.withValues(alpha: 0.15) : SSColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? opt.color.withValues(alpha: 0.5) : SSColors.border,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    opt.value == 'live' && active
                        ? AnimatedBuilder(
                            animation: pulse,
                            builder: (_, _) => Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: SSColors.live.withValues(alpha: 0.5 + 0.5 * pulse.value),
                                boxShadow: [BoxShadow(
                                  color: SSColors.liveGlow.withValues(alpha: 0.4 * pulse.value),
                                  blurRadius: 6,
                                )],
                              ),
                            ),
                          )
                        : Icon(opt.icon, color: active ? opt.color : SSColors.textMuted, size: 14),
                    const SizedBox(height: 4),
                    Text(opt.label, style: TextStyle(
                      color: active ? opt.color : SSColors.textMuted,
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3,
                    )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  final String                 selected;
  final void Function(String)  onChanged;
  const _FilterChipRow({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _filterOptions.map((opt) {
          final active = selected == opt.value;
          return GestureDetector(
            onTap: () => onChanged(opt.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? SSColors.purpleGlowFaint : SSColors.surfaceCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? SSColors.purple.withValues(alpha: 0.65) : SSColors.border,
                  width: active ? 1.5 : 1,
                ),
                boxShadow: active
                    ? [BoxShadow(
                        color: SSColors.purpleGlow.withValues(alpha: 0.4),
                        blurRadius: 8)]
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(opt.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(opt.label, style: TextStyle(
                  color: active ? SSColors.purpleLight : SSColors.textMuted,
                  fontSize: 12, fontWeight: FontWeight.w700,
                )),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FeaturedSection extends StatelessWidget {
  final Stream<TournamentModel?>        stream;
  final Animation<double>               pulse;
  final Set<String>                     joinedIds;
  final String                          typeFilter;
  final void Function(TournamentModel)  onTap;
  const _FeaturedSection({required this.stream, required this.pulse, required this.joinedIds, required this.typeFilter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TournamentModel?>(
      stream: stream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _ShimmerPlaceholder(height: 200);
        }
        final t = snap.data;
        if (t == null) return const SizedBox.shrink();
        if (typeFilter != 'all' && t.tournamentType != typeFilter) {
          return const SizedBox.shrink();
        }
        return _FeaturedBanner(
          tournament: t, pulse: pulse,
          isJoined: joinedIds.contains(t.id), onTap: onTap,
        );
      },
    );
  }
}

class _TournamentFeedSection extends StatelessWidget {
  final TournamentService              service;
  final Set<String>                    joinedIds;
  final String                         typeFilter;
  final String                         statusFilter;
  final Animation<double>              pulse;
  final void Function(TournamentModel) onTap;
  final VoidCallback                   onSeeAll;
  const _TournamentFeedSection({required this.service, required this.joinedIds, required this.typeFilter, required this.statusFilter, required this.pulse, required this.onTap, required this.onSeeAll});

  Stream<List<TournamentModel>> _buildStream() {
    if (statusFilter == 'live')      return service.liveTournamentsStream();
    if (statusFilter == 'upcoming')  return service.upcomingTournamentsStream(limit: 30);
    if (statusFilter == 'completed') return service.completedTournamentsStream(limit: 30);
    return service.filteredTournamentsStream(
      typeFilter: typeFilter == 'all' ? null : typeFilter,
      limit: 50,
    );
  }

  List<TournamentModel> _applyTypeFilter(List<TournamentModel> list) {
    if (typeFilter == 'all') return list;
    return list.where((t) => t.tournamentType == typeFilter).toList();
  }

  List<TournamentModel> _sort(List<TournamentModel> list) {
    final live      = list.where((t) => t.status == TournamentStatus.live).toList();
    final upcoming  = list.where((t) => t.status == TournamentStatus.upcoming).toList()
      ..sort((a, b) {
        if (a.startTime == null) return 1;
        if (b.startTime == null) return -1;
        return a.startTime!.compareTo(b.startTime!);
      });
    final completed = list.where((t) => t.status == TournamentStatus.completed).toList()
      ..sort((a, b) {
        if (a.startTime == null) return 1;
        if (b.startTime == null) return -1;
        return b.startTime!.compareTo(a.startTime!);
      });
    final cancelled = list.where((t) => t.status == TournamentStatus.cancelled).toList();
    return [...live, ...upcoming, ...completed, ...cancelled];
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TournamentModel>>(
      stream: _buildStream(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Column(children: List.generate(4, (_) => const _ListCardShimmer()));
        }
        if (snap.hasError) {
          return _ErrorCard(message: 'Could not load tournaments.\n${snap.error}');
        }
        final filtered = _applyTypeFilter(snap.data ?? []);
        final sorted   = _sort(filtered);
        if (sorted.isEmpty) {
          return _EmptyCard(statusFilter: statusFilter, typeFilter: typeFilter);
        }
        return Column(
          children: sorted.map((t) => _TournamentListCard(
            tournament: t,
            isJoined:   joinedIds.contains(t.id),
            pulse:      pulse,
            onTap:      () => onTap(t),
            animIndex:  sorted.indexOf(t),
          )).toList(),
        );
      },
    );
  }
}

// ─── All remaining v3 widgets below (unchanged) ─────────────────────────────

class _TournamentListCard extends StatefulWidget {
  final TournamentModel   tournament;
  final bool              isJoined;
  final Animation<double> pulse;
  final VoidCallback      onTap;
  final int               animIndex;
  const _TournamentListCard({required this.tournament, required this.isJoined, required this.pulse, required this.onTap, required this.animIndex});
  @override State<_TournamentListCard> createState() => _TournamentListCardState();
}

class _TournamentListCardState extends State<_TournamentListCard> with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: 60 * widget.animIndex), () {
      if (mounted) _slideCtrl.forward();
    });
  }

  @override void dispose() { _slideCtrl.dispose(); super.dispose(); }

  Color _statusAccentColor(TournamentModel t) {
    switch (t.status) {
      case TournamentStatus.live:      return SSColors.live;
      case TournamentStatus.completed: return SSColors.textMuted;
      case TournamentStatus.upcoming:  return SSColors.purple;
      case TournamentStatus.cancelled: return SSColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final isLive = t.status == TournamentStatus.live;
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: AnimatedBuilder(
              animation: widget.pulse,
              builder: (_, child) => Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                decoration: BoxDecoration(
                  color: SSColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLive
                        ? SSColors.live.withValues(alpha: 0.3 + 0.2 * widget.pulse.value)
                        : widget.isJoined
                            ? SSColors.success.withValues(alpha: 0.3)
                            : SSColors.border,
                    width: (isLive || widget.isJoined) ? 1.5 : 1,
                  ),
                  boxShadow: [BoxShadow(
                    color: isLive
                        ? SSColors.live.withValues(alpha: 0.05 + 0.04 * widget.pulse.value)
                        : SSColors.purple.withValues(alpha: 0.06),
                    blurRadius: 12,
                  )],
                ),
                child: child,
              ),
              child: IntrinsicHeight(
                child: Row(children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: _statusAccentColor(t),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16), bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          _StatusPill(t.status),
                          const SizedBox(width: 6),
                          _TypePill(t.tournamentType),
                          if (t.isTeamTournament) ...[
                            const SizedBox(width: 6),
                            _TeamPill(t.teamSizeDisplay),
                          ],
                          if (widget.isJoined) ...[
                            const SizedBox(width: 6),
                            _JoinedPill(),
                          ],
                          const Spacer(),
                          Text(t.startTimeDisplay, style: const TextStyle(
                            color: SSColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600,
                          )),
                        ]),
                        const SizedBox(height: 8),
                        Text(t.title, style: const TextStyle(
                          color: SSColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800, height: 1.2,
                        ), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(t.subtitle, style: const TextStyle(
                          color: SSColors.textSecondary, fontSize: 12,
                        ), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 12),
                        Row(children: [
                          _Stat(icon: Icons.emoji_events_rounded, color: SSColors.gold, value: t.prizePoolDisplay),
                          const SizedBox(width: 16),
                          _Stat(icon: Icons.people_rounded, color: SSColors.purpleLight, value: '${t.joinedPlayers}/${t.maxPlayers}'),
                          const SizedBox(width: 16),
                          _Stat(icon: Icons.payments_rounded, color: t.entryFee > 0 ? SSColors.textSecondary : SSColors.success, value: t.entryFeeDisplay),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: SSColors.purpleGlowFaint,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: SSColors.border),
                            ),
                            child: const Icon(Icons.arrow_forward_ios_rounded, color: SSColors.purple, size: 12),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: t.fillPercent, minHeight: 3,
                            backgroundColor: SSColors.surfaceElevated,
                            valueColor: AlwaysStoppedAnimation(
                              t.isAlmostFull ? SSColors.live : SSColors.purple,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedBanner extends StatefulWidget {
  final TournamentModel              tournament;
  final Animation<double>            pulse;
  final bool                         isJoined;
  final void Function(TournamentModel) onTap;
  const _FeaturedBanner({required this.tournament, required this.pulse, required this.isJoined, required this.onTap});
  @override State<_FeaturedBanner> createState() => _FeaturedBannerState();
}

class _FeaturedBannerState extends State<_FeaturedBanner> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _pressed = false;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => widget.onTap(t),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedBuilder(
            animation: widget.pulse,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                  color: SSColors.purple.withValues(
                    alpha: widget.isJoined ? 0.0 : 0.15 + 0.10 * widget.pulse.value,
                  ),
                  blurRadius: 24 + 8 * widget.pulse.value,
                )],
              ),
              child: child,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: SSColors.surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  image: (t.bannerUrl?.isNotEmpty == true)
                      ? DecorationImage(
                          image: NetworkImage(t.bannerUrl!),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            SSColors.background.withValues(alpha: 0.55), BlendMode.darken,
                          ),
                        )
                      : null,
                ),
                child: Stack(children: [
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topRight, end: Alignment.bottomLeft,
                      colors: [
                        SSColors.purpleDim.withValues(alpha: 0.3),
                        SSColors.background.withValues(alpha: 0.9),
                      ],
                    ),
                  ))),
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.isJoined
                          ? SSColors.success.withValues(alpha: 0.4) : SSColors.borderBright,
                      width: widget.isJoined ? 1.5 : 1,
                    ),
                  ))),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        _Badge(label: t.modeDisplay, color: SSColors.purpleDark),
                        const SizedBox(width: 8),
                        _Badge(label: t.startTimeDisplay, color: SSColors.surfaceElevated, textColor: SSColors.gold),
                        const Spacer(),
                        if (widget.isJoined) _SmallJoinedBadge(),
                      ]),
                      const Spacer(),
                      Text(t.title, style: SSTextStyles.displayLarge.copyWith(
                        height: 1.1,
                        shadows: [Shadow(color: SSColors.purple.withValues(alpha: 0.5), blurRadius: 12)],
                      ), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(t.subtitle, style: SSTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        _InfoColumn(label: 'PRIZE POOL', valueWidget: Text(t.prizePoolDisplay, style: SSTextStyles.monoPrize, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 16),
                        _InfoColumn(label: 'ENTRY', valueWidget: Text(t.entryFeeDisplay, style: SSTextStyles.titleMedium.copyWith(color: SSColors.textPrimary), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 16),
                        _InfoColumn(label: 'SLOTS LEFT', valueWidget: Text('${t.slotsLeft}', style: SSTextStyles.titleMedium.copyWith(color: t.isAlmostFull ? SSColors.live : SSColors.textPrimary))),
                        const Spacer(),
                        widget.isJoined
                            ? _SmallJoinedBadge()
                            : _JoinButton(entryFeeDisplay: t.entryFeeDisplay, featured: true, onTap: () => widget.onTap(t)),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// PRIORITY 4: Updated wallet frozen banner — mentions tournament entry too.
class _WalletFrozenBanner extends StatelessWidget {
  final String reason;
  const _WalletFrozenBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFAA22).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFAA22).withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          const Icon(Icons.ac_unit_rounded, color: Color(0xFFFFAA22), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('WALLET FROZEN', style: TextStyle(
              color: Color(0xFFFFAA22), fontSize: 11,
              fontWeight: FontWeight.w800, letterSpacing: 1,
            )),
            Text(
              reason.isNotEmpty
                  ? reason
                  : 'Deposits, withdrawals and tournament entry are disabled.',
              style: const TextStyle(
                color: SSColors.textSecondary, fontSize: 11, height: 1.4,
              ),
            ),
          ])),
        ]),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int tournamentsPlayed, wins;
  final bool loaded;
  const _StatsBar({required this.tournamentsPlayed, required this.wins, required this.loaded});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(child: _StatChip(icon: Icons.emoji_events_rounded, label: 'Tournaments', value: loaded ? '$tournamentsPlayed' : '…', color: SSColors.gold)),
        const SizedBox(width: 10),
        Expanded(child: _StatChip(icon: Icons.military_tech_rounded, label: 'Wins', value: loaded ? '$wins' : '…', color: SSColors.purple)),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _StatChip({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(color: SSColors.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: SSColors.border)),
      child: Row(children: [
        Icon(icon, color: color, size: 15), const SizedBox(width: 5),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: SSTextStyles.titleSmall.copyWith(color: color, fontSize: 13), overflow: TextOverflow.ellipsis),
          Text(label, style: SSTextStyles.labelSmall, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final TournamentStatus status;
  const _StatusPill(this.status);
  @override
  Widget build(BuildContext context) {
    Color color; String label;
    switch (status) {
      case TournamentStatus.live:      color = SSColors.live;      label = '● LIVE';      break;
      case TournamentStatus.completed: color = SSColors.textMuted; label = 'ENDED';       break;
      case TournamentStatus.upcoming:  color = SSColors.gold;      label = 'UPCOMING';    break;
      case TournamentStatus.cancelled: color = SSColors.textMuted; label = 'CANCELLED';   break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5), border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String type;
  const _TypePill(this.type);
  static const _labels = {
    'battle_royale': '🗺️ Battle Royale', 'clash_squad': '⚔️ Clash Squad',
    '2v2': '🤝 2v2 Arena', 'lone_wolf': '🎯 Lone Wolf',
    'lose_to_win': '🔄 Lose To Win', '1v1_arena': '🥊 1v1 Arena',
    'sniper': '🔭 Sniper', 'custom_league': '🏆 League',
  };
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: SSColors.surfaceElevated, borderRadius: BorderRadius.circular(5), border: Border.all(color: SSColors.border)),
      child: Text(_labels[type] ?? type, style: const TextStyle(color: SSColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}

class _TeamPill extends StatelessWidget {
  final String label;
  const _TeamPill(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: SSColors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5), border: Border.all(color: SSColors.purple.withValues(alpha: 0.3))),
      child: Text(label, style: const TextStyle(color: SSColors.purpleLight, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}

class _JoinedPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: SSColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5), border: Border.all(color: SSColors.success.withValues(alpha: 0.35))),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_rounded, color: SSColors.success, size: 9),
        SizedBox(width: 3),
        Text('JOINED', style: TextStyle(color: SSColors.success, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon; final Color color; final String value;
  const _Stat({required this.icon, required this.color, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 12), const SizedBox(width: 4),
      Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _SmallJoinedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: SSColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: SSColors.success.withValues(alpha: 0.35))),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_rounded, color: SSColors.success, size: 11), SizedBox(width: 4),
        Text('JOINED', style: TextStyle(color: SSColors.success, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ]),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label; final Widget valueWidget;
  const _InfoColumn({required this.label, required this.valueWidget});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: SSTextStyles.labelSmall), valueWidget,
    ]);
  }
}

class _JoinButton extends StatefulWidget {
  final String entryFeeDisplay; final bool featured; final VoidCallback? onTap;
  const _JoinButton({required this.entryFeeDisplay, this.featured = false, this.onTap});
  @override State<_JoinButton> createState() => _JoinButtonState();
}
class _JoinButtonState extends State<_JoinButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        padding: EdgeInsets.symmetric(horizontal: widget.featured ? 18 : 14, vertical: widget.featured ? 10 : 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [SSColors.purple, SSColors.purpleDim], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: SSColors.purple.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Text(widget.featured ? 'JOIN NOW' : 'JOIN', style: SSTextStyles.labelLarge.copyWith(color: Colors.white, letterSpacing: 1.2, fontSize: widget.featured ? 13 : 11)),
      )),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label; final Color color; final Color? textColor;
  const _Badge({required this.label, required this.color, this.textColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: SSTextStyles.labelSmall.copyWith(color: textColor ?? SSColors.textSecondary, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
    );
  }
}

class _ShimmerPlaceholder extends StatefulWidget {
  final double height;
  const _ShimmerPlaceholder({required this.height});
  @override State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}
class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true); _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _anim, builder: (_, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(height: widget.height, decoration: BoxDecoration(
        color: SSColors.surfaceCard.withValues(alpha: 0.5 + 0.3 * _anim.value),
        borderRadius: BorderRadius.circular(20), border: Border.all(color: SSColors.border),
      )),
    ));
  }
}

class _ListCardShimmer extends StatefulWidget {
  const _ListCardShimmer();
  @override State<_ListCardShimmer> createState() => _ListCardShimmerState();
}
class _ListCardShimmerState extends State<_ListCardShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true); _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _anim, builder: (_, _) => Container(
      height: 120, margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      decoration: BoxDecoration(
        color: SSColors.surfaceCard.withValues(alpha: 0.5 + 0.3 * _anim.value),
        borderRadius: BorderRadius.circular(16), border: Border.all(color: SSColors.border),
      ),
    ));
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: SSColors.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: SSColors.live.withValues(alpha: 0.3))),
        child: Column(children: [
          const Icon(Icons.error_outline_rounded, color: SSColors.live, size: 32),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: SSColors.textSecondary, fontSize: 13, height: 1.5)),
        ]),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String statusFilter, typeFilter;
  const _EmptyCard({required this.statusFilter, required this.typeFilter});
  @override
  Widget build(BuildContext context) {
    final typeLabel = _filterOptions.firstWhere((o) => o.value == typeFilter, orElse: () => const _FilterOption(value: '', label: 'selected', emoji: '')).label;
    final statusLabel = statusFilter == 'all' ? '' : '$statusFilter ';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(color: SSColors.purpleGlowFaint, shape: BoxShape.circle, border: Border.all(color: SSColors.border)), child: const Icon(Icons.search_off_rounded, color: SSColors.purple, size: 28)),
        const SizedBox(height: 16),
        const Text('No tournaments found', style: TextStyle(color: SSColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(typeFilter == 'all' ? 'No ${statusLabel}tournaments right now.' : 'No $statusLabel$typeLabel tournaments right now.',
            textAlign: TextAlign.center, style: const TextStyle(color: SSColors.textSecondary, fontSize: 13, height: 1.5)),
      ]),
    );
  }
}

class _NavItem {
  final IconData icon; final String label;
  const _NavItem({required this.icon, required this.label});
}