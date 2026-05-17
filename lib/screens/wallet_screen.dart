// lib/screens/wallet_screen.dart
// ─────────────────────────────────────────────
// WALLET SCREEN  — Shadow Storm  (v2)
//
// Layout: Scaffold → Column → [fixed header, fixed balance hero,
//         fixed quick-action grid, Expanded → IndexedStack]
//
// ✅ NO NestedScrollView + SliverPersistentHeader (crash-safe)
// ✅ Firestore paths: users/{uid}/transactions/
//                    users/{uid}/deposit_requests/
//                    users/{uid}/withdraw_requests/
// ✅ Premium animated balance card with particles + shimmer
// ✅ Quick-action navigation: Deposit | Withdraw | History | Support
// ✅ No Firebase Storage / image_picker
// ─────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/wallet_service.dart';

// ── Design tokens (mirror SSColors from home_screen.dart) ──────────────────
class _C {
  static const background      = Color(0xFF06040E);
  static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);

  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  // static const purpleDim       = Color(0xFF7B3FE4);
  // static const purpleDark      = Color(0xFF3C2570);
  static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);

  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);

  static const gold            = Color(0xFFFFCC44);
  static const goldGlow        = Color(0x55FFCC44);
  static const live            = Color(0xFFFF4466);
  static const success         = Color(0xFF44FF99);
  static const discord         = Color(0xFF5865F2);
  static const telegram        = Color(0xFF229ED9);

  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);

  static const pending         = Color(0xFFFFCC44);
  static const approved        = Color(0xFF44FF99);
  static const rejected        = Color(0xFFFF4466);
}

TextStyle _ts({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = _C.textPrimary,
  double letterSpacing = 0,
  double height = 1.4,
}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFamily: 'Roboto',
    );

Color _statusColor(String s) {
  switch (s) {
    case 'approved': return _C.approved;
    case 'rejected': return _C.rejected;
    default:         return _C.pending;
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours  < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays   < 1) return '${diff.inHours}h ago';
  if (diff.inDays   < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

// ─────────────────────────────────────────────
// WALLET SCREEN
// ─────────────────────────────────────────────
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with TickerProviderStateMixin {
  final WalletService _svc = WalletService.instance;

  int _sectionIndex = 0; // 0=Deposit 1=Withdraw 2=History 3=Support

  // Animations
  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _particleCtrl;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;
  late Animation<double>   _particleAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _particleCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();

    _fadeIn       = CurvedAnimation(parent: _fadeCtrl,    curve: Curves.easeOutCubic);
    _pulse        = CurvedAnimation(parent: _pulseCtrl,   curve: Curves.easeInOut);
    _particleAnim = CurvedAnimation(parent: _particleCtrl, curve: Curves.linear);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _C.background,
      body: FadeTransition(
        opacity: _fadeIn,
        child: Column(
          children: [
            SizedBox(height: topPad),
            _buildAppBar(),
            _buildBalanceHero(),
            _buildQuickActions(),
            const SizedBox(height: 4),
            Expanded(
              child: IndexedStack(
                index: _sectionIndex,
                children: [
                  _DepositSection(service: _svc),
                  _WithdrawSection(service: _svc),
                  _HistorySection(service: _svc),
                  _SupportSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── APP BAR ───────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _C.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.border),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _C.textSecondary, size: 16),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _C.purpleGlowFaint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.border),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: _C.purple, size: 17),
        ),
        const SizedBox(width: 10),
        Text('WALLET', style: _ts(
            size: 17, weight: FontWeight.w900,
            letterSpacing: 2, color: _C.textPrimary)),
        const Spacer(),
        // Live indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _C.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _C.success.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _PulseDot(color: _C.success, pulse: _pulse),
            const SizedBox(width: 5),
            Text('LIVE', style: _ts(
                size: 9, weight: FontWeight.w800,
                color: _C.success, letterSpacing: 1)),
          ]),
        ),
      ]),
    );
  }

  // ── ANIMATED BALANCE HERO ─────────────────
  Widget _buildBalanceHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: StreamBuilder<WalletData>(
        stream: _svc.walletDataStream(),
        builder: (ctx, snap) {
          final d       = snap.data ?? WalletData.empty;
          final loading = snap.connectionState == ConnectionState.waiting;
          return AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: _C.purple.withValues(
                        alpha: 0.18 + 0.10 * _pulse.value),
                    blurRadius: 28 + 8 * _pulse.value,
                  ),
                  BoxShadow(
                    color: _C.gold.withValues(alpha: 0.06 + 0.04 * _pulse.value),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: child,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(children: [
                // Background gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E1540), Color(0xFF0D0920), _C.surface],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
                // Particle layer
                SizedBox(
                  height: 140,
                  child: AnimatedBuilder(
                    animation: _particleAnim,
                    builder: (_, _) => CustomPaint(
                      painter: _ParticlePainter(progress: _particleAnim.value),
                      size: Size(
                        MediaQuery.of(ctx).size.width - 32,
                        140,
                      ),
                    ),
                  ),
                ),
                // Holographic shimmer lines
                Positioned.fill(child: CustomPaint(
                  painter: _HoloPainter(),
                )),
                // Bright border
                Positioned.fill(child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _C.borderBright),
                  ),
                )),
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    // Balance
                    Row(children: [
                      const Icon(Icons.account_balance_wallet_rounded,
                          color: _C.purple, size: 16),
                      const SizedBox(width: 7),
                      Text('WALLET BALANCE', style: _ts(
                          size: 10, weight: FontWeight.w700,
                          color: _C.textSecondary, letterSpacing: 1.4)),
                    ]),
                    const SizedBox(height: 10),
                    loading
                        ? _ShimmerBox(width: 180, height: 44)
                        : Text(
                            '₹${d.balance.toStringAsFixed(2)}',
                            style: _ts(
                              size: 38,
                              weight: FontWeight.w900,
                              color: _C.gold,
                              letterSpacing: 0.5,
                            ),
                          ),
                    const SizedBox(height: 4),
                    Text('Available Balance', style: _ts(
                        size: 11, color: _C.textMuted)),
                    const SizedBox(height: 14),
                    // 3 stat chips
                    Row(children: [
                      Expanded(child: _BalanceStat(
                        label: 'WINNINGS',
                        value: loading ? null : d.totalEarnings,
                        color: _C.gold,
                        icon: Icons.emoji_events_rounded,
                      )),
                      Container(width: 1, height: 32, color: _C.border),
                      Expanded(child: _BalanceStat(
                        label: 'DEPOSITED',
                        value: loading ? null : d.totalDeposits,
                        color: _C.success,
                        icon: Icons.add_circle_outline_rounded,
                      )),
                      Container(width: 1, height: 32, color: _C.border),
                      Expanded(child: _BalanceStat(
                        label: 'WITHDRAWN',
                        value: loading ? null : d.totalWithdrawals,
                        color: _C.live,
                        icon: Icons.remove_circle_outline_rounded,
                      )),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── QUICK ACTIONS ─────────────────────────
  static const _actions = [
    (Icons.add_rounded,              'Deposit',  _C.success),
    (Icons.remove_rounded,           'Withdraw', _C.live),
    (Icons.receipt_long_rounded,     'History',  _C.purple),
    (Icons.support_agent_rounded,    'Support',  _C.discord),
  ];

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: List.generate(_actions.length, (i) {
          final (icon, label, color) = _actions[i];
          final active = i == _sectionIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _sectionIndex = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? color.withValues(alpha: 0.14)
                      : _C.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active
                        ? color.withValues(alpha: 0.55) : _C.border,
                    width: active ? 1.5 : 1,
                  ),
                  boxShadow: active
                      ? [BoxShadow(
                          color: color.withValues(alpha: 0.25),
                          blurRadius: 12,
                        )]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        color: active ? color : _C.textMuted, size: 20),
                    const SizedBox(height: 5),
                    Text(label, style: _ts(
                      size: 10, weight: FontWeight.w700,
                      color: active ? color : _C.textMuted,
                      letterSpacing: 0.4,
                    )),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: DEPOSIT
// ═════════════════════════════════════════════
class _DepositSection extends StatefulWidget {
  final WalletService service;
  const _DepositSection({required this.service});
  @override State<_DepositSection> createState() => _DepositSectionState();
}

class _DepositSectionState extends State<_DepositSection> {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _utrCtrl    = TextEditingController();
  bool    _loading = false;
  String? _error;
  bool    _success = false;

  final _quick = [100, 250, 500, 1000, 2500, 5000];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _utrCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _success = false; });
    try {
      await widget.service.submitDepositRequest(
        amount: double.parse(_amountCtrl.text.trim()),
        utr:    _utrCtrl.text.trim(),
      );
      setState(() { _success = true; _loading = false; });
      _amountCtrl.clear();
      _utrCtrl.clear();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $url'), backgroundColor: _C.live),
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _InfoBanner(
            icon: Icons.info_outline_rounded, color: _C.purple,
            text: 'Enter amount + UTR, then send your payment screenshot '
                'to Discord or Telegram for approval (usually within 30 min).',
          ),
          const SizedBox(height: 18),

          _FieldLabel('AMOUNT  (₹)'),
          _StyledField(
            controller: _amountCtrl, hint: 'Enter deposit amount',
            keyboardType: TextInputType.number, prefixText: '₹ ',
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid amount';
              if (n < 50)             return 'Minimum deposit is ₹50';
              return null;
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _quick.map((a) {
              final sel = _amountCtrl.text == a.toString();
              return GestureDetector(
                onTap: () => setState(() => _amountCtrl.text = a.toString()),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? _C.purpleGlowFaint : _C.surfaceCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? _C.purple : _C.border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text('₹$a', style: _ts(
                    size: 12, weight: FontWeight.w700,
                    color: sel ? _C.purpleLight : _C.textSecondary,
                  )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          _FieldLabel('UTR / TRANSACTION ID'),
          _StyledField(
            controller: _utrCtrl, hint: 'Paste your UTR number here',
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'UTR is required';
              if (v.trim().length < 6)           return 'Invalid UTR number';
              return null;
            },
          ),
          const SizedBox(height: 18),

          // UPI card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _C.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _C.gold.withValues(alpha: 0.3)),
              boxShadow: [BoxShadow(color: _C.goldGlow.withValues(alpha: 0.15), blurRadius: 20)],
            ),
            child: Column(children: [
              Text('PAY TO THIS UPI', style: _ts(
                  size: 9, weight: FontWeight.w800,
                  color: _C.textMuted, letterSpacing: 1.4)),
              const SizedBox(height: 14),
              Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text(
                  'QR CODE\nHERE',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                )),
              ),
              const SizedBox(height: 12),
              Text('shadowstorm@upi', style: _ts(
                  size: 15, weight: FontWeight.w800, color: _C.gold)),
              const SizedBox(height: 4),
              Text('Pay and save your UTR number', style: _ts(
                  size: 11, color: _C.textMuted)),
            ]),
          ),
          const SizedBox(height: 18),

          _InfoBanner(
            icon: Icons.photo_camera_rounded, color: _C.gold,
            text: 'After submitting, send your payment screenshot '
                'to our Discord or Telegram support for approval.',
          ),
          const SizedBox(height: 14),

          _FieldLabel('SEND SCREENSHOT FOR APPROVAL'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _SupportButton(
              label: 'Discord', sublabel: '@mastersenpai1  ·  ! SHADOW',
              color: _C.discord, icon: Icons.forum_rounded,
              onTap: () => _launch('https://discord.gg/2eUqD7wtBR'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _SupportButton(
              label: 'Telegram', sublabel: '@Anonymaster_a',
              color: _C.telegram, icon: Icons.send_rounded,
              onTap: () => _launch('https://t.me/Anonymaster_a'),
            )),
          ]),
          const SizedBox(height: 18),

          if (_error   != null) _StatusBanner(text: _error!,   isError: true),
          if (_success)         _StatusBanner(
            text: '✅ Deposit submitted! Now send your payment screenshot '
                  'to Discord or Telegram for approval.',
            isError: false,
          ),
          const SizedBox(height: 4),

          _GlowButton(
            label: _loading ? 'SUBMITTING…' : 'SUBMIT DEPOSIT REQUEST',
            icon: Icons.upload_rounded,
            onTap: _loading ? null : _submit,
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: WITHDRAW
// ═════════════════════════════════════════════
class _WithdrawSection extends StatefulWidget {
  final WalletService service;
  const _WithdrawSection({required this.service});
  @override State<_WithdrawSection> createState() => _WithdrawSectionState();
}

class _WithdrawSectionState extends State<_WithdrawSection> {
  final _formKey     = GlobalKey<FormState>();
  final _amountCtrl  = TextEditingController();
  final _upiCtrl     = TextEditingController();
  final _holderCtrl  = TextEditingController();
  final _bankCtrl    = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl    = TextEditingController();
  String  _method  = 'upi';
  bool    _loading = false;
  String? _error;
  bool    _success = false;

  @override
  void dispose() {
    for (final c in [_amountCtrl, _upiCtrl, _holderCtrl, _bankCtrl, _accountCtrl, _ifscCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _success = false; });
    try {
      await widget.service.submitWithdrawRequest(
        amount:        double.parse(_amountCtrl.text.trim()),
        method:        _method,
        upiId:         _upiCtrl.text.trim(),
        accountHolder: _holderCtrl.text.trim(),
        bankName:      _bankCtrl.text.trim(),
        accountNumber: _accountCtrl.text.trim(),
        ifscCode:      _ifscCtrl.text.trim(),
      );
      setState(() { _success = true; _loading = false; });
      for (final c in [_amountCtrl, _upiCtrl, _holderCtrl, _bankCtrl, _accountCtrl, _ifscCtrl]) {
        c.clear();
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _InfoBanner(
            icon: Icons.schedule_rounded, color: _C.gold,
            text: 'Withdrawals are processed within 24 hours after admin approval.',
          ),
          const SizedBox(height: 18),

          _FieldLabel('WITHDRAW AMOUNT  (₹)'),
          _StyledField(
            controller: _amountCtrl, hint: 'Enter amount',
            keyboardType: TextInputType.number, prefixText: '₹ ',
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid amount';
              if (n < 100)             return 'Minimum withdrawal is ₹100';
              return null;
            },
          ),
          const SizedBox(height: 18),

          _FieldLabel('WITHDRAWAL METHOD'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _MethodToggle(
              label: '📱  UPI', active: _method == 'upi',
              onTap: () => setState(() => _method = 'upi'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _MethodToggle(
              label: '🏦  Bank Transfer', active: _method == 'bank',
              onTap: () => setState(() => _method = 'bank'),
            )),
          ]),
          const SizedBox(height: 18),

          if (_method == 'upi') ...[
            _FieldLabel('UPI ID'),
            _StyledField(
              controller: _upiCtrl, hint: 'yourname@bank',
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'UPI ID is required';
                if (!v.contains('@'))              return 'Invalid UPI ID format';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _FieldLabel('ACCOUNT HOLDER NAME'),
            _StyledField(
              controller: _holderCtrl, hint: 'Full name as registered',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
          ],

          if (_method == 'bank') ...[
            _FieldLabel('ACCOUNT HOLDER NAME'),
            _StyledField(
              controller: _holderCtrl, hint: 'Full name as on bank account',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),
            _FieldLabel('BANK NAME'),
            _StyledField(
              controller: _bankCtrl, hint: 'e.g. State Bank of India',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Bank name is required' : null,
            ),
            const SizedBox(height: 14),
            _FieldLabel('ACCOUNT NUMBER'),
            _StyledField(
              controller: _accountCtrl, hint: 'Enter account number',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Account number is required';
                if (v.trim().length < 8)           return 'Invalid account number';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _FieldLabel('IFSC CODE'),
            _StyledField(
              controller: _ifscCtrl, hint: 'e.g. SBIN0001234',
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'IFSC is required';
                if (v.trim().length != 11)         return 'IFSC must be 11 characters';
                return null;
              },
            ),
          ],

          const SizedBox(height: 18),

          if (_error   != null) _StatusBanner(text: _error!,   isError: true),
          if (_success)         _StatusBanner(
            text: '✅ Withdrawal request submitted! Processing within 24 hours.',
            isError: false,
          ),
          const SizedBox(height: 4),

          _GlowButton(
            label: _loading ? 'SUBMITTING…' : 'SUBMIT WITHDRAWAL',
            icon: Icons.arrow_upward_rounded, color: _C.live,
            onTap: _loading ? null : _submit,
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: HISTORY  (transactions + pending requests)
// ═════════════════════════════════════════════
class _HistorySection extends StatelessWidget {
  final WalletService service;
  const _HistorySection({required this.service});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Pending deposit requests ─────────
        _SectionTitle(
            label: 'PENDING DEPOSITS',
            icon: Icons.add_circle_rounded, color: _C.success),
        const SizedBox(height: 10),
        StreamBuilder<List<DepositRequest>>(
          stream: service.depositRequestsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _InlineLoader();
            }
            final list = (snap.data ?? [])
                .where((r) => r.status == 'pending')
                .toList();
            if (list.isEmpty) {
              return _EmptyInline(message: 'No pending deposits.');
            }
            return Column(
              children: list.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DepositReqCard(req: r),
              )).toList(),
            );
          },
        ),

        const SizedBox(height: 20),

        // ── Pending withdrawal requests ──────
        _SectionTitle(
            label: 'PENDING WITHDRAWALS',
            icon: Icons.remove_circle_rounded, color: _C.live),
        const SizedBox(height: 10),
        StreamBuilder<List<WithdrawRequest>>(
          stream: service.withdrawRequestsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _InlineLoader();
            }
            final list = (snap.data ?? [])
                .where((r) => r.status == 'pending')
                .toList();
            if (list.isEmpty) {
              return _EmptyInline(message: 'No pending withdrawals.');
            }
            return Column(
              children: list.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _WithdrawReqCard(req: r),
              )).toList(),
            );
          },
        ),

        const SizedBox(height: 20),

        // ── Full transaction history ─────────
        _SectionTitle(
            label: 'TRANSACTION HISTORY',
            icon: Icons.receipt_long_rounded, color: _C.purple),
        const SizedBox(height: 10),
        StreamBuilder<List<WalletTransaction>>(
          stream: service.transactionsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _InlineLoader();
            }
            if (snap.hasError) {
              return _EmptyInline(message: 'Could not load transactions.');
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return _EmptyInline(
                  message: 'No transactions yet.\nDeposit funds to get started!');
            }
            return Column(
              children: list.map((tx) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TxCard(tx: tx),
              )).toList(),
            );
          },
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: SUPPORT
// ═════════════════════════════════════════════
class _SupportSection extends StatelessWidget {
  Future<void> _launch(BuildContext ctx, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Could not open: $url'), backgroundColor: _C.live),
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoBanner(
          icon: Icons.support_agent_rounded, color: _C.purple,
          text: 'Need help? Contact our support team on Discord or Telegram. '
              'We usually respond within 30 minutes.',
        ),
        const SizedBox(height: 24),

        _SectionTitle(
            label: 'OFFICIAL SUPPORT CHANNELS',
            icon: Icons.headset_mic_rounded, color: _C.purple),
        const SizedBox(height: 12),

        // Discord card
        _PremiumSupportCard(
          platform: 'DISCORD',
          name: '! SHADOW',
          handle: '@mastersenpai1',
          serverLabel: 'Shadow Storm Community',
          color: _C.discord,
          icon: Icons.forum_rounded,
          badge: 'MAIN SUPPORT',
          onTap: () => _launch(context, 'https://discord.gg/2eUqD7wtBR'),
        ),
        const SizedBox(height: 12),

        // Telegram card
        _PremiumSupportCard(
          platform: 'TELEGRAM',
          name: 'Anonymaster',
          handle: '@Anonymaster_a',
          serverLabel: 'Direct message for fast support',
          color: _C.telegram,
          icon: Icons.send_rounded,
          badge: 'QUICK RESPONSE',
          onTap: () => _launch(context, 'https://t.me/Anonymaster_a'),
        ),
        const SizedBox(height: 24),

        // Common issues section
        _SectionTitle(
            label: 'COMMON ISSUES',
            icon: Icons.help_outline_rounded, color: _C.gold),
        const SizedBox(height: 12),
        ...[
          ('My deposit is pending for too long?',
              'Contact support with your UTR number. Approvals take 30 min.'),
          ('Withdrawal not received?',
              'Withdrawals take up to 24 hours. Contact support with your request ID.'),
          ('Wrong UTR submitted?',
              'Message support immediately on Discord or Telegram with the correct UTR.'),
          ('Balance not updated after winning?',
              'Winnings are credited within 30 minutes of tournament end. Contact support if delayed.'),
        ].map((pair) {
          final (q, a) = pair;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _FaqCard(question: q, answer: a),
          );
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────

class _PremiumSupportCard extends StatefulWidget {
  final String       platform, name, handle, serverLabel, badge;
  final Color        color;
  final IconData     icon;
  final VoidCallback onTap;
  const _PremiumSupportCard({
    required this.platform, required this.name, required this.handle,
    required this.serverLabel, required this.color, required this.icon,
    required this.badge, required this.onTap,
  });
  @override State<_PremiumSupportCard> createState() => _PremiumSupportCardState();
}

class _PremiumSupportCardState extends State<_PremiumSupportCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _ctrl.forward(),
      onTapUp:     (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.color.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(
              color: widget.color.withValues(alpha: 0.18),
              blurRadius: 16, offset: const Offset(0, 4),
            )],
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.color.withValues(alpha: 0.4)),
              ),
              child: Icon(widget.icon, color: widget.color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(widget.platform, style: _ts(
                    size: 13, weight: FontWeight.w900,
                    color: widget.color, letterSpacing: 1,
                  )),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(widget.badge, style: _ts(
                      size: 8, weight: FontWeight.w800,
                      color: widget.color, letterSpacing: 0.8,
                    )),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(widget.name, style: _ts(
                    size: 14, weight: FontWeight.w800, color: _C.textPrimary)),
                Text(widget.handle, style: _ts(
                    size: 11, color: _C.textMuted)),
                const SizedBox(height: 2),
                Text(widget.serverLabel, style: _ts(
                    size: 10, color: _C.textSecondary)),
              ],
            )),
            Icon(Icons.open_in_new_rounded,
                color: widget.color.withValues(alpha: 0.7), size: 18),
          ]),
        ),
      ),
    );
  }
}

class _FaqCard extends StatefulWidget {
  final String question, answer;
  const _FaqCard({required this.question, required this.answer});
  @override State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _open ? _C.purpleGlowFaint : _C.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _open ? _C.purple.withValues(alpha: 0.4) : _C.border,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.question, style: _ts(
                size: 12, weight: FontWeight.w700, color: _C.textPrimary))),
            Icon(
              _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: _C.textMuted, size: 18,
            ),
          ]),
          if (_open) ...[
            const SizedBox(height: 8),
            Text(widget.answer, style: _ts(
                size: 11, color: _C.textSecondary, height: 1.5)),
          ],
        ]),
      ),
    );
  }
}

class _DepositReqCard extends StatelessWidget {
  final DepositRequest req;
  const _DepositReqCard({required this.req});
  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(req.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _C.success.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.add_rounded, color: _C.success, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Deposit Request', style: _ts(
                size: 13, weight: FontWeight.w700)),
            Text('UTR: ${req.utr}', style: _ts(
                size: 11, color: _C.textMuted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${req.amount.toStringAsFixed(2)}', style: _ts(
                size: 15, weight: FontWeight.w900, color: _C.success)),
            const SizedBox(height: 4),
            _StatusPill(status: req.status, color: statusColor),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(_timeAgo(req.createdAt), style: _ts(size: 10, color: _C.textMuted)),
        if (req.adminNote != null) ...[
          const SizedBox(height: 6),
          _InfoBanner(icon: Icons.message_rounded, color: _C.purple,
              text: req.adminNote!),
        ],
      ]),
    );
  }
}

class _WithdrawReqCard extends StatelessWidget {
  final WithdrawRequest req;
  const _WithdrawReqCard({required this.req});
  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(req.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _C.live.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.remove_rounded, color: _C.live, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Withdrawal Request', style: _ts(
                size: 13, weight: FontWeight.w700)),
            Text(
              req.method == 'upi'
                  ? '📱 ${req.upiId}'
                  : '🏦 ${req.accountHolder}',
              style: _ts(size: 11, color: _C.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${req.amount.toStringAsFixed(2)}', style: _ts(
                size: 15, weight: FontWeight.w900, color: _C.live)),
            const SizedBox(height: 4),
            _StatusPill(status: req.status, color: statusColor),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(_timeAgo(req.createdAt), style: _ts(size: 10, color: _C.textMuted)),
        if (req.adminNote != null) ...[
          const SizedBox(height: 6),
          _InfoBanner(icon: Icons.message_rounded, color: _C.purple,
              text: req.adminNote!),
        ],
      ]),
    );
  }
}

class _TxCard extends StatelessWidget {
  final WalletTransaction tx;
  const _TxCard({required this.tx});

  IconData get _icon => switch (tx.type) {
    'deposit'          => Icons.add_circle_rounded,
    'withdrawal'       => Icons.remove_circle_rounded,
    'tournament_entry' => Icons.sports_esports_rounded,
    'winnings'         => Icons.emoji_events_rounded,
    'refund'           => Icons.replay_rounded,
    _                  => Icons.swap_horiz_rounded,
  };

  Color get _color => tx.isCredit ? _C.success : _C.live;

  String get _label => switch (tx.type) {
    'deposit'          => 'Deposit',
    'withdrawal'       => 'Withdrawal',
    'tournament_entry' => 'Tournament Entry',
    'winnings'         => 'Winnings',
    'refund'           => 'Refund',
    _                  => tx.type,
  };

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(tx.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(_icon, color: _color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_label, style: _ts(size: 13, weight: FontWeight.w700)),
            if (tx.description != null) ...[
              const SizedBox(height: 2),
              Text(tx.description!, style: _ts(size: 11, color: _C.textMuted),
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 4),
            Row(children: [
              _StatusPill(status: tx.status, color: statusColor),
              const SizedBox(width: 8),
              Text(_timeAgo(tx.createdAt),
                  style: _ts(size: 10, color: _C.textMuted)),
            ]),
          ],
        )),
        const SizedBox(width: 8),
        Text(
          '${tx.isCredit ? '+' : '-'}₹${tx.amount.toStringAsFixed(2)}',
          style: _ts(size: 14, weight: FontWeight.w900,
              color: tx.isCredit ? _C.success : _C.live),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// REUSABLE ATOMS
// ─────────────────────────────────────────────

class _BalanceStat extends StatelessWidget {
  final String   label;
  final double?  value;
  final Color    color;
  final IconData icon;
  const _BalanceStat({
    required this.label, required this.value,
    required this.color, required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(height: 4),
      value == null
          ? _ShimmerBox(width: 50, height: 14)
          : Text(
              '₹${value!.toStringAsFixed(0)}',
              style: _ts(size: 12, weight: FontWeight.w800, color: color),
              overflow: TextOverflow.ellipsis,
            ),
      const SizedBox(height: 2),
      Text(label, style: _ts(size: 8, weight: FontWeight.w700,
          color: _C.textMuted, letterSpacing: 0.8)),
    ]);
  }
}

class _SupportButton extends StatefulWidget {
  final String label, sublabel;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _SupportButton({
    required this.label, required this.sublabel,
    required this.color, required this.icon, required this.onTap,
  });
  @override State<_SupportButton> createState() => _SupportButtonState();
}

class _SupportButtonState extends State<_SupportButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _ctrl.forward(),
      onTapUp:     (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.color.withValues(alpha: 0.45)),
            boxShadow: [BoxShadow(
              color: widget.color.withValues(alpha: 0.18),
              blurRadius: 12, offset: const Offset(0, 4),
            )],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(widget.icon, color: widget.color, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(widget.label, style: _ts(
                  size: 12, weight: FontWeight.w800, color: widget.color),
                  overflow: TextOverflow.ellipsis)),
              Icon(Icons.open_in_new_rounded,
                  color: widget.color.withValues(alpha: 0.6), size: 13),
            ]),
            const SizedBox(height: 4),
            Text(widget.sublabel, style: _ts(size: 10, color: _C.textMuted),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class _GlowButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _GlowButton({
    required this.label, required this.icon,
    this.color = _C.purple, this.onTap,
  });
  @override State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return GestureDetector(
      onTapDown:   (_) { if (!disabled) _ctrl.forward(); },
      onTapUp:     (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: disabled
                  ? [_C.surfaceElevated, _C.surfaceElevated]
                  : [widget.color, widget.color.withValues(alpha: 0.75)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: disabled ? [] : [BoxShadow(
              color: widget.color.withValues(alpha: 0.4),
              blurRadius: 16, offset: const Offset(0, 4),
            )],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icon,
                color: disabled ? _C.textMuted : Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(widget.label, style: _ts(
              size: 13, weight: FontWeight.w900, letterSpacing: 1.2,
              color: disabled ? _C.textMuted : Colors.white,
            )),
          ]),
        ),
      ),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _MethodToggle({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? _C.purpleGlowFaint : _C.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? _C.purple : _C.border, width: active ? 1.5 : 1),
          boxShadow: active
              ? [BoxShadow(color: _C.purpleGlow.withValues(alpha: 0.4), blurRadius: 10)]
              : [],
        ),
        child: Center(child: Text(label, style: _ts(
          size: 13, weight: FontWeight.w700,
          color: active ? _C.purpleLight : _C.textSecondary,
        ))),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController      controller;
  final String                     hint;
  final TextInputType              keyboardType;
  final String?                    prefixText;
  final List<TextInputFormatter>?  inputFormatters;
  final String? Function(String?)? validator;
  final TextCapitalization         textCapitalization;

  const _StyledField({
    required this.controller, required this.hint,
    this.keyboardType = TextInputType.text, this.prefixText,
    this.inputFormatters, this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType,
      inputFormatters: inputFormatters, validator: validator,
      textCapitalization: textCapitalization,
      style: _ts(size: 14, weight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint, prefixText: prefixText,
        hintStyle: _ts(size: 13, color: _C.textMuted),
        prefixStyle: _ts(size: 14, weight: FontWeight.w700, color: _C.textSecondary),
        filled: true, fillColor: _C.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.purple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.live),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _C.live, width: 1.5),
        ),
        errorStyle: _ts(size: 11, color: _C.live),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: _ts(
          size: 10, weight: FontWeight.w800,
          color: _C.textMuted, letterSpacing: 1.2)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _SectionTitle({required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 3, height: 16,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 6),
      Text(label, style: _ts(
          size: 10, weight: FontWeight.w800,
          color: _C.textSecondary, letterSpacing: 1.5)),
    ]);
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final Color  color;
  const _StatusPill({required this.status, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(status.toUpperCase(), style: _ts(
          size: 9, weight: FontWeight.w800,
          color: color, letterSpacing: 0.8)),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   text;
  const _InfoBanner({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: _ts(size: 12, color: _C.textSecondary))),
      ]),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String text;
  final bool   isError;
  const _StatusBanner({required this.text, required this.isError});
  @override
  Widget build(BuildContext context) {
    final color = isError ? _C.live : _C.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          color: color, size: 17,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: _ts(size: 12, color: _C.textSecondary))),
      ]),
    );
  }
}

class _InlineLoader extends StatelessWidget {
  const _InlineLoader();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: SizedBox(
        width: 24, height: 24,
        child: CircularProgressIndicator(color: _C.purple, strokeWidth: 2),
      )),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  final String message;
  const _EmptyInline({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Text(message, style: _ts(size: 12, color: _C.textMuted),
          textAlign: TextAlign.center),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final Color            color;
  final Animation<double> pulse;
  const _PulseDot({required this.color, required this.pulse});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.5 + 0.5 * pulse.value),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6),
              blurRadius: 5 * pulse.value)],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width, height;
  const _ShimmerBox({required this.width, required this.height});
  @override State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          color: _C.surfaceElevated.withValues(alpha: 0.5 + 0.4 * _anim.value),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CUSTOM PAINTERS
// ─────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final double progress;
  static final _rng = math.Random(42);
  static final _particles = List.generate(22, (i) => [
    _rng.nextDouble(), // x fraction
    _rng.nextDouble(), // y fraction
    _rng.nextDouble() * 3 + 1, // size
    _rng.nextDouble(), // speed offset
  ]);

  const _ParticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t  = (progress + p[3]) % 1.0;
      final x  = p[0] * size.width;
      final y  = (p[1] - t * 0.4) % 1.0 * size.height;
      final r  = p[2];
      final alpha = (math.sin(t * math.pi) * 0.5).clamp(0.0, 0.5);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = const Color(0xFF9D55FF).withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.progress != progress;
}

class _HoloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9D55FF).withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = size.height * i / 7;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final diag = Paint()
      ..color = const Color(0xFFB07EF8).withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    for (var i = 0; i < 6; i++) {
      final x = size.width * (0.5 + i * 0.12);
      canvas.drawLine(
          Offset(x, 0), Offset(x - size.height * 0.6, size.height), diag);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}