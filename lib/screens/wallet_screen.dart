// lib/screens/wallet_screen.dart
// ─────────────────────────────────────────────
// WALLET SCREEN  — Shadow Storm
// Sections:
//   1. Balance Overview (animated gaming cards, live from Firestore)
//   2. Deposit Request  (amount + UTR only — no screenshot upload)
//   3. Withdraw Request (UPI / Bank details)
//   4. Transaction History (realtime stream)
//   5. Pending Requests (deposit + withdraw combined)

// SECURITY: Frontend NEVER modifies walletBalance directly.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/wallet_service.dart';

// ── Design tokens (mirror home_screen.dart SSColors) ──
class _C {
  static const background      = Color(0xFF06040E);
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
  static const live            = Color(0xFFFF4466);
  static const success         = Color(0xFF44FF99);
  static const discord         = Color(0xFF5865F2);
  static const telegram        = Color(0xFF229ED9);

  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);

  static const pending  = Color(0xFFFFCC44);
  static const approved = Color(0xFF44FF99);
  static const rejected = Color(0xFFFF4466);
}

TextStyle _ts({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = _C.textPrimary,
  double letterSpacing = 0,
}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFamily: 'Roboto',
    );

// ─────────────────────────────────────────────
// WALLET SCREEN
// ─────────────────────────────────────────────
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  final WalletService _service = WalletService.instance;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // WalletScreen is a full Scaffold pushed via Navigator.push.
    // The parent HomeScreen (with its bottom nav) remains in the stack
    // behind this screen — that is why the bottom nav stays visible
    // when the user taps the back arrow here.
    return Scaffold(
      backgroundColor: _C.background,
      body: NestedScrollView(
        physics: const BouncingScrollPhysics(),
        headerSliverBuilder: (ctx, _) => [
          _WalletAppBar(),
          SliverToBoxAdapter(child: _BalanceSection(service: _service)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(controller: _tabCtrl),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          physics: const BouncingScrollPhysics(),
          children: [
            _DepositTab(service: _service),
            _WithdrawTab(service: _service),
            _TransactionHistoryTab(service: _service),
            _PendingRequestsTab(service: _service),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// APP BAR
// ─────────────────────────────────────────────
class _WalletAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: _C.background,
      pinned: true,
      expandedHeight: 0,
      toolbarHeight: 56,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            color: _C.textSecondary, size: 20),
      ),
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _C.purpleGlowFaint,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _C.border),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: _C.purple, size: 18),
        ),
        const SizedBox(width: 10),
        Text('WALLET',
            style: _ts(
                size: 16,
                weight: FontWeight.w900,
                color: _C.textPrimary,
                letterSpacing: 2)),
      ]),
      centerTitle: false,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEE06040E), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SECTION 1 — BALANCE OVERVIEW (live from Firestore)
// ─────────────────────────────────────────────
class _BalanceSection extends StatelessWidget {
  final WalletService service;
  const _BalanceSection({required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WalletData>(
      stream: service.walletDataStream(),
      builder: (ctx, snap) {
        final data    = snap.data ?? WalletData.empty;
        final loading = snap.connectionState == ConnectionState.waiting;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(children: [
            // ── Main balance card ──────────────
            _GlowCard(
              glowColor: _C.purpleGlow,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E1538), Color(0xFF0E0A1A)],
                  ),
                  border: Border.all(color: _C.borderBright),
                ),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.account_balance_wallet_rounded,
                        color: _C.purple, size: 18),
                    const SizedBox(width: 8),
                    Text('WALLET BALANCE',
                        style: _ts(
                            size: 11,
                            weight: FontWeight.w700,
                            color: _C.textSecondary,
                            letterSpacing: 1.5)),
                    const Spacer(),
                    _PulseDot(color: _C.success),
                    const SizedBox(width: 6),
                    Text('LIVE',
                        style: _ts(
                            size: 9,
                            weight: FontWeight.w800,
                            color: _C.success,
                            letterSpacing: 1)),
                  ]),
                  const SizedBox(height: 12),
                  loading
                      ? const _ShimmerBox(width: 160, height: 40)
                      : Text(
                          '₹${data.balance.toStringAsFixed(2)}',
                          style: _ts(
                              size: 36,
                              weight: FontWeight.w900,
                              color: _C.gold,
                              letterSpacing: 0.5),
                        ),
                  const SizedBox(height: 4),
                  Text('Available to use',
                      style: _ts(size: 12, color: _C.textMuted)),
                ]),
              ),
            ),

            const SizedBox(height: 12),

            // ── 3 stat mini-cards ──────────────
            Row(children: [
              Expanded(
                  child: _MiniStatCard(
                label: 'EARNINGS',
                value: loading ? null : data.totalEarnings,
                icon: Icons.emoji_events_rounded,
                color: _C.gold,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _MiniStatCard(
                label: 'DEPOSITED',
                value: loading ? null : data.totalDeposits,
                icon: Icons.add_circle_outline_rounded,
                color: _C.success,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _MiniStatCard(
                label: 'WITHDRAWN',
                value: loading ? null : data.totalWithdrawals,
                icon: Icons.remove_circle_outline_rounded,
                color: _C.live,
              )),
            ]),
          ]),
        );
      },
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String  label;
  final double? value;
  final IconData icon;
  final Color   color;
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 6),
        value == null
            ? const _ShimmerBox(width: 60, height: 14)
            : Text(
                '₹${value!.toStringAsFixed(0)}',
                style: _ts(size: 14, weight: FontWeight.w800, color: color),
                overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label,
            style: _ts(
                size: 9,
                weight: FontWeight.w600,
                color: _C.textMuted,
                letterSpacing: 1)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// PINNED TAB BAR DELEGATE
// ─────────────────────────────────────────────
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;

  const _TabBarDelegate({
    required this.controller,
  });

  // Set the structural constraints to match standard TabBar height explicitly
  @override
  double get minExtent => 48.0;

  @override
  double get maxExtent => 48.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: _C.background,
      height: 48.0, // Hard-constrain the frame boundary to prevent layout leaks
      child: TabBar(
        controller: controller,
        isScrollable: true,
        indicatorColor: _C.purple,
        labelColor: _C.purpleLight,
        unselectedLabelColor: _C.textMuted,
        // Optional tracking refinements for clean dark typography profiles
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        tabs: const [
          Tab(text: '💰 DEPOSIT'),
          Tab(text: '🏦 WITHDRAW'),
          Tab(text: '📋 HISTORY'),
          Tab(text: '⏳ PENDING'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
    return controller != oldDelegate.controller;
  }
}

// ─────────────────────────────────────────────
// SECTION 2 — DEPOSIT REQUEST TAB
// Screenshot upload removed. User sends proof via Discord / Telegram.
// ─────────────────────────────────────────────
class _DepositTab extends StatefulWidget {
  final WalletService service;
  const _DepositTab({required this.service});

  @override
  State<_DepositTab> createState() => _DepositTabState();
}

class _DepositTabState extends State<_DepositTab> {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _utrCtrl    = TextEditingController();

  bool    _loading = false;
  String? _error;
  bool    _success = false;

  final _quickAmounts = [100, 250, 500, 1000, 2500, 5000];

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
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $url'),
            backgroundColor: _C.live,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Info banner ───────────────────
          _InfoBanner(
            icon: Icons.info_outline_rounded,
            color: _C.purple,
            text:
                'Enter your deposit amount and UTR number. '
                'Then send your payment screenshot to our Discord or Telegram '
                'for quick approval (within 30 minutes).',
          ),
          const SizedBox(height: 20),

          // ── Amount ────────────────────────
          _FieldLabel('AMOUNT (₹)'),
          _StyledField(
            controller: _amountCtrl,
            hint: 'Enter deposit amount',
            keyboardType: TextInputType.number,
            prefixText: '₹ ',
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
            ],
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid amount';
              if (n < 50) return 'Minimum deposit is ₹50';
              return null;
            },
          ),
          const SizedBox(height: 10),

          // ── Quick amounts ──────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickAmounts
                .map((a) => GestureDetector(
                      onTap: () =>
                          setState(() => _amountCtrl.text = a.toString()),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _amountCtrl.text == a.toString()
                              ? _C.purpleGlowFaint
                              : _C.surfaceCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _amountCtrl.text == a.toString()
                                ? _C.purple
                                : _C.border,
                          ),
                        ),
                        child: Text(
                          '₹$a',
                          style: _ts(
                              size: 12,
                              weight: FontWeight.w700,
                              color: _amountCtrl.text == a.toString()
                                  ? _C.purpleLight
                                  : _C.textSecondary),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),

          // ── UTR ───────────────────────────
          _FieldLabel('UTR / TRANSACTION ID'),
          _StyledField(
            controller: _utrCtrl,
            hint: 'Enter your UTR number',
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'UTR is required';
              if (v.trim().length < 6) return 'Invalid UTR number';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // ── Payment QR placeholder ─────────
          _SectionCard(
            title: 'PAY TO THIS UPI',
            child: Column(children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'QR CODE\nHERE',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('shadowstorm@upi',
                  style: _ts(
                      size: 14,
                      weight: FontWeight.w700,
                      color: _C.gold)),
              const SizedBox(height: 4),
              Text('Pay & save your UTR number',
                  style: _ts(size: 12, color: _C.textMuted)),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Screenshot instruction banner ──
          _InfoBanner(
            icon: Icons.photo_camera_rounded,
            color: _C.gold,
            text:
                'After submitting, send your payment screenshot to our '
                'Discord or Telegram support for approval.',
          ),
          const SizedBox(height: 16),

          // ── Support buttons ────────────────
          _FieldLabel('SEND SCREENSHOT FOR APPROVAL'),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: _SupportButton(
                label: 'Discord Support',
                sublabel: '@mastersenpai1 · ! SHADOW',
                color: _C.discord,
                icon: Icons.forum_rounded,
                onTap: () =>
                    _launchUrl('https://discord.gg/2eUqD7wtBR'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SupportButton(
                label: 'Telegram Support',
                sublabel: '@Anonymaster_a',
                color: _C.telegram,
                icon: Icons.send_rounded,
                onTap: () =>
                    _launchUrl('https://t.me/Anonymaster_a'),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Error / Success ────────────────
          if (_error != null) _StatusBanner(text: _error!, isError: true),
          if (_success)
            _StatusBanner(
              text:
                  '✅ Deposit request submitted!\n'
                  'Now send your payment screenshot to Discord or Telegram '
                  'for approval (usually within 30 minutes).',
              isError: false,
            ),

          const SizedBox(height: 12),

          // ── Submit button ──────────────────
          _GlowButton(
            label: _loading ? 'SUBMITTING...' : 'SUBMIT DEPOSIT REQUEST',
            icon: Icons.upload_rounded,
            onTap: _loading ? null : _submit,
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SECTION 3 — WITHDRAW REQUEST TAB (unchanged)
// ─────────────────────────────────────────────
class _WithdrawTab extends StatefulWidget {
  final WalletService service;
  const _WithdrawTab({required this.service});

  @override
  State<_WithdrawTab> createState() => _WithdrawTabState();
}

class _WithdrawTabState extends State<_WithdrawTab> {
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
    _amountCtrl.dispose();
    _upiCtrl.dispose();
    _holderCtrl.dispose();
    _bankCtrl.dispose();
    _accountCtrl.dispose();
    _ifscCtrl.dispose();
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
      _amountCtrl.clear();
      _upiCtrl.clear();
      _holderCtrl.clear();
      _bankCtrl.clear();
      _accountCtrl.clear();
      _ifscCtrl.clear();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          _InfoBanner(
            icon: Icons.schedule_rounded,
            color: _C.gold,
            text:
                'Withdrawals are processed within 24 hours after admin approval.',
          ),
          const SizedBox(height: 20),

          _FieldLabel('WITHDRAW AMOUNT (₹)'),
          _StyledField(
            controller: _amountCtrl,
            hint: 'Enter amount',
            keyboardType: TextInputType.number,
            prefixText: '₹ ',
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
            ],
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid amount';
              if (n < 100) return 'Minimum withdrawal is ₹100';
              return null;
            },
          ),
          const SizedBox(height: 20),

          _FieldLabel('WITHDRAWAL METHOD'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _MethodToggle(
              label: '📱 UPI',
              active: _method == 'upi',
              onTap: () => setState(() => _method = 'upi'),
            )),
            const SizedBox(width: 10),
            Expanded(
                child: _MethodToggle(
              label: '🏦 Bank Transfer',
              active: _method == 'bank',
              onTap: () => setState(() => _method = 'bank'),
            )),
          ]),
          const SizedBox(height: 20),

          if (_method == 'upi') ...[
            _FieldLabel('UPI ID'),
            _StyledField(
              controller: _upiCtrl,
              hint: 'yourname@bank',
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'UPI ID is required';
                if (!v.contains('@')) return 'Invalid UPI ID format';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _FieldLabel('ACCOUNT HOLDER NAME'),
            _StyledField(
              controller: _holderCtrl,
              hint: 'Full name as registered',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),
          ],

          if (_method == 'bank') ...[
            _FieldLabel('ACCOUNT HOLDER NAME'),
            _StyledField(
              controller: _holderCtrl,
              hint: 'Full name as on bank account',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 14),
            _FieldLabel('BANK NAME'),
            _StyledField(
              controller: _bankCtrl,
              hint: 'e.g. State Bank of India',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Bank name is required'
                  : null,
            ),
            const SizedBox(height: 14),
            _FieldLabel('ACCOUNT NUMBER'),
            _StyledField(
              controller: _accountCtrl,
              hint: 'Enter account number',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Account number is required';
                if (v.trim().length < 8) return 'Invalid account number';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _FieldLabel('IFSC CODE'),
            _StyledField(
              controller: _ifscCtrl,
              hint: 'e.g. SBIN0001234',
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'IFSC is required';
                if (v.trim().length != 11) return 'IFSC must be 11 characters';
                return null;
              },
            ),
          ],

          const SizedBox(height: 20),

          if (_error != null) _StatusBanner(text: _error!, isError: true),
          if (_success)
            _StatusBanner(
              text: 'Withdrawal request submitted! Processing within 24 hours.',
              isError: false,
            ),

          const SizedBox(height: 12),

          _GlowButton(
            label: _loading ? 'SUBMITTING...' : 'SUBMIT WITHDRAWAL',
            icon: Icons.arrow_upward_rounded,
            color: _C.live,
            onTap: _loading ? null : _submit,
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SECTION 4 — TRANSACTION HISTORY TAB
// ─────────────────────────────────────────────
class _TransactionHistoryTab extends StatelessWidget {
  final WalletService service;
  const _TransactionHistoryTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WalletTransaction>>(
      stream: service.transactionsStream(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingState();
        }
        if (snap.hasError) {
          return const _ErrorState(
              message: 'Could not load transactions.');
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.receipt_long_rounded,
            message: 'No transactions yet.\nDeposit funds to get started!',
          );
        }
        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => _TransactionCard(tx: list[i]),
        );
      },
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionCard({required this.tx});

  IconData get _icon {
    switch (tx.type) {
      case 'deposit':          return Icons.add_circle_rounded;
      case 'withdrawal':       return Icons.remove_circle_rounded;
      case 'tournament_entry': return Icons.sports_esports_rounded;
      case 'winnings':         return Icons.emoji_events_rounded;
      case 'refund':           return Icons.replay_rounded;
      default:                 return Icons.swap_horiz_rounded;
    }
  }

  Color get _color {
    if (tx.isCredit) return _C.success;
    return _C.live;
  }

  String get _typeLabel {
    switch (tx.type) {
      case 'deposit':          return 'Deposit';
      case 'withdrawal':       return 'Withdrawal';
      case 'tournament_entry': return 'Tournament Entry';
      case 'winnings':         return 'Winnings';
      case 'refund':           return 'Refund';
      default:                 return tx.type;
    }
  }

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
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_icon, color: _color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(_typeLabel,
                style: _ts(size: 13, weight: FontWeight.w700)),
            if (tx.note != null) ...[
              const SizedBox(height: 2),
              Text(tx.note!,
                  style: _ts(size: 11, color: _C.textMuted),
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 4),
            Row(children: [
              _StatusPill(status: tx.status, color: statusColor),
              const SizedBox(width: 8),
              Text(_formatDate(tx.createdAt),
                  style: _ts(size: 10, color: _C.textMuted)),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          '${tx.isCredit ? '+' : '-'}₹${tx.amount.toStringAsFixed(2)}',
          style: _ts(
              size: 15,
              weight: FontWeight.w900,
              color: tx.isCredit ? _C.success : _C.live),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// SECTION 5 — PENDING REQUESTS TAB
// ─────────────────────────────────────────────
class _PendingRequestsTab extends StatelessWidget {
  final WalletService service;
  const _PendingRequestsTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Deposit Requests ──────────────────
        _SectionTitle(
            label: 'DEPOSIT REQUESTS',
            icon: Icons.add_circle_rounded,
            color: _C.success),
        const SizedBox(height: 10),
        StreamBuilder<List<DepositRequest>>(
          stream: service.depositRequestsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingState();
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return const _EmptyState(
                icon: Icons.inbox_rounded,
                message: 'No deposit requests yet.',
              );
            }
            return Column(
              children: list
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DepositRequestCard(req: r),
                      ))
                  .toList(),
            );
          },
        ),

        const SizedBox(height: 24),

        // ── Withdraw Requests ─────────────────
        _SectionTitle(
            label: 'WITHDRAWAL REQUESTS',
            icon: Icons.remove_circle_rounded,
            color: _C.live),
        const SizedBox(height: 10),
        StreamBuilder<List<WithdrawRequest>>(
          stream: service.withdrawRequestsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingState();
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return const _EmptyState(
                icon: Icons.inbox_rounded,
                message: 'No withdrawal requests yet.',
              );
            }
            return Column(
              children: list
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _WithdrawRequestCard(req: r),
                      ))
                  .toList(),
            );
          },
        ),
      ]),
    );
  }
}

class _DepositRequestCard extends StatelessWidget {
  final DepositRequest req;
  const _DepositRequestCard({required this.req});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(req.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.add_circle_rounded, color: _C.success, size: 16),
          const SizedBox(width: 8),
          Text('Deposit Request',
              style: _ts(size: 13, weight: FontWeight.w700)),
          const Spacer(),
          Text('₹${req.amount.toStringAsFixed(2)}',
              style: _ts(
                  size: 15, weight: FontWeight.w900, color: _C.success)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('UTR: ', style: _ts(size: 11, color: _C.textMuted)),
          Text(req.utr,
              style: _ts(
                  size: 11,
                  weight: FontWeight.w700,
                  color: _C.textSecondary)),
          const Spacer(),
          _StatusPill(status: req.status, color: statusColor),
        ]),
        const SizedBox(height: 6),
        Text(_formatDate(req.createdAt),
            style: _ts(size: 10, color: _C.textMuted)),
        if (req.status == 'pending') ...[
          const SizedBox(height: 10),
          _InfoBanner(
            icon: Icons.photo_camera_rounded,
            color: _C.gold,
            text:
                'Send your payment screenshot to Discord or Telegram to speed up approval.',
          ),
        ],
      ]),
    );
  }
}

class _WithdrawRequestCard extends StatelessWidget {
  final WithdrawRequest req;
  const _WithdrawRequestCard({required this.req});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(req.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.remove_circle_rounded, color: _C.live, size: 16),
          const SizedBox(width: 8),
          Text('Withdrawal Request',
              style: _ts(size: 13, weight: FontWeight.w700)),
          const Spacer(),
          Text('₹${req.amount.toStringAsFixed(2)}',
              style:
                  _ts(size: 15, weight: FontWeight.w900, color: _C.live)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(
              req.method == 'upi'
                  ? '📱 ${req.upiId}'
                  : '🏦 ${req.accountHolder}',
              style: _ts(size: 11, color: _C.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(status: req.status, color: statusColor),
        ]),
        const SizedBox(height: 6),
        Text(_formatDate(req.createdAt),
            style: _ts(size: 10, color: _C.textMuted)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────

class _GlowCard extends StatelessWidget {
  final Widget child;
  final Color  glowColor;
  const _GlowCard({required this.child, required this.glowColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: glowColor, blurRadius: 20)],
      ),
      child: child,
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController          controller;
  final String                         hint;
  final TextInputType                  keyboardType;
  final String?                        prefixText;
  final List<TextInputFormatter>?      inputFormatters;
  final String? Function(String?)?     validator;
  final TextCapitalization             textCapitalization;

  const _StyledField({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.prefixText,
    this.inputFormatters,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textCapitalization: textCapitalization,
      style: _ts(size: 14, weight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefixText,
        hintStyle: _ts(size: 13, color: _C.textMuted),
        prefixStyle:
            _ts(size: 14, weight: FontWeight.w700, color: _C.textSecondary),
        filled: true,
        fillColor: _C.surfaceCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Text(text,
          style: _ts(
              size: 10,
              weight: FontWeight.w800,
              color: _C.textMuted,
              letterSpacing: 1.2)),
    );
  }
}

/// Gaming-style support button for Discord / Telegram.
class _SupportButton extends StatefulWidget {
  final String   label;
  final String   sublabel;
  final Color    color;
  final IconData icon;
  final VoidCallback onTap;

  const _SupportButton({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_SupportButton> createState() => _SupportButtonState();
}

class _SupportButtonState extends State<_SupportButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) => _ctrl.forward(),
      onTapUp:    (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.color.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(widget.icon, color: widget.color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.label,
                      style: _ts(
                          size: 12,
                          weight: FontWeight.w800,
                          color: widget.color),
                      overflow: TextOverflow.ellipsis),
                ),
                Icon(Icons.open_in_new_rounded,
                    color: widget.color.withValues(alpha: 0.7), size: 13),
              ]),
              const SizedBox(height: 4),
              Text(widget.sublabel,
                  style: _ts(size: 10, color: _C.textMuted),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowButton extends StatefulWidget {
  final String        label;
  final IconData      icon;
  final Color         color;
  final VoidCallback? onTap;

  const _GlowButton({
    required this.label,
    required this.icon,
    this.color = _C.purple,
    this.onTap,
  });

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: disabled
                ? []
                : [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Icon(widget.icon,
                color: disabled ? _C.textMuted : Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(widget.label,
                style: _ts(
                    size: 13,
                    weight: FontWeight.w900,
                    color: disabled ? _C.textMuted : Colors.white,
                    letterSpacing: 1.2)),
          ]),
        ),
      ),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;
  const _MethodToggle(
      {required this.label, required this.active, required this.onTap});

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
            color: active ? _C.purple : _C.border,
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: _C.purpleGlow.withValues(alpha: 0.4),
                      blurRadius: 10)
                ]
              : [],
        ),
        child: Center(
          child: Text(label,
              style: _ts(
                  size: 13,
                  weight: FontWeight.w700,
                  color: active ? _C.purpleLight : _C.textSecondary)),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   text;
  const _InfoBanner(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: _ts(size: 12, color: _C.textSecondary))),
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
          isError
              ? Icons.error_outline_rounded
              : Icons.check_circle_rounded,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: _ts(size: 12, color: _C.textSecondary))),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(children: [
        Text(title,
            style: _ts(
                size: 10,
                weight: FontWeight.w800,
                color: _C.textMuted,
                letterSpacing: 1.2)),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  const _SectionTitle(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 6),
      Text(label,
          style: _ts(
              size: 11,
              weight: FontWeight.w800,
              color: _C.textSecondary,
              letterSpacing: 1.5)),
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
      child: Text(status.toUpperCase(),
          style: _ts(
              size: 9,
              weight: FontWeight.w800,
              color: color,
              letterSpacing: 0.8)),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
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
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.5 + 0.5 * _anim.value),
          boxShadow: [
            BoxShadow(
                color: widget.color.withValues(alpha: 0.5),
                blurRadius: 6 * _anim.value),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width, height;
  const _ShimmerBox({required this.width, required this.height});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
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
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: _C.surfaceElevated
              .withValues(alpha: 0.5 + 0.4 * _anim.value),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(
            color: _C.purple, strokeWidth: 2),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: _C.textMuted, size: 48),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: _ts(size: 13, color: _C.textMuted)),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: _C.live, size: 40),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: _ts(size: 13, color: _C.textSecondary)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────

Color _statusColor(String status) {
  switch (status) {
    case 'approved': return _C.approved;
    case 'rejected': return _C.rejected;
    default:         return _C.pending;
  }
}

String _formatDate(DateTime dt) {
  final now  = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1)   return '${diff.inMinutes}m ago';
  if (diff.inDays < 1)    return '${diff.inHours}h ago';
  if (diff.inDays < 7)    return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}