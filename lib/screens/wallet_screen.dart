// lib/screens/wallet_screen.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Wallet Screen (Phase F1)
//
// Changes from v3:
//   PRIORITY 3: Scaffold wrapped with MaintenanceGuard.
//
//   PRIORITY 4: walletFrozen fully enforced:
//     • Deposit section: disabled with freeze notice when walletFrozen=true.
//     • Withdraw section: disabled with freeze notice when walletFrozen=true.
//     • Both sections read freeze reason from AppSettingsService stream.
//     • Player can still browse History and Support tabs when frozen.
//
//   All original v3 widgets, UPI QR, form logic, history, support intact.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/wallet_service.dart';
import '../services/app_settings_service.dart';

// ── Design tokens ───────────────────────────────────────────────────────────
class _C {
  static const background      = Color(0xFF06040E);
  static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);
  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);
  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);
  static const gold            = Color(0xFFFFCC44);
  static const goldGlow        = Color(0x55FFCC44);
  static const live            = Color(0xFFFF4466);
  static const liveGlow        = Color(0x55FF4466);
  static const success         = Color(0xFF44FF99);
  static const discord         = Color(0xFF5865F2);
  static const telegram        = Color(0xFF229ED9);
  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
  static const pending         = Color(0xFFFFCC44);
  static const approved        = Color(0xFF44FF99);
  static const rejected        = Color(0xFFFF4466);
  static const frozen          = Color(0xFFFFAA22);
}

TextStyle _ts({double size = 14, FontWeight weight = FontWeight.w400, Color color = _C.textPrimary, double letterSpacing = 0, double height = 1.4}) =>
    TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: height, fontFamily: 'Roboto');

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
  @override State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with TickerProviderStateMixin {
  final WalletService _svc = WalletService.instance;

  int _sectionIndex = 0;

  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _pulse  = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // BUILD
  // PRIORITY 3: Scaffold wrapped with MaintenanceGuard.
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return MaintenanceGuard(
      child: Scaffold(
        backgroundColor: _C.background,
        body: FadeTransition(
          opacity: _fadeIn,
          child: StreamBuilder<AppSettings>(
            stream: AppSettingsService.instance.settingsStream,
            builder: (context, settingsSnap) {
              final settings = settingsSnap.data ?? const AppSettings();
              return Column(children: [
                SizedBox(height: topPad),
                _buildAppBar(),
                _buildBalanceHero(),
                _buildApprovalNotice(),
                // PRIORITY 4: Show freeze banner when wallet is frozen.
                if (settings.walletFrozen) _buildWalletFrozenBanner(settings.walletFreezeReason),
                _buildQuickActions(),
                const SizedBox(height: 4),
                Expanded(
                  child: IndexedStack(
                    index: _sectionIndex,
                    children: [
                      // PRIORITY 4: Pass frozen state to deposit/withdraw sections.
                      _DepositSection(service: _svc, frozen: settings.walletFrozen, freezeReason: settings.walletFreezeReason),
                      _WithdrawSection(service: _svc, frozen: settings.walletFrozen, freezeReason: settings.walletFreezeReason),
                      _HistorySection(service: _svc),
                      _SupportSection(),
                    ],
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  // PRIORITY 4: Wallet frozen banner inside wallet screen.
  Widget _buildWalletFrozenBanner(String reason) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _C.frozen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.frozen.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.ac_unit_rounded, color: _C.frozen, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('WALLET FROZEN', style: TextStyle(color: _C.frozen, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          Text(
            reason.isNotEmpty ? reason : 'Deposits and withdrawals are temporarily disabled.',
            style: const TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.4),
          ),
        ])),
      ]),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _C.textSecondary, size: 16),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
          child: const Icon(Icons.account_balance_wallet_rounded, color: _C.purple, size: 17),
        ),
        const SizedBox(width: 10),
        Text('WALLET', style: _ts(size: 17, weight: FontWeight.w900, letterSpacing: 2)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: _C.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.success.withValues(alpha: 0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _PulseDot(color: _C.success, pulse: _pulse), const SizedBox(width: 5),
            Text('LIVE', style: _ts(size: 9, weight: FontWeight.w800, color: _C.success, letterSpacing: 1)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildApprovalNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_C.gold.withValues(alpha: 0.10), _C.purple.withValues(alpha: 0.07)], begin: Alignment.centerLeft, end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.gold.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.schedule_rounded, color: _C.gold, size: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text('Deposit & withdrawal approvals are processed daily between 8 PM and 8 AM.', style: _ts(size: 11, color: _C.textSecondary, height: 1.4))),
        ]),
      ),
    );
  }

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
                boxShadow: [BoxShadow(color: _C.purple.withValues(alpha: 0.18 + 0.10 * _pulse.value), blurRadius: 28 + 8 * _pulse.value)],
              ),
              child: child,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(children: [
                Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1540), Color(0xFF0D0920), _C.surface], stops: [0.0, 0.55, 1.0]))),
                Positioned.fill(child: CustomPaint(painter: _HoloPainter())),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: _C.borderBright)))),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Row(children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: _C.purple, size: 16), const SizedBox(width: 7),
                      Text('WALLET BALANCE', style: _ts(size: 10, weight: FontWeight.w700, color: _C.textSecondary, letterSpacing: 1.4)),
                    ]),
                    const SizedBox(height: 10),
                    loading ? _ShimmerBox(width: 180, height: 44) : Text('₹${d.balance.toStringAsFixed(2)}', style: _ts(size: 38, weight: FontWeight.w900, color: _C.gold, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text('Available Balance', style: _ts(size: 11, color: _C.textMuted)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _BalanceStat(label: 'WINNINGS', value: loading ? null : d.totalEarnings, color: _C.gold, icon: Icons.emoji_events_rounded)),
                      Container(width: 1, height: 32, color: _C.border),
                      Expanded(child: _BalanceStat(label: 'DEPOSITED', value: loading ? null : d.totalDeposits, color: _C.success, icon: Icons.add_circle_outline_rounded)),
                      Container(width: 1, height: 32, color: _C.border),
                      Expanded(child: _BalanceStat(label: 'WITHDRAWN', value: loading ? null : d.totalWithdrawals, color: _C.live, icon: Icons.remove_circle_outline_rounded)),
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

  static const _actions = [
    (Icons.add_rounded,           'Deposit',  _C.success),
    (Icons.remove_rounded,        'Withdraw', _C.live),
    (Icons.receipt_long_rounded,  'History',  _C.purple),
    (Icons.support_agent_rounded, 'Support',  _C.discord),
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
                  color: active ? color.withValues(alpha: 0.14) : _C.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: active ? color.withValues(alpha: 0.55) : _C.border, width: active ? 1.5 : 1),
                  boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12)] : null,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: active ? color : _C.textMuted, size: 20),
                  const SizedBox(height: 5),
                  Text(label, style: _ts(size: 10, weight: FontWeight.w700, color: active ? color : _C.textMuted, letterSpacing: 0.4)),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WALLET FROZEN NOTICE WIDGET (reusable inside sections)
// ─────────────────────────────────────────────
class _FrozenNotice extends StatelessWidget {
  final String reason;
  const _FrozenNotice({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.frozen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.frozen.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [BoxShadow(color: _C.frozen.withValues(alpha: 0.15), blurRadius: 16)],
      ),
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _C.frozen.withValues(alpha: 0.12), border: Border.all(color: _C.frozen.withValues(alpha: 0.3))),
          child: const Icon(Icons.ac_unit_rounded, color: _C.frozen, size: 28),
        ),
        const SizedBox(height: 14),
        const Text('WALLET FROZEN', style: TextStyle(color: _C.frozen, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Text(
          reason.isNotEmpty ? reason : 'Wallet operations are temporarily suspended by the admin.',
          style: const TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
          child: const Text('You can browse the app freely.\nDeposits and withdrawals are disabled until the freeze is lifted.', style: TextStyle(color: _C.textMuted, fontSize: 11, height: 1.5), textAlign: TextAlign.center),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: DEPOSIT
// PRIORITY 4: frozen=true disables the entire form and shows freeze notice.
// ═════════════════════════════════════════════
class _DepositSection extends StatefulWidget {
  final WalletService service;
  final bool frozen;
  final String freezeReason;
  const _DepositSection({required this.service, required this.frozen, required this.freezeReason});
  @override State<_DepositSection> createState() => _DepositSectionState();
}

class _DepositSectionState extends State<_DepositSection> {
  final _formKey     = GlobalKey<FormState>();
  final _amountCtrl  = TextEditingController();
  final _utrCtrl     = TextEditingController();
  bool    _loading      = false;
  String? _error;
  bool    _success      = false;
  bool    _paymentDone  = false;
  String  _upiLink      = '';

  final _quick = [100, 250, 500, 1000, 2500, 5000];

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    setState(() {
      _upiLink = (amount != null && amount >= 50) ? buildUpiDeepLink(amount) : '';
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _utrCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchUpi() async {
    if (_upiLink.isEmpty) return;
    final uri      = Uri.parse(_upiLink);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No UPI app found. Please install GPay, PhonePe or Paytm.'), backgroundColor: _C.live));
    } else {
      setState(() => _paymentDone = true);
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: $url'), backgroundColor: _C.live));
    }
  }

  Future<void> _submit() async {
    if (widget.frozen) return; // PRIORITY 4: guard
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _success = false; });
    try {
      await widget.service.submitDepositRequest(amount: double.parse(_amountCtrl.text.trim()), utr: _utrCtrl.text.trim());
      setState(() { _success = true; _loading = false; _paymentDone = false; });
      _amountCtrl.clear();
      _utrCtrl.clear();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // PRIORITY 4: Show freeze notice instead of form when frozen.
    if (widget.frozen) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: _FrozenNotice(reason: widget.freezeReason),
      );
    }

    final amount    = double.tryParse(_amountCtrl.text.trim());
    final hasAmount = amount != null && amount >= 50;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepBadge(number: '1', label: 'ENTER DEPOSIT AMOUNT'),
          const SizedBox(height: 10),
          _StyledField(
            controller: _amountCtrl, hint: 'Enter deposit amount',
            keyboardType: TextInputType.number, prefixText: '₹ ',
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid amount';
              if (n < 50) return 'Minimum deposit is ₹50';
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
                    border: Border.all(color: sel ? _C.purple : _C.border, width: sel ? 1.5 : 1),
                  ),
                  child: Text('₹$a', style: _ts(size: 12, weight: FontWeight.w700, color: sel ? _C.purpleLight : _C.textSecondary)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          _StepBadge(number: '2', label: 'SCAN QR OR PAY WITH UPI APP'),
          const SizedBox(height: 10),
          _UpiPayCard(upiLink: _upiLink, hasAmount: hasAmount, amount: amount, onPayTap: _launchUpi),
          const SizedBox(height: 22),
          AnimatedOpacity(
            opacity: _paymentDone ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 300),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StepBadge(number: '3', label: 'ENTER YOUR UTR NUMBER'),
              const SizedBox(height: 10),
              _paymentDone
                  ? _InfoBanner(icon: Icons.check_circle_outline_rounded, color: _C.success, text: 'Great! Payment initiated. Now enter your UTR / Transaction ID from your UPI app to complete the request.')
                  : _InfoBanner(icon: Icons.info_outline_rounded, color: _C.purple, text: 'Complete the UPI payment above first, then enter your UTR number here to submit your deposit request.'),
              const SizedBox(height: 12),
              _StyledField(
                controller: _utrCtrl, hint: 'Paste your UTR / Transaction ID',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'UTR is required';
                  if (v.trim().length < 6) return 'Invalid UTR number';
                  return null;
                },
              ),
            ]),
          ),
          const SizedBox(height: 18),
          _FieldLabel('SEND PAYMENT SCREENSHOT FOR FASTER APPROVAL'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _SupportButton(label: 'Discord', sublabel: '@mastersenpai1  ·  ! SHADOW', color: _C.discord, icon: Icons.forum_rounded, onTap: () => _launch('https://discord.gg/2eUqD7wtBR'))),
            const SizedBox(width: 10),
            Expanded(child: _SupportButton(label: 'Telegram', sublabel: '@Anonymaster_a', color: _C.telegram, icon: Icons.send_rounded, onTap: () => _launch('https://t.me/Anonymaster_a'))),
          ]),
          const SizedBox(height: 18),
          if (_error   != null) _StatusBanner(text: _error!, isError: true),
          if (_success)         _StatusBanner(text: '✅ Deposit request submitted! Your request is now pending admin approval. Approvals happen daily 8 PM – 8 AM.', isError: false),
          const SizedBox(height: 4),
          _GlowButton(label: _loading ? 'SUBMITTING…' : 'SUBMIT DEPOSIT REQUEST', icon: Icons.upload_rounded, onTap: _loading ? null : _submit),
        ]),
      ),
    );
  }
}

// ─── UPI Pay Card (unchanged from v3) ──────────────────────────────────────
class _UpiPayCard extends StatelessWidget {
  final String upiLink; final bool hasAmount; final double? amount; final VoidCallback onPayTap;
  const _UpiPayCard({required this.upiLink, required this.hasAmount, required this.amount, required this.onPayTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _C.surfaceCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.gold.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: _C.goldGlow.withValues(alpha: 0.15), blurRadius: 20)],
      ),
      child: Column(children: [
        Text('PAY TO THIS UPI', style: _ts(size: 9, weight: FontWeight.w800, color: _C.textMuted, letterSpacing: 1.4)),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: hasAmount && upiLink.isNotEmpty
              ? Container(
                  key: ValueKey(upiLink),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: _C.gold.withValues(alpha: 0.25), blurRadius: 16)]),
                  child: QrImageView(data: upiLink, version: QrVersions.auto, size: 160, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                )
              : Container(
                  key: const ValueKey('placeholder'),
                  width: 160, height: 160,
                  decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border.withValues(alpha: 0.5))),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.qr_code_2_rounded, color: _C.textMuted, size: 48),
                    const SizedBox(height: 8),
                    Text('Enter amount\nto generate QR', style: _ts(size: 11, color: _C.textMuted, height: 1.5), textAlign: TextAlign.center),
                  ]),
                ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.gold.withValues(alpha: 0.25))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_rounded, color: _C.gold, size: 15), const SizedBox(width: 8),
            Text(upiId, style: _ts(size: 14, weight: FontWeight.w900, color: _C.gold)),
          ]),
        ),
        if (amount != null && amount! > 0) ...[
          const SizedBox(height: 6),
          Text('Amount: ₹${amount!.toStringAsFixed(2)}', style: _ts(size: 12, color: _C.textSecondary, weight: FontWeight.w600)),
        ],
        const SizedBox(height: 16),
        GestureDetector(
          onTap: hasAmount ? onPayTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: hasAmount
                  ? const LinearGradient(colors: [Color(0xFF9D55FF), Color(0xFF5865F2)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : LinearGradient(colors: [_C.surfaceElevated, _C.surfaceElevated]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: hasAmount ? [BoxShadow(color: _C.purple.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))] : [],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.payment_rounded, color: hasAmount ? Colors.white : _C.textMuted, size: 18), const SizedBox(width: 8),
              Text('PAY WITH UPI', style: _ts(size: 13, weight: FontWeight.w900, letterSpacing: 1.2, color: hasAmount ? Colors.white : _C.textMuted)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 6, alignment: WrapAlignment.center,
          children: ['GPay', 'PhonePe', 'Paytm', 'BHIM'].map((app) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.border)),
              child: Text(app, style: _ts(size: 10, color: _C.textSecondary, weight: FontWeight.w600)),
            ),
          ).toList(),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: WITHDRAW
// PRIORITY 4: frozen=true disables the entire form.
// ═════════════════════════════════════════════
class _WithdrawSection extends StatefulWidget {
  final WalletService service;
  final bool frozen;
  final String freezeReason;
  const _WithdrawSection({required this.service, required this.frozen, required this.freezeReason});
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
  double  _liveBalance = 0.0;

  @override
  void initState() { super.initState(); _amountCtrl.addListener(() => setState(() {})); }
  @override
  void dispose() {
    for (final c in [_amountCtrl, _upiCtrl, _holderCtrl, _bankCtrl, _accountCtrl, _ifscCtrl]) c.dispose();
    super.dispose();
  }

  double get _enteredAmount => double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
  bool get _exceedsBalance => _enteredAmount > 0 && _enteredAmount > _liveBalance;

  Future<void> _submit() async {
    if (widget.frozen) return; // PRIORITY 4: guard
    if (!_formKey.currentState!.validate()) return;
    if (_exceedsBalance) return;
    setState(() { _loading = true; _error = null; _success = false; });
    try {
      await widget.service.submitWithdrawRequest(
        amount: _enteredAmount, method: _method,
        upiId: _upiCtrl.text.trim(), accountHolder: _holderCtrl.text.trim(),
        bankName: _bankCtrl.text.trim(), accountNumber: _accountCtrl.text.trim(),
        ifscCode: _ifscCtrl.text.trim(),
      );
      setState(() { _success = true; _loading = false; });
      for (final c in [_amountCtrl, _upiCtrl, _holderCtrl, _bankCtrl, _accountCtrl, _ifscCtrl]) c.clear();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // PRIORITY 4: Show freeze notice when frozen.
    if (widget.frozen) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: _FrozenNotice(reason: widget.freezeReason),
      );
    }

    return StreamBuilder<WalletData>(
      stream: widget.service.walletDataStream(),
      builder: (ctx, snap) {
        final walletData = snap.data ?? WalletData.empty;
        _liveBalance = walletData.balance;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _LiveBalanceChip(balance: _liveBalance),
              const SizedBox(height: 16),
              _InfoBanner(icon: Icons.schedule_rounded, color: _C.gold, text: 'Withdrawals are processed within 24 hours after admin approval. Approvals happen daily 8 PM – 8 AM.'),
              const SizedBox(height: 18),
              _FieldLabel('WITHDRAW AMOUNT  (₹)'),
              _StyledField(
                controller: _amountCtrl, hint: 'Enter amount',
                keyboardType: TextInputType.number, prefixText: '₹ ',
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  if (n < 100) return 'Minimum withdrawal is ₹100';
                  if (n > _liveBalance) return 'Amount exceeds your available balance (₹${_liveBalance.toStringAsFixed(2)})';
                  return null;
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _exceedsBalance
                    ? _InsufficientBalanceCard(key: const ValueKey('warn'), available: _liveBalance, requested: _enteredAmount)
                    : const SizedBox(key: ValueKey('none')),
              ),
              const SizedBox(height: 18),
              _FieldLabel('WITHDRAWAL METHOD'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _MethodToggle(label: '📱  UPI', active: _method == 'upi', onTap: () => setState(() => _method = 'upi'))),
                const SizedBox(width: 10),
                Expanded(child: _MethodToggle(label: '🏦  Bank Transfer', active: _method == 'bank', onTap: () => setState(() => _method = 'bank'))),
              ]),
              const SizedBox(height: 18),
              if (_method == 'upi') ...[
                _FieldLabel('UPI ID'),
                _StyledField(controller: _upiCtrl, hint: 'yourname@bank', validator: (v) { if (v == null || v.trim().isEmpty) return 'UPI ID is required'; if (!v.contains('@')) return 'Invalid UPI ID format'; return null; }),
                const SizedBox(height: 14),
                _FieldLabel('ACCOUNT HOLDER NAME'),
                _StyledField(controller: _holderCtrl, hint: 'Full name as registered', validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
              ],
              if (_method == 'bank') ...[
                _FieldLabel('ACCOUNT HOLDER NAME'),
                _StyledField(controller: _holderCtrl, hint: 'Full name as on bank account', validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
                const SizedBox(height: 14),
                _FieldLabel('BANK NAME'),
                _StyledField(controller: _bankCtrl, hint: 'e.g. State Bank of India', validator: (v) => (v == null || v.trim().isEmpty) ? 'Bank name is required' : null),
                const SizedBox(height: 14),
                _FieldLabel('ACCOUNT NUMBER'),
                _StyledField(controller: _accountCtrl, hint: 'Enter account number', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], validator: (v) { if (v == null || v.trim().isEmpty) return 'Account number is required'; if (v.trim().length < 8) return 'Invalid account number'; return null; }),
                const SizedBox(height: 14),
                _FieldLabel('IFSC CODE'),
                _StyledField(controller: _ifscCtrl, hint: 'e.g. SBIN0001234', textCapitalization: TextCapitalization.characters, validator: (v) { if (v == null || v.trim().isEmpty) return 'IFSC is required'; if (v.trim().length != 11) return 'IFSC must be 11 characters'; return null; }),
              ],
              const SizedBox(height: 18),
              if (_error   != null) _StatusBanner(text: _error!, isError: true),
              if (_success)         _StatusBanner(text: '✅ Withdrawal request submitted! Processing within 24 hours after admin approval.', isError: false),
              const SizedBox(height: 4),
              _GlowButton(
                label: _loading ? 'SUBMITTING…' : 'SUBMIT WITHDRAWAL',
                icon: Icons.arrow_upward_rounded,
                color: _exceedsBalance ? _C.textMuted : _C.live,
                onTap: (_loading || _exceedsBalance) ? null : _submit,
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _InsufficientBalanceCard extends StatelessWidget {
  final double available, requested;
  const _InsufficientBalanceCard({super.key, required this.available, required this.requested});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _C.live.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.live.withValues(alpha: 0.5), width: 1.5), boxShadow: [BoxShadow(color: _C.liveGlow.withValues(alpha: 0.3), blurRadius: 18, spreadRadius: 1)]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _C.live.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.warning_amber_rounded, color: _C.live, size: 16)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('INSUFFICIENT WALLET BALANCE', style: _ts(size: 11, weight: FontWeight.w900, color: _C.live, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text('You are trying to withdraw ₹${requested.toStringAsFixed(2)} but your available balance is only ₹${available.toStringAsFixed(2)}.', style: _ts(size: 11, color: _C.textSecondary, height: 1.5)),
          const SizedBox(height: 8),
          Row(children: [
            _MiniStat(label: 'AVAILABLE', value: '₹${available.toStringAsFixed(2)}', color: _C.success),
            const SizedBox(width: 16),
            _MiniStat(label: 'REQUESTED', value: '₹${requested.toStringAsFixed(2)}', color: _C.live),
          ]),
        ])),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value; final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _ts(size: 8, weight: FontWeight.w800, color: _C.textMuted, letterSpacing: 0.8)),
      Text(value, style: _ts(size: 13, weight: FontWeight.w900, color: color)),
    ]);
  }
}

class _LiveBalanceChip extends StatelessWidget {
  final double balance;
  const _LiveBalanceChip({required this.balance});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: _C.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.success.withValues(alpha: 0.3))),
      child: Row(children: [
        const Icon(Icons.account_balance_wallet_rounded, color: _C.success, size: 16), const SizedBox(width: 10),
        Text('Available Balance:', style: _ts(size: 12, color: _C.textSecondary)), const Spacer(),
        Text('₹${balance.toStringAsFixed(2)}', style: _ts(size: 15, weight: FontWeight.w900, color: _C.success)),
      ]),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: HISTORY (unchanged from v3)
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
        _SectionTitle(label: 'PENDING DEPOSITS', icon: Icons.add_circle_rounded, color: _C.success),
        const SizedBox(height: 10),
        StreamBuilder<List<DepositRequest>>(
          stream: service.depositRequestsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const _InlineLoader();
            final list = (snap.data ?? []).where((r) => r.status == 'pending').toList();
            if (list.isEmpty) return _EmptyInline(message: 'No pending deposits.');
            return Column(children: list.map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _DepositReqCard(req: r))).toList());
          },
        ),
        const SizedBox(height: 20),
        _SectionTitle(label: 'PENDING WITHDRAWALS', icon: Icons.remove_circle_rounded, color: _C.live),
        const SizedBox(height: 10),
        StreamBuilder<List<WithdrawRequest>>(
          stream: service.withdrawRequestsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const _InlineLoader();
            final list = (snap.data ?? []).where((r) => r.status == 'pending').toList();
            if (list.isEmpty) return _EmptyInline(message: 'No pending withdrawals.');
            return Column(children: list.map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _WithdrawReqCard(req: r))).toList());
          },
        ),
        const SizedBox(height: 20),
        _SectionTitle(label: 'TRANSACTION HISTORY', icon: Icons.receipt_long_rounded, color: _C.purple),
        const SizedBox(height: 10),
        StreamBuilder<List<WalletTransaction>>(
          stream: service.transactionsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const _InlineLoader();
            if (snap.hasError) return _EmptyInline(message: 'Could not load transactions.');
            final list = snap.data ?? [];
            if (list.isEmpty) return _EmptyInline(message: 'No transactions yet.\nDeposit funds to get started!');
            return Column(children: list.map((tx) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _TxCard(tx: tx))).toList());
          },
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION: SUPPORT (unchanged from v3)
// ═════════════════════════════════════════════
class _SupportSection extends StatelessWidget {
  Future<void> _launch(BuildContext ctx, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Could not open: $url'), backgroundColor: _C.live));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoBanner(icon: Icons.support_agent_rounded, color: _C.purple, text: 'Need help? Contact our support team on Discord or Telegram. We usually respond within 30 minutes.'),
        const SizedBox(height: 24),
        _SectionTitle(label: 'OFFICIAL SUPPORT CHANNELS', icon: Icons.headset_mic_rounded, color: _C.purple),
        const SizedBox(height: 12),
        _PremiumSupportCard(platform: 'DISCORD', name: '! SHADOW', handle: '@mastersenpai1', serverLabel: 'Shadow Storm Community', color: _C.discord, icon: Icons.forum_rounded, badge: 'MAIN SUPPORT', onTap: () => _launch(context, 'https://discord.gg/2eUqD7wtBR')),
        const SizedBox(height: 12),
        _PremiumSupportCard(platform: 'TELEGRAM', name: 'Anonymaster', handle: '@Anonymaster_a', serverLabel: 'Direct message for fast support', color: _C.telegram, icon: Icons.send_rounded, badge: 'QUICK RESPONSE', onTap: () => _launch(context, 'https://t.me/Anonymaster_a')),
        const SizedBox(height: 24),
        _SectionTitle(label: 'COMMON ISSUES', icon: Icons.help_outline_rounded, color: _C.gold),
        const SizedBox(height: 12),
        ...[
          ('My deposit is pending for too long?', 'Contact support with your UTR number. Approvals happen daily 8 PM – 8 AM.'),
          ('Withdrawal not received?', 'Withdrawals take up to 24 hours. Contact support with your request ID.'),
          ('Wrong UTR submitted?', 'Message support immediately on Discord or Telegram with the correct UTR.'),
          ('Balance not updated after winning?', 'Winnings are credited within 30 minutes of tournament end. Contact support if delayed.'),
        ].map((pair) {
          final (q, a) = pair;
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: _FaqCard(question: q, answer: a));
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// ALL REUSABLE ATOMS (unchanged from v3)
// ─────────────────────────────────────────────

class _StepBadge extends StatelessWidget {
  final String number, label;
  const _StepBadge({required this.number, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 24, height: 24, decoration: BoxDecoration(color: _C.purple, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _C.purpleGlow, blurRadius: 8)]), child: Center(child: Text(number, style: _ts(size: 11, weight: FontWeight.w900, color: Colors.white)))),
      const SizedBox(width: 8),
      Text(label, style: _ts(size: 10, weight: FontWeight.w800, color: _C.textSecondary, letterSpacing: 1.2)),
    ]);
  }
}

class _PremiumSupportCard extends StatefulWidget {
  final String platform, name, handle, serverLabel, badge; final Color color; final IconData icon; final VoidCallback onTap;
  const _PremiumSupportCard({required this.platform, required this.name, required this.handle, required this.serverLabel, required this.color, required this.icon, required this.badge, required this.onTap});
  @override State<_PremiumSupportCard> createState() => _PremiumSupportCardState();
}
class _PremiumSupportCardState extends State<_PremiumSupportCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: widget.color.withValues(alpha: 0.4)), boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 4))]),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12), border: Border.all(color: widget.color.withValues(alpha: 0.4))), child: Icon(widget.icon, color: widget.color, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(widget.platform, style: _ts(size: 13, weight: FontWeight.w900, color: widget.color, letterSpacing: 1)),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text(widget.badge, style: _ts(size: 8, weight: FontWeight.w800, color: widget.color, letterSpacing: 0.8))),
            ]),
            const SizedBox(height: 3),
            Text(widget.name, style: _ts(size: 14, weight: FontWeight.w800)),
            Text(widget.handle, style: _ts(size: 11, color: _C.textMuted)),
            const SizedBox(height: 2),
            Text(widget.serverLabel, style: _ts(size: 10, color: _C.textSecondary)),
          ])),
          Icon(Icons.open_in_new_rounded, color: widget.color.withValues(alpha: 0.7), size: 18),
        ]),
      )),
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
        decoration: BoxDecoration(color: _open ? _C.purpleGlowFaint : _C.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: _open ? _C.purple.withValues(alpha: 0.4) : _C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.question, style: _ts(size: 12, weight: FontWeight.w700))),
            Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _C.textMuted, size: 18),
          ]),
          if (_open) ...[const SizedBox(height: 8), Text(widget.answer, style: _ts(size: 11, color: _C.textSecondary, height: 1.5))],
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
      decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: statusColor.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: _C.success.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.add_rounded, color: _C.success, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Deposit Request', style: _ts(size: 13, weight: FontWeight.w700)),
            Text('UTR: ${req.utr}', style: _ts(size: 11, color: _C.textMuted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${req.amount.toStringAsFixed(2)}', style: _ts(size: 15, weight: FontWeight.w900, color: _C.success)),
            const SizedBox(height: 4),
            _StatusPill(status: req.status, color: statusColor),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(_timeAgo(req.createdAt), style: _ts(size: 10, color: _C.textMuted)),
        if (req.adminNote != null) ...[const SizedBox(height: 6), _InfoBanner(icon: Icons.message_rounded, color: _C.purple, text: req.adminNote!)],
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
      decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: statusColor.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: _C.live.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.remove_rounded, color: _C.live, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Withdrawal Request', style: _ts(size: 13, weight: FontWeight.w700)),
            Text(req.method == 'upi' ? '📱 ${req.upiId}' : '🏦 ${req.accountHolder}', style: _ts(size: 11, color: _C.textMuted), overflow: TextOverflow.ellipsis),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${req.amount.toStringAsFixed(2)}', style: _ts(size: 15, weight: FontWeight.w900, color: _C.live)),
            const SizedBox(height: 4),
            _StatusPill(status: req.status, color: statusColor),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(_timeAgo(req.createdAt), style: _ts(size: 10, color: _C.textMuted)),
        if (req.adminNote != null) ...[const SizedBox(height: 6), _InfoBanner(icon: Icons.message_rounded, color: _C.purple, text: req.adminNote!)],
      ]),
    );
  }
}

class _TxCard extends StatelessWidget {
  final WalletTransaction tx;
  const _TxCard({required this.tx});
  IconData get _icon => switch (tx.type) { 'deposit' => Icons.add_circle_rounded, 'withdrawal' => Icons.remove_circle_rounded, 'tournament_entry' => Icons.sports_esports_rounded, 'winnings' => Icons.emoji_events_rounded, 'refund' => Icons.replay_rounded, _ => Icons.swap_horiz_rounded };
  Color get _color => tx.isCredit ? _C.success : _C.live;
  String get _label => switch (tx.type) { 'deposit' => 'Deposit', 'withdrawal' => 'Withdrawal', 'tournament_entry' => 'Tournament Entry', 'winnings' => 'Winnings', 'refund' => 'Refund', _ => tx.type };
  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(tx.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(_icon, color: _color, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_label, style: _ts(size: 13, weight: FontWeight.w700)),
          if (tx.description != null) ...[const SizedBox(height: 2), Text(tx.description!, style: _ts(size: 11, color: _C.textMuted), overflow: TextOverflow.ellipsis)],
          const SizedBox(height: 4),
          Row(children: [
            _StatusPill(status: tx.status, color: statusColor),
            const SizedBox(width: 8),
            Text(_timeAgo(tx.createdAt), style: _ts(size: 10, color: _C.textMuted)),
          ]),
        ])),
        const SizedBox(width: 8),
        Text('${tx.isCredit ? '+' : '-'}₹${tx.amount.toStringAsFixed(2)}', style: _ts(size: 14, weight: FontWeight.w900, color: tx.isCredit ? _C.success : _C.live)),
      ]),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label; final double? value; final Color color; final IconData icon;
  const _BalanceStat({required this.label, required this.value, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13), const SizedBox(height: 4),
      value == null ? _ShimmerBox(width: 50, height: 14) : Text('₹${value!.toStringAsFixed(0)}', style: _ts(size: 12, weight: FontWeight.w800, color: color), overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(label, style: _ts(size: 8, weight: FontWeight.w700, color: _C.textMuted, letterSpacing: 0.8)),
    ]);
  }
}

class _SupportButton extends StatefulWidget {
  final String label, sublabel; final Color color; final IconData icon; final VoidCallback onTap;
  const _SupportButton({required this.label, required this.sublabel, required this.color, required this.icon, required this.onTap});
  @override State<_SupportButton> createState() => _SupportButtonState();
}
class _SupportButtonState extends State<_SupportButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: widget.color.withValues(alpha: 0.45)), boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(widget.icon, color: widget.color, size: 18), const SizedBox(width: 6),
            Expanded(child: Text(widget.label, style: _ts(size: 12, weight: FontWeight.w800, color: widget.color), overflow: TextOverflow.ellipsis)),
            Icon(Icons.open_in_new_rounded, color: widget.color.withValues(alpha: 0.6), size: 13),
          ]),
          const SizedBox(height: 4),
          Text(widget.sublabel, style: _ts(size: 10, color: _C.textMuted), overflow: TextOverflow.ellipsis),
        ]),
      )),
    );
  }
}

class _GlowButton extends StatefulWidget {
  final String label; final IconData icon; final Color color; final VoidCallback? onTap;
  const _GlowButton({required this.label, required this.icon, this.color = _C.purple, this.onTap});
  @override State<_GlowButton> createState() => _GlowButtonState();
}
class _GlowButtonState extends State<_GlowButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return GestureDetector(
      onTapDown: (_) { if (!disabled) _ctrl.forward(); },
      onTapUp: (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: disabled ? [_C.surfaceElevated, _C.surfaceElevated] : [widget.color, widget.color.withValues(alpha: 0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled ? [] : [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(widget.icon, color: disabled ? _C.textMuted : Colors.white, size: 18), const SizedBox(width: 10),
          Text(widget.label, style: _ts(size: 13, weight: FontWeight.w900, letterSpacing: 1.2, color: disabled ? _C.textMuted : Colors.white)),
        ]),
      )),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _MethodToggle({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: active ? _C.purpleGlowFaint : _C.surfaceCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? _C.purple : _C.border, width: active ? 1.5 : 1), boxShadow: active ? [BoxShadow(color: _C.purpleGlow.withValues(alpha: 0.4), blurRadius: 10)] : []),
        child: Center(child: Text(label, style: _ts(size: 13, weight: FontWeight.w700, color: active ? _C.purpleLight : _C.textSecondary))),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller; final String hint; final TextInputType keyboardType; final String? prefixText; final List<TextInputFormatter>? inputFormatters; final String? Function(String?)? validator; final TextCapitalization textCapitalization;
  const _StyledField({required this.controller, required this.hint, this.keyboardType = TextInputType.text, this.prefixText, this.inputFormatters, this.validator, this.textCapitalization = TextCapitalization.none});
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType, inputFormatters: inputFormatters,
      validator: validator, textCapitalization: textCapitalization,
      style: _ts(size: 14, weight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint, prefixText: prefixText,
        hintStyle: _ts(size: 13, color: _C.textMuted),
        prefixStyle: _ts(size: 14, weight: FontWeight.w700, color: _C.textSecondary),
        filled: true, fillColor: _C.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.purple, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.live)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.live, width: 1.5)),
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
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: _ts(size: 10, weight: FontWeight.w800, color: _C.textMuted, letterSpacing: 1.2)));
  }
}

class _SectionTitle extends StatelessWidget {
  final String label; final IconData icon; final Color color;
  const _SectionTitle({required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 3, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Icon(icon, color: color, size: 14), const SizedBox(width: 6),
      Text(label, style: _ts(size: 10, weight: FontWeight.w800, color: _C.textSecondary, letterSpacing: 1.5)),
    ]);
  }
}

class _StatusPill extends StatelessWidget {
  final String status; final Color color;
  const _StatusPill({required this.status, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(status.toUpperCase(), style: _ts(size: 9, weight: FontWeight.w800, color: color, letterSpacing: 0.8)),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon; final Color color; final String text;
  const _InfoBanner({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 15), const SizedBox(width: 10),
        Expanded(child: Text(text, style: _ts(size: 12, color: _C.textSecondary))),
      ]),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String text; final bool isError;
  const _StatusBanner({required this.text, required this.isError});
  @override
  Widget build(BuildContext context) {
    final color = isError ? _C.live : _C.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: color, size: 17),
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
    return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: _C.purple, strokeWidth: 2))));
  }
}

class _EmptyInline extends StatelessWidget {
  final String message;
  const _EmptyInline({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)), child: Text(message, style: _ts(size: 12, color: _C.textMuted), textAlign: TextAlign.center));
  }
}

class _PulseDot extends StatelessWidget {
  final Color color; final Animation<double> pulse;
  const _PulseDot({required this.color, required this.pulse});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: pulse, builder: (_, _) => Container(
      width: 6, height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.5 + 0.5 * pulse.value), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5 * pulse.value)]),
    ));
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width, height;
  const _ShimmerBox({required this.width, required this.height});
  @override State<_ShimmerBox> createState() => _ShimmerBoxState();
}
class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true); _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _anim, builder: (_, _) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(color: _C.surfaceElevated.withValues(alpha: 0.5 + 0.4 * _anim.value), borderRadius: BorderRadius.circular(8)),
    ));
  }
}

class _HoloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF9D55FF).withValues(alpha: 0.04)..strokeWidth = 1;
    for (var i = 0; i < 8; i++) { final y = size.height * i / 7; canvas.drawLine(Offset(0, y), Offset(size.width, y), paint); }
    final diag = Paint()..color = const Color(0xFFB07EF8).withValues(alpha: 0.05)..strokeWidth = 0.5;
    for (var i = 0; i < 6; i++) { final x = size.width * (0.5 + i * 0.12); canvas.drawLine(Offset(x, 0), Offset(x - size.height * 0.6, size.height), diag); }
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}