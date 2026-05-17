// lib/screens/home_screen.dart
// ─────────────────────────────────────────────
// HOME SCREEN  (v5)
// Changes from v4:
//   • Fixed black-screen bug: Wallet (3) and Ranks (2) tabs in bottom nav
//     now push screens WITHOUT calling setState on _navIndex, so the index
//     never changes and the home body is never replaced by an empty widget.
//   • Real wallet balance: AppBar balance chip now streams from WalletService
//     instead of showing hardcoded ₹2,450.
//   • Stats bar now streams from Firestore (wins, tournamentsPlayed).
//   • All other behaviour preserved from v4.
// ─────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/wallet_service.dart';
import '../services/tournament_service.dart';
import '../models/tournament_model.dart';
import 'profile_screen.dart';
import 'tournament_details_screen.dart';
import 'all_tournaments_screen.dart';
import '../screens/events_screen.dart';
import '../screens/wallet_screen.dart';
import '../screens/ranks_screen.dart';

// ─────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────
void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF06040E),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const ShadowStormApp());
}

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

  static final displayLarge = _base.copyWith(
      fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5);
  static final titleLarge  = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2);
  static final titleMedium = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.15);
  static final titleSmall  = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1);
  static final bodyMedium  = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: SSColors.textSecondary);
  static final labelLarge  = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: SSColors.textSecondary);
  static final labelSmall  = _base.copyWith(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: SSColors.textMuted);
  static final monoPrize   = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: SSColors.gold);
}

// ─────────────────────────────────────────────
// FILTER TYPES
// ─────────────────────────────────────────────
class _FilterOption {
  final String value, label, emoji;
  const _FilterOption({required this.value, required this.label, required this.emoji});
}

const _filterOptions = [
  _FilterOption(value: 'all',           label: 'All',         emoji: '⚡'),
  _FilterOption(value: 'battle_royale', label: 'Full Map',    emoji: '🗺️'),
  _FilterOption(value: 'clash_squad',   label: 'Clash Squad', emoji: '⚔️'),
  _FilterOption(value: 'lone_wolf',     label: 'Lone Wolf',   emoji: '🎯'),
  _FilterOption(value: 'league',        label: 'League',      emoji: '🏆'),
];

// ─────────────────────────────────────────────
// APP ROOT
// ─────────────────────────────────────────────
class ShadowStormApp extends StatelessWidget {
  const ShadowStormApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shadow Storm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SSColors.background,
        colorScheme: const ColorScheme.dark(
          primary: SSColors.purple,
          secondary: SSColors.purpleLight,
          surface: SSColors.surface,
        ),
        splashColor: SSColors.purpleGlow,
        highlightColor: Colors.transparent,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ── _navIndex is ONLY 0 (Home) or 1 (Events).
  // Ranks (2) and Wallet (3) are pushed screens — their tabs
  // never update _navIndex, so the bottom nav highlight never
  // jumps and the body never renders a blank page.
  int _navIndex = 0;

  final AuthService       _authService       = AuthService();
  final TournamentService _tournamentService = TournamentService.instance;
  final WalletService     _walletService     = WalletService.instance;

  User? get _currentUser => _authService.currentUser;
  String? get _userId    => _currentUser?.uid;

  Set<String> _joinedIds = {};
  StreamSubscription<Set<String>>? _joinedSub;

  String _typeFilter = 'all';

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..forward();
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _pulse  = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

    if (_userId != null) {
      _joinedSub = _tournamentService
          .joinedTournamentIdsStream(_userId!)
          .listen((ids) {
        if (mounted) setState(() => _joinedIds = ids);
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _joinedSub?.cancel();
    super.dispose();
  }

  // ──────────────────────────────────────────
  // NAVIGATION HELPERS
  // ──────────────────────────────────────────

  void _openProfile() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  void _openWallet() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => const WalletScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _openRanks() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => const RanksScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _openTournamentDetails(TournamentModel tournament) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) =>
            TournamentDetailsScreen(tournament: tournament),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _openAllTournaments(
      {String? statusFilter, String? typeFilter, String? title}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => AllTournamentsScreen(
          title:         title ?? 'All Tournaments',
          initialStatus: statusFilter,
          initialType:   typeFilter,
        ),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ──────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SSColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: FadeTransition(opacity: _fadeIn, child: _buildBody()),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ──────────────────────────────────────────
  // APP BAR — balance chip streams real data from Firestore
  // ──────────────────────────────────────────
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
          _GlowContainer(
            glowColor: SSColors.purpleGlow, borderRadius: 12,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: SSColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SSColors.border),
              ),
              child: const Center(
                child: Icon(Icons.bolt_rounded,
                    color: SSColors.purple, size: 22)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SHADOW STORM',
                    style: SSTextStyles.titleSmall.copyWith(
                      color: SSColors.purple, letterSpacing: 1.5, fontSize: 11,
                    )),
                Text(
                  'Welcome, ${_currentUser?.displayName?.split(' ').first ?? 'Striker'}',
                  style: SSTextStyles.bodyMedium.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ── Real-time wallet balance chip ──
          GestureDetector(
            onTap: _openWallet,
            child: _GlowContainer(
              glowColor: SSColors.purpleGlowFaint, borderRadius: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: SSColors.surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SSColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wallet_rounded,
                      color: SSColors.gold, size: 15),
                  const SizedBox(width: 5),
                  // Stream live balance from Firestore
                  StreamBuilder<WalletData>(
                    stream: _walletService.walletDataStream(),
                    builder: (ctx, snap) {
                      final balance =
                          snap.data?.balance ?? 0.0;
                      final loading =
                          snap.connectionState == ConnectionState.waiting;
                      return Text(
                        loading ? '...' : '₹${balance.toStringAsFixed(0)}',
                        style: SSTextStyles.titleSmall
                            .copyWith(color: SSColors.gold, fontSize: 13),
                      );
                    },
                  ),
                ]),
              ),
            ),
          ),

          const SizedBox(width: 10),
          GestureDetector(
            onTap: _openProfile,
            child: _GlowContainer(
              glowColor: SSColors.purpleGlow, borderRadius: 20,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [SSColors.purpleDim, SSColors.purple],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  border:
                      Border.all(color: SSColors.purpleLight, width: 1.5),
                ),
                child: Center(
                  child: _currentUser?.photoURL != null
                      ? ClipOval(
                          child: Image.network(_currentUser!.photoURL!,
                              width: 38, height: 38, fit: BoxFit.cover))
                      : Text(
                          (_currentUser?.displayName?.isNotEmpty == true)
                              ? _currentUser!.displayName![0].toUpperCase()
                              : 'P',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ──────────────────────────────────────────
  // BODY
  // ──────────────────────────────────────────
  Widget _buildBody() {
    if (_navIndex == 1) return const EventsScreen();

    final topPad = MediaQuery.of(context).padding.top + 64 + 12;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: topPad)),
        // Stats bar reads from Firestore
        SliverToBoxAdapter(
            child: _StatsBar(userId: _userId)),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: _FilterChipRow(
            selected: _typeFilter,
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'FEATURED', accent: 'TOURNAMENT',
            onSeeAll: () => _openAllTournaments(
              statusFilter: 'upcoming', title: 'Featured Tournaments',
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: _FeaturedSection(
            stream:    _tournamentService.featuredTournamentStream(),
            pulse:     _pulse,
            joinedIds: _joinedIds,
            onTap:     _openTournamentDetails,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'LIVE', accent: 'NOW', isLive: true,
            onSeeAll: () => _openAllTournaments(
              statusFilter: 'live', title: 'Live Tournaments',
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: _LiveSection(
            stream:     _tournamentService.liveTournamentsStream(),
            pulse:      _pulse,
            joinedIds:  _joinedIds,
            typeFilter: _typeFilter,
            onTap:      _openTournamentDetails,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'UPCOMING', accent: 'TOURNAMENTS',
            onSeeAll: () => _openAllTournaments(
              statusFilter: 'upcoming',
              typeFilter: _typeFilter == 'all' ? null : _typeFilter,
              title: 'Upcoming Tournaments',
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: _UpcomingSection(
            stream:     _tournamentService.upcomingTournamentsStream(),
            joinedIds:  _joinedIds,
            typeFilter: _typeFilter,
            onTap:      _openTournamentDetails,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  // ──────────────────────────────────────────
  // BOTTOM NAV
  // ──────────────────────────────────────────
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
        boxShadow: [
          BoxShadow(
            color: SSColors.purpleGlow.withValues(alpha: 0.3),
            blurRadius: 20, offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List.generate(items.length, (i) {
              // Ranks (2) and Wallet (3) are always pushed, never switch _navIndex.
              // Home (0) and Events (1) switch the body in place.
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
                        color: active
                            ? SSColors.purpleGlowFaint : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(items[i].icon,
                          color: active
                              ? SSColors.purple : SSColors.textMuted,
                          size: 22),
                    ),
                    const SizedBox(height: 2),
                    Text(items[i].label,
                        style: SSTextStyles.labelSmall.copyWith(
                          color: active
                              ? SSColors.purple : SSColors.textMuted,
                          fontWeight: active
                              ? FontWeight.w700 : FontWeight.w400,
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
// STATS BAR — streams wins + tournamentsPlayed from Firestore
// ─────────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final String? userId;
  const _StatsBar({required this.userId});

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Expanded(child: _StatChip(
              icon: Icons.emoji_events_rounded,
              label: 'Tournaments', value: '0', color: SSColors.gold)),
          const SizedBox(width: 10),
          Expanded(child: _StatChip(
              icon: Icons.military_tech_rounded,
              label: 'Wins', value: '0', color: SSColors.purple)),
        ]),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (ctx, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final tournaments =
            (data?['tournamentsPlayed'] ?? 0).toString();
        final wins = (data?['wins'] ?? 0).toString();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(child: _StatChip(
                icon: Icons.emoji_events_rounded,
                label: 'Tournaments',
                value: tournaments,
                color: SSColors.gold)),
            const SizedBox(width: 10),
            Expanded(child: _StatChip(
                icon: Icons.military_tech_rounded,
                label: 'Wins',
                value: wins,
                color: SSColors.purple)),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// FILTER CHIP ROW
// ─────────────────────────────────────────────
class _FilterChipRow extends StatelessWidget {
  final String   selected;
  final void Function(String) onChanged;
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
                  color: active
                      ? SSColors.purple.withValues(alpha: 0.65) : SSColors.border,
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
                Text(opt.label,
                    style: TextStyle(
                      color: active ? SSColors.purpleLight : SSColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    )),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STREAM SECTION WRAPPERS
// ─────────────────────────────────────────────

class _FeaturedSection extends StatelessWidget {
  final Stream<TournamentModel?>       stream;
  final Animation<double>              pulse;
  final Set<String>                    joinedIds;
  final void Function(TournamentModel) onTap;
  const _FeaturedSection({
    required this.stream, required this.pulse,
    required this.joinedIds, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TournamentModel?>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _ShimmerPlaceholder(height: 200);
        }
        if (snap.hasError) {
          return const _ErrorCard(message: 'Could not load featured tournament.');
        }
        if (!snap.hasData || snap.data == null) {
          return const _EmptyCard(message: 'No featured tournament right now.');
        }
        return _FeaturedBanner(
          tournament: snap.data!,
          pulse:      pulse,
          isJoined:   joinedIds.contains(snap.data!.id),
          onTap:      onTap,
        );
      },
    );
  }
}

class _LiveSection extends StatelessWidget {
  final Stream<List<TournamentModel>>  stream;
  final Animation<double>              pulse;
  final Set<String>                    joinedIds;
  final String                         typeFilter;
  final void Function(TournamentModel) onTap;
  const _LiveSection({
    required this.stream, required this.pulse,
    required this.joinedIds, required this.typeFilter, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TournamentModel>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _HorizontalShimmer(height: 200);
        }
        if (snap.hasError) {
          return const _ErrorCard(message: 'Could not load live tournaments.');
        }
        final list = (snap.data ?? []).where((t) {
          if (typeFilter == 'all') return true;
          return t.tournamentType == typeFilter;
        }).toList();
        if (list.isEmpty) {
          return _EmptyCard(
              message: typeFilter == 'all'
                  ? 'No live tournaments right now.'
                  : 'No live ${_filterLabel(typeFilter)} tournaments.');
        }
        return SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => onTap(list[i]),
              child: _LiveTournamentCard(
                tournament: list[i],
                pulse: pulse, index: i,
                isJoined: joinedIds.contains(list[i].id),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UpcomingSection extends StatelessWidget {
  final Stream<List<TournamentModel>>  stream;
  final Set<String>                    joinedIds;
  final String                         typeFilter;
  final void Function(TournamentModel) onTap;
  const _UpcomingSection({
    required this.stream, required this.joinedIds,
    required this.typeFilter, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TournamentModel>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _HorizontalShimmer(height: 220);
        }
        if (snap.hasError) {
          return const _ErrorCard(
              message: 'Could not load upcoming tournaments.');
        }
        final list = (snap.data ?? []).where((t) {
          if (typeFilter == 'all') return true;
          return t.tournamentType == typeFilter;
        }).toList();
        if (list.isEmpty) {
          return _EmptyCard(
              message: typeFilter == 'all'
                  ? 'No upcoming tournaments. Check back soon!'
                  : 'No upcoming ${_filterLabel(typeFilter)} tournaments.');
        }
        return SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => onTap(list[i]),
              child: _UpcomingTournamentCard(
                tournament: list[i],
                index: i,
                isJoined: joinedIds.contains(list[i].id),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _filterLabel(String type) {
  switch (type) {
    case 'battle_royale': return 'Full Map';
    case 'clash_squad':   return 'Clash Squad';
    case 'lone_wolf':     return 'Lone Wolf';
    case 'league':        return 'League';
    default:              return type;
  }
}

// ─────────────────────────────────────────────
// SECTION HEADER
// ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String        title, accent;
  final bool          isLive;
  final VoidCallback? onSeeAll;
  const _SectionHeader({
    required this.title, required this.accent,
    this.isLive = false, this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(
            color: isLive ? SSColors.live : SSColors.purple,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: SSTextStyles.labelLarge
                .copyWith(fontSize: 12, letterSpacing: 1.5)),
        const SizedBox(width: 5),
        Text(accent,
            style: SSTextStyles.labelLarge.copyWith(
              fontSize: 12, letterSpacing: 1.5,
              color: isLive ? SSColors.live : SSColors.purple,
            )),
        if (isLive) ...[const SizedBox(width: 8), _LiveDot()],
        const Spacer(),
        GestureDetector(
          onTap: onSeeAll,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('See All',
                  style: SSTextStyles.labelLarge
                      .copyWith(color: SSColors.purple, fontSize: 11)),
              const Icon(Icons.chevron_right_rounded,
                  color: SSColors.purple, size: 16),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// FEATURED BANNER
// ─────────────────────────────────────────────
class _FeaturedBanner extends StatefulWidget {
  final TournamentModel               tournament;
  final Animation<double>             pulse;
  final bool                          isJoined;
  final void Function(TournamentModel) onTap;
  const _FeaturedBanner({
    required this.tournament, required this.pulse,
    required this.isJoined, required this.onTap,
  });

  @override
  State<_FeaturedBanner> createState() => _FeaturedBannerState();
}

class _FeaturedBannerState extends State<_FeaturedBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
  }
  @override
  void dispose() { _hoverCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => widget.onTap(t),
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
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
                    alpha: widget.isJoined
                        ? 0.0 : 0.15 + 0.12 * widget.pulse.value,
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
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  image: (t.bannerUrl != null && t.bannerUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(t.bannerUrl!),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            SSColors.background.withValues(alpha: 0.55),
                            BlendMode.darken,
                          ),
                        )
                      : null,
                ),
                child: Stack(children: [
                  if (t.bannerUrl == null || t.bannerUrl!.isEmpty)
                    Positioned.fill(child: CustomPaint(
                      painter: _GeometricPainter(
                          color: SSColors.purple.withValues(alpha: 0.04)),
                    )),
                  Positioned.fill(child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          SSColors.purpleDim.withValues(alpha: 0.3),
                          SSColors.background.withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                  )),
                  Positioned.fill(child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.isJoined
                            ? SSColors.success.withValues(alpha: 0.4)
                            : SSColors.borderBright,
                        width: widget.isJoined ? 1.5 : 1,
                      ),
                    ),
                  )),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Flexible(child: _Badge(
                            label: t.modeDisplay,
                            color: SSColors.purpleDim)),
                        const SizedBox(width: 8),
                        Flexible(child: _Badge(
                          label: t.startTimeDisplay,
                          color: SSColors.surfaceElevated,
                          textColor: SSColors.gold,
                        )),
                        const Spacer(),
                        if (widget.isJoined)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: SSColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: SSColors.success.withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Icon(Icons.check_circle_rounded,
                                  color: SSColors.success, size: 10),
                              SizedBox(width: 4),
                              Text('JOINED',
                                  style: TextStyle(
                                    color: SSColors.success, fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  )),
                            ]),
                          ),
                      ]),
                      const Spacer(),
                      Text(t.title,
                          style: SSTextStyles.displayLarge.copyWith(
                            height: 1.1,
                            shadows: [Shadow(
                              color: SSColors.purple.withValues(alpha: 0.5),
                              blurRadius: 12,
                            )],
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(t.subtitle,
                          style: SSTextStyles.bodyMedium,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        _InfoColumn(
                            label: 'PRIZE POOL',
                            valueWidget: Text(t.prizePoolDisplay,
                                style: SSTextStyles.monoPrize,
                                overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 16),
                        _InfoColumn(
                            label: 'ENTRY',
                            valueWidget: Text(t.entryFeeDisplay,
                                style: SSTextStyles.titleMedium.copyWith(
                                    color: SSColors.textPrimary),
                                overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 16),
                        _InfoColumn(
                            label: 'SLOTS LEFT',
                            valueWidget: Text('${t.slotsLeft}',
                                style: SSTextStyles.titleMedium.copyWith(
                                    color: t.isAlmostFull
                                        ? SSColors.live : SSColors.textPrimary))),
                        const Spacer(),
                        widget.isJoined
                            ? _FeaturedJoinedBadge()
                            : _JoinButton(
                                entryFeeDisplay: t.entryFeeDisplay,
                                featured: true,
                                onTap: () => widget.onTap(t),
                              ),
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

class _FeaturedJoinedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SSColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SSColors.success.withValues(alpha: 0.4)),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_rounded, color: SSColors.success, size: 13),
        SizedBox(width: 4),
        Text('JOINED', style: TextStyle(
          color: SSColors.success, fontSize: 12,
          fontWeight: FontWeight.w800, letterSpacing: 1,
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// UPCOMING TOURNAMENT CARD
// ─────────────────────────────────────────────
class _UpcomingTournamentCard extends StatefulWidget {
  final TournamentModel tournament;
  final int             index;
  final bool            isJoined;
  const _UpcomingTournamentCard({
    required this.tournament, required this.index, required this.isJoined,
  });

  @override
  State<_UpcomingTournamentCard> createState() =>
      _UpcomingTournamentCardState();
}

class _UpcomingTournamentCardState extends State<_UpcomingTournamentCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(
        Duration(milliseconds: 100 + widget.index * 100), () {
      if (mounted) _ctrl.forward();
    });
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t          = widget.tournament;
    final almostFull = t.isAlmostFull;
    return ScaleTransition(
      scale: _anim,
      child: SizedBox(
        width: 190,
        child: Container(
          decoration: BoxDecoration(
            color: SSColors.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isJoined
                  ? SSColors.success.withValues(alpha: 0.35) : SSColors.border,
              width: widget.isJoined ? 1.5 : 1,
            ),
            boxShadow: [BoxShadow(
              color: widget.isJoined
                  ? SSColors.success.withValues(alpha: 0.06)
                  : SSColors.purple.withValues(alpha: 0.08),
              blurRadius: 16,
            )],
          ),
          child: Stack(children: [
            Positioned(top: -30, right: -30, child: Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (widget.isJoined ? SSColors.success : SSColors.purple)
                    .withValues(alpha: 0.04),
              ),
            )),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Flexible(child: _Badge(
                    label: t.mode,
                    color: SSColors.purpleDark,
                    textColor: SSColors.purpleLight,
                  )),
                  if (almostFull && !widget.isJoined) ...[
                    const SizedBox(width: 4),
                    _Badge(
                        label: 'HOT',
                        color: SSColors.live.withValues(alpha: 0.2),
                        textColor: SSColors.live),
                  ],
                  if (widget.isJoined) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: SSColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: SSColors.success.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_rounded,
                            color: SSColors.success, size: 8),
                        SizedBox(width: 3),
                        Text('IN', style: TextStyle(
                          color: SSColors.success, fontSize: 8,
                          fontWeight: FontWeight.w800,
                        )),
                      ]),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                Text(t.title,
                    style: SSTextStyles.titleMedium
                        .copyWith(fontSize: 16, height: 1.15),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(t.subtitle,
                    style: SSTextStyles.bodyMedium.copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
                const Spacer(),
                Row(children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: SSColors.gold, size: 13),
                  const SizedBox(width: 4),
                  Expanded(child: Text(t.prizePoolDisplay,
                      style: SSTextStyles.titleSmall
                          .copyWith(color: SSColors.gold, fontSize: 13),
                      overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 8),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Text('${t.slotsLeft} left',
                      style: SSTextStyles.labelSmall.copyWith(
                        color: almostFull
                            ? SSColors.live : SSColors.textMuted)),
                  Flexible(child: Text(t.startTimeDisplay,
                      style: SSTextStyles.labelSmall,
                      overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: t.fillPercent, minHeight: 3,
                    backgroundColor: SSColors.surfaceElevated,
                    valueColor: AlwaysStoppedAnimation(
                        almostFull ? SSColors.live : SSColors.purple),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ENTRY', style: SSTextStyles.labelSmall),
                    Text(t.entryFeeDisplay, style: SSTextStyles.titleSmall),
                  ]),
                  const Spacer(),
                  widget.isJoined
                      ? _SmallJoinedBadge()
                      : _JoinButton(entryFeeDisplay: t.entryFeeDisplay),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// LIVE TOURNAMENT CARD
// ─────────────────────────────────────────────
class _LiveTournamentCard extends StatelessWidget {
  final TournamentModel   tournament;
  final Animation<double> pulse;
  final int               index;
  final bool              isJoined;
  const _LiveTournamentCard({
    required this.tournament, required this.pulse,
    required this.index, required this.isJoined,
  });

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) => Container(
        width: 260,
        decoration: BoxDecoration(
          color: SSColors.surfaceCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isJoined
                ? SSColors.success.withValues(alpha: 0.4)
                : SSColors.live.withValues(alpha: 0.3 + 0.2 * pulse.value),
            width: isJoined ? 1.5 : 1,
          ),
          boxShadow: [BoxShadow(
            color: isJoined
                ? SSColors.success.withValues(alpha: 0.05)
                : SSColors.live.withValues(alpha: 0.07 + 0.05 * pulse.value),
            blurRadius: 16,
          )],
        ),
        child: child,
      ),
      child: Stack(children: [
        Positioned.fill(child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CustomPaint(painter: _GeometricPainter(
              color: SSColors.live.withValues(alpha: 0.03))),
        )),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SSColors.live.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: SSColors.live.withValues(alpha: 0.4), width: 0.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _LiveDot(),
                  const SizedBox(width: 5),
                  Text('LIVE',
                      style: SSTextStyles.labelSmall.copyWith(
                        color: SSColors.live, fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      )),
                ]),
              ),
              const Spacer(),
              if (isJoined)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: SSColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: SSColors.success.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                      mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded,
                        color: SSColors.success, size: 10),
                    SizedBox(width: 3),
                    Text('JOINED', style: TextStyle(
                      color: SSColors.success, fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5,
                    )),
                  ]),
                )
              else
                Flexible(child: Text(t.mode,
                    style: SSTextStyles.labelSmall,
                    overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 10),
            Text(t.title,
                style: SSTextStyles.titleLarge.copyWith(fontSize: 17),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(t.subtitle,
                style: SSTextStyles.bodyMedium.copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis),
            const Spacer(),
            Row(children: [
              Flexible(child: _InfoPill(
                icon: Icons.emoji_events_rounded,
                label: t.prizePoolDisplay, color: SSColors.gold,
              )),
              const SizedBox(width: 8),
              _InfoPill(
                icon: Icons.people_rounded,
                label: '${t.joinedPlayers}/${t.maxPlayers}',
                color: SSColors.textSecondary,
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.visibility_rounded, size: 15),
                label: const Text('WATCH LIVE'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SSColors.live,
                  side: const BorderSide(color: SSColors.live, width: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: SSTextStyles.labelLarge.copyWith(
                      color: SSColors.live, letterSpacing: 1),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// LOADING / EMPTY / ERROR
// ─────────────────────────────────────────────

class _ShimmerPlaceholder extends StatefulWidget {
  final double height;
  const _ShimmerPlaceholder({required this.height});

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: SSColors.surfaceCard
                .withValues(alpha: 0.5 + 0.3 * _anim.value),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SSColors.border),
          ),
        ),
      ),
    );
  }
}

class _HorizontalShimmer extends StatefulWidget {
  final double height;
  const _HorizontalShimmer({required this.height});

  @override
  State<_HorizontalShimmer> createState() => _HorizontalShimmerState();
}

class _HorizontalShimmerState extends State<_HorizontalShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => SizedBox(
        height: widget.height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) => Container(
            width: 200,
            decoration: BoxDecoration(
              color: SSColors.surfaceCard
                  .withValues(alpha: 0.5 + 0.3 * _anim.value),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SSColors.border),
            ),
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SSColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SSColors.live.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: SSColors.live, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: SSTextStyles.bodyMedium.copyWith(fontSize: 12))),
        ]),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SSColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SSColors.border),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded,
              color: SSColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: SSTextStyles.bodyMedium.copyWith(fontSize: 12))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final Color    color;
  const _StatChip({
    required this.icon, required this.label,
    required this.value, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: SSColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SSColors.border),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: SSTextStyles.titleSmall
                    .copyWith(color: color, fontSize: 13),
                overflow: TextOverflow.ellipsis),
            Text(label,
                style: SSTextStyles.labelSmall,
                overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    );
  }
}

class _SmallJoinedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SSColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SSColors.success.withValues(alpha: 0.35)),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_rounded, color: SSColors.success, size: 11),
        SizedBox(width: 4),
        Text('JOINED', style: TextStyle(
          color: SSColors.success, fontSize: 10,
          fontWeight: FontWeight.w800, letterSpacing: 0.5,
        )),
      ]),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SSColors.live.withValues(alpha: 0.5 + 0.5 * _anim.value),
          boxShadow: [BoxShadow(
              color: SSColors.liveGlow, blurRadius: 6 * _anim.value)],
        ),
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final Widget valueWidget;
  const _InfoColumn({required this.label, required this.valueWidget});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: SSTextStyles.labelSmall),
        valueWidget,
      ],
    );
  }
}

class _JoinButton extends StatefulWidget {
  final String        entryFeeDisplay;
  final bool          featured;
  final VoidCallback? onTap;
  const _JoinButton({
    required this.entryFeeDisplay, this.featured = false, this.onTap,
  });

  @override
  State<_JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends State<_JoinButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _ctrl.forward(),
      onTapUp:     (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.featured ? 18 : 14,
            vertical:   widget.featured ? 10 :  8,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [SSColors.purple, SSColors.purpleDim],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(
              color: SSColors.purple.withValues(alpha: 0.4),
              blurRadius: 12, offset: const Offset(0, 4),
            )],
          ),
          child: Text(
            widget.featured ? 'JOIN NOW' : 'JOIN',
            style: SSTextStyles.labelLarge.copyWith(
              color: Colors.white, letterSpacing: 1.2,
              fontSize: widget.featured ? 13 : 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String  label;
  final Color   color;
  final Color?  textColor;
  const _Badge({required this.label, required this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: SSTextStyles.labelSmall.copyWith(
            color: textColor ?? SSColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _InfoPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 12),
      const SizedBox(width: 4),
      Text(label,
          style: SSTextStyles.labelSmall.copyWith(color: color),
          overflow: TextOverflow.ellipsis),
    ]);
  }
}

class _GlowContainer extends StatelessWidget {
  final Widget child;
  final Color  glowColor;
  final double borderRadius;
  const _GlowContainer({
    required this.child, required this.glowColor, required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [BoxShadow(color: glowColor, blurRadius: 10)],
      ),
      child: child,
    );
  }
}

class _GeometricPainter extends CustomPainter {
  final Color color;
  _GeometricPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    const spacing  = 28.0;
    final cols = (size.width  / spacing).ceil() + 2;
    final rows = (size.height / spacing).ceil() + 2;
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        canvas.drawCircle(Offset(c * spacing, r * spacing), 1.2, dotPaint);
      }
    }
    final linePaint = Paint()
      ..color       = color.withValues(alpha: 0.7)
      ..strokeWidth = 0.5;
    for (var i = 0; i < 6; i++) {
      final x = size.width * (0.5 + i * 0.15);
      canvas.drawLine(Offset(x, 0),
          Offset(x - size.height * 0.5, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GeometricPainter old) => old.color != color;
}

class _NavItem {
  final IconData icon;
  final String   label;
  const _NavItem({required this.icon, required this.label});
}