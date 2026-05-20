// lib/admin/pages/admin_settings_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Settings Page
// Phase 5: Realtime config/admin_settings management
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/admin_page_container.dart';
import '../widgets/admin_components.dart';
import '../theme/admin_theme.dart';
import '../services/admin_settings_service.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage>
    with TickerProviderStateMixin {
  final AdminSettingsService _service = AdminSettingsService.instance;

  late TabController _tabCtrl;

  // Loading states
  bool _savingPayment      = false;
  bool _togglingMaint      = false;
  bool _togglingFreeze     = false;
  bool _savingSecurity     = false;
  bool _savingPlatform     = false;
  bool _testingWebhook     = false;

  // Payment form
  final _upiIdCtrl         = TextEditingController();
  final _payeeNameCtrl     = TextEditingController();
  double _minDeposit       = 100;
  double _maxDeposit       = 10000;
  double _minWithdrawal    = 100;
  double _maxWithdrawal    = 5000;

  // Security form
  int  _sessionTimeout     = 60;
  bool _require2FA         = false;

  // Platform form
  final _supportEmailCtrl  = TextEditingController();
  final _discordCtrl       = TextEditingController();
  final _versionCtrl       = TextEditingController();

  // Maintenance message
  final _maintMsgCtrl      = TextEditingController();

  // Wallet freeze reason
  final _freezeReasonCtrl  = TextEditingController();

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _upiIdCtrl.dispose();
    _payeeNameCtrl.dispose();
    _supportEmailCtrl.dispose();
    _discordCtrl.dispose();
    _versionCtrl.dispose();
    _maintMsgCtrl.dispose();
    _freezeReasonCtrl.dispose();
    super.dispose();
  }

  void _populateFromSettings(AdminSettings s) {
    if (_initialized) return;
    _initialized = true;
    _upiIdCtrl.text        = s.upiId;
    _payeeNameCtrl.text    = s.upiPayeeName;
    _minDeposit            = s.minDepositAmount;
    _maxDeposit            = s.maxDepositAmount;
    _minWithdrawal         = s.minWithdrawalAmount;
    _maxWithdrawal         = s.maxWithdrawalAmount;
    _sessionTimeout        = s.sessionTimeoutMinutes;
    _require2FA            = s.require2FA;
    _supportEmailCtrl.text = s.supportEmail;
    _discordCtrl.text      = s.discordInvite ?? '';
    _versionCtrl.text      = s.appVersion;
    _maintMsgCtrl.text     = s.maintenanceMessage;
    _freezeReasonCtrl.text = s.walletFreezeReason;
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final color = isError ? AdminColors.danger : AdminColors.success;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AdminTextStyles.bodyMedium.copyWith(color: color)),
      backgroundColor: AdminColors.surfaceCard,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
    ));
  }

  // ─── Payment save ──────────────────────────
  Future<void> _savePayment() async {
    setState(() => _savingPayment = true);
    try {
      await _service.updatePaymentSettings(
        upiId:          _upiIdCtrl.text.trim(),
        upiPayeeName:   _payeeNameCtrl.text.trim(),
        minDeposit:     _minDeposit,
        maxDeposit:     _maxDeposit,
        minWithdrawal:  _minWithdrawal,
        maxWithdrawal:  _maxWithdrawal,
      );
      _snack('Payment settings saved.');
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingPayment = false);
    }
  }

  // ─── Maintenance toggle ────────────────────
  Future<void> _toggleMaintenance(bool enabled, AdminSettings current) async {
    if (enabled) {
      // Show confirmation
      final ok = await AdminConfirmDialog.show(
        context,
        title:        'Enable Maintenance Mode',
        message:      'This will block ALL player actions on the platform. Existing sessions will see a maintenance screen.\n\nAre you sure?',
        confirmLabel: 'Enable Maintenance',
        confirmColor: AdminColors.danger,
        confirmIcon:  Icons.construction_rounded,
      );
      if (ok != true) return;
    }
    setState(() => _togglingMaint = true);
    try {
      await _service.setMaintenanceMode(enabled,
          message: _maintMsgCtrl.text.trim().isEmpty
              ? null : _maintMsgCtrl.text.trim());
      _snack(enabled ? '⚠️ Maintenance mode enabled.' : '✓ Maintenance mode disabled.');
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _togglingMaint = false);
    }
  }

  // ─── Wallet freeze toggle ──────────────────
  Future<void> _toggleFreeze(bool frozen) async {
    if (frozen) {
      final ok = await AdminConfirmDialog.show(
        context,
        title:        'Freeze All Wallets',
        message:      'This will BLOCK all deposit and withdrawal processing globally. Players will not be able to transact.\n\nContinue?',
        confirmLabel: 'Freeze Wallets',
        confirmColor: AdminColors.warning,
        confirmIcon:  Icons.ac_unit_rounded,
      );
      if (ok != true) return;
    }
    setState(() => _togglingFreeze = true);
    try {
      await _service.setWalletFreeze(frozen,
          reason: _freezeReasonCtrl.text.trim().isEmpty
              ? null : _freezeReasonCtrl.text.trim());
      _snack(frozen ? '❄️ All wallets frozen.' : '✓ Wallets unfrozen.');
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _togglingFreeze = false);
    }
  }

  // ─── Security save ─────────────────────────
  Future<void> _saveSecurity() async {
    setState(() => _savingSecurity = true);
    try {
      await _service.updateSecuritySettings(
        sessionTimeoutMinutes: _sessionTimeout,
        require2FA:            _require2FA,
      );
      _snack('Security settings saved.');
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingSecurity = false);
    }
  }

  // ─── Platform save ─────────────────────────
  Future<void> _savePlatform() async {
    setState(() => _savingPlatform = true);
    try {
      await _service.updatePlatformInfo(
        supportEmail:  _supportEmailCtrl.text.trim(),
        discordInvite: _discordCtrl.text.trim().isEmpty
            ? null : _discordCtrl.text.trim(),
        appVersion:    _versionCtrl.text.trim(),
      );
      _snack('Platform info saved.');
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingPlatform = false);
    }
  }

  // ─── Test webhook ──────────────────────────
  Future<void> _testWebhook() async {
    setState(() => _testingWebhook = true);
    try {
      final ok = await _service.sendTestWebhook();
      _snack(ok ? '✓ Webhook sent successfully!' : 'Webhook failed — check URL.',
          isError: !ok);
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testingWebhook = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminSettings>(
      stream: _service.settingsStream(),
      builder: (context, snap) {
        final settings = snap.data ?? const AdminSettings();
        if (snap.data != null) _populateFromSettings(snap.data!);

        return AdminPageContainer(
          title:    'Admin Settings',
          subtitle: 'Platform configuration — realtime sync',
          actions: [
            AdminActionButton(
              label:    'Test Webhook',
              icon:     _testingWebhook
                  ? Icons.hourglass_empty_rounded
                  : Icons.send_rounded,
              color:    AdminColors.info,
              outlined: true,
              onTap:    _testingWebhook ? null : _testWebhook,
            ),
          ],
          child: Column(
            children: [
              // Maintenance + Freeze banners
              if (settings.maintenanceMode) ...[
                AdminAlertBanner(
                  message: '⚠️ MAINTENANCE MODE IS ACTIVE — All player actions are blocked.',
                  color:   AdminColors.danger,
                  icon:    Icons.construction_rounded,
                ),
                const SizedBox(height: 8),
              ],
              if (settings.walletFrozen) ...[
                AdminAlertBanner(
                  message: '❄️ WALLETS ARE GLOBALLY FROZEN — All deposits and withdrawals are paused.',
                  color:   AdminColors.warning,
                  icon:    Icons.ac_unit_rounded,
                ),
                const SizedBox(height: 8),
              ],

              // Tab bar
              Container(
                decoration: BoxDecoration(
                  color:        AdminColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: AdminColors.border),
                ),
                child: TabBar(
                  controller:         _tabCtrl,
                  isScrollable:       true,
                  labelColor:         AdminColors.purple,
                  unselectedLabelColor: AdminColors.textMuted,
                  indicatorColor:     AdminColors.purple,
                  indicatorSize:      TabBarIndicatorSize.tab,
                  labelStyle:         AdminTextStyles.labelMedium.copyWith(
                      fontSize: 10, letterSpacing: 1),
                  tabs: const [
                    Tab(text: 'PAYMENT'),
                    Tab(text: 'MAINTENANCE'),
                    Tab(text: 'SECURITY'),
                    Tab(text: 'ADMINS'),
                    Tab(text: 'PLATFORM'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tab content (not using TabBarView to avoid layout issues in scroll)
              ListenableBuilder(
                listenable: _tabCtrl,
                builder: (_, _) {
                  return switch (_tabCtrl.index) {
                    0 => _buildPaymentTab(),
                    1 => _buildMaintenanceTab(settings),
                    2 => _buildSecurityTab(settings),
                    3 => _buildAdminsTab(),
                    4 => _buildPlatformTab(),
                    _ => const SizedBox.shrink(),
                  };
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  // PAYMENT TAB
  // ═══════════════════════════════════════════
  Widget _buildPaymentTab() {
    return AdminSectionCard(
      title:     'PAYMENT SETTINGS',
      titleIcon: Icons.payment_rounded,
      titleColor: AdminColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminFormField(
            label:       'UPI ID',
            hint:        'name@upi',
            controller:  _upiIdCtrl,
            prefixIcon:  Icons.qr_code_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          AdminFormField(
            label:      'Payee Name',
            hint:       'Displayed to players on payment screen',
            controller: _payeeNameCtrl,
            prefixIcon: Icons.person_rounded,
          ),
          const SizedBox(height: 20),

          AdminSectionHeader(
            label: 'DEPOSIT LIMITS',
            color: AdminColors.success,
            icon:  Icons.add_circle_outline_rounded,
          ),
          const SizedBox(height: 12),
          _AmountSlider(
            label:    'Minimum Deposit',
            value:    _minDeposit,
            min:      10,
            max:      500,
            color:    AdminColors.success,
            onChanged: (v) => setState(() => _minDeposit = v),
          ),
          const SizedBox(height: 12),
          _AmountSlider(
            label:    'Maximum Deposit',
            value:    _maxDeposit,
            min:      1000,
            max:      50000,
            color:    AdminColors.success,
            onChanged: (v) => setState(() => _maxDeposit = v),
          ),

          const SizedBox(height: 20),

          AdminSectionHeader(
            label: 'WITHDRAWAL LIMITS',
            color: AdminColors.danger,
            icon:  Icons.remove_circle_outline_rounded,
          ),
          const SizedBox(height: 12),
          _AmountSlider(
            label:    'Minimum Withdrawal',
            value:    _minWithdrawal,
            min:      10,
            max:      500,
            color:    AdminColors.danger,
            onChanged: (v) => setState(() => _minWithdrawal = v),
          ),
          const SizedBox(height: 12),
          _AmountSlider(
            label:    'Maximum Withdrawal',
            value:    _maxWithdrawal,
            min:      500,
            max:      25000,
            color:    AdminColors.danger,
            onChanged: (v) => setState(() => _maxWithdrawal = v),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AdminActionButton(
              label:  _savingPayment ? 'Saving…' : 'Save Payment Settings',
              icon:   Icons.save_rounded,
              color:  AdminColors.success,
              onTap:  _savingPayment ? null : _savePayment,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // MAINTENANCE TAB
  // ═══════════════════════════════════════════
  Widget _buildMaintenanceTab(AdminSettings settings) {
    return Column(
      children: [
        // Maintenance toggle (large warning card)
        AdminToggleCard(
          title:       'Maintenance Mode',
          subtitle:    'Block all player actions platform-wide immediately.',
          icon:        Icons.construction_rounded,
          activeColor: AdminColors.danger,
          value:       settings.maintenanceMode,
          loading:     _togglingMaint,
          isWarning:   true,
          onChanged:   (v) => _toggleMaintenance(v, settings),
        ),
        const SizedBox(height: 16),

        // Freeze toggle
        AdminToggleCard(
          title:       'Wallet Freeze',
          subtitle:    'Pause all deposit and withdrawal processing globally.',
          icon:        Icons.ac_unit_rounded,
          activeColor: AdminColors.warning,
          value:       settings.walletFrozen,
          loading:     _togglingFreeze,
          isWarning:   true,
          onChanged:   _toggleFreeze,
        ),
        const SizedBox(height: 16),

        AdminSectionCard(
          title:     'MESSAGES',
          titleIcon: Icons.message_rounded,
          child: Column(
            children: [
              AdminFormField(
                label:      'Maintenance Message',
                hint:       'Shown to players during maintenance…',
                controller: _maintMsgCtrl,
                maxLines:   3,
                prefixIcon: Icons.info_outline_rounded,
              ),
              const SizedBox(height: 14),
              AdminFormField(
                label:      'Wallet Freeze Reason',
                hint:       'Internal note for why wallets are frozen…',
                controller: _freezeReasonCtrl,
                maxLines:   2,
                prefixIcon: Icons.notes_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Quick danger actions
        AdminSectionCard(
          title:     'QUICK DANGER ACTIONS',
          titleIcon: Icons.warning_rounded,
          titleColor: AdminColors.danger,
          child: Column(
            children: [
              _DangerAction(
                label:    'Enable Maintenance Mode',
                sublabel: 'Immediately block all player actions',
                icon:     Icons.construction_rounded,
                color:    AdminColors.danger,
                active:   settings.maintenanceMode,
                onTap:    () => _toggleMaintenance(!settings.maintenanceMode, settings),
              ),
              const SizedBox(height: 8),
              _DangerAction(
                label:    'Freeze All Wallets',
                sublabel: 'Block all deposit & withdrawal processing',
                icon:     Icons.ac_unit_rounded,
                color:    AdminColors.warning,
                active:   settings.walletFrozen,
                onTap:    () => _toggleFreeze(!settings.walletFrozen),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // SECURITY TAB
  // ═══════════════════════════════════════════
  Widget _buildSecurityTab(AdminSettings settings) {
    return AdminSectionCard(
      title:     'SECURITY CONTROLS',
      titleIcon: Icons.security_rounded,
      titleColor: AdminColors.purple,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            label: 'SESSION TIMEOUT',
            color: AdminColors.purple,
            icon:  Icons.timer_rounded,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              (label: '15 min', value: 15),
              (label: '30 min', value: 30),
              (label: '1 hour', value: 60),
              (label: '4 hours', value: 240),
              (label: 'Never',  value: 0),
            ].map((opt) => GestureDetector(
              onTap: () => setState(() => _sessionTimeout = opt.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _sessionTimeout == opt.value
                      ? AdminColors.purple.withValues(alpha: 0.15)
                      : AdminColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _sessionTimeout == opt.value
                        ? AdminColors.purple.withValues(alpha: 0.5)
                        : AdminColors.border,
                    width: _sessionTimeout == opt.value ? 1.5 : 1,
                  ),
                ),
                child: Text(opt.label,
                    style: AdminTextStyles.labelMedium.copyWith(
                        color: _sessionTimeout == opt.value
                            ? AdminColors.purple
                            : AdminColors.textMuted)),
              ),
            )).toList(),
          ),

          const SizedBox(height: 24),
          AdminSectionHeader(
            label: 'TWO-FACTOR AUTH',
            color: AdminColors.info,
            icon:  Icons.verified_user_rounded,
          ),
          const SizedBox(height: 12),
          AdminToggleCard(
            title:       'Require 2FA for Admins',
            subtitle:    'Coming soon — full 2FA implementation in future phase.',
            icon:        Icons.smartphone_rounded,
            activeColor: AdminColors.info,
            value:       _require2FA,
            onChanged:   (v) => setState(() => _require2FA = v),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AdminActionButton(
              label:  _savingSecurity ? 'Saving…' : 'Save Security Settings',
              icon:   Icons.security_rounded,
              color:  AdminColors.purple,
              onTap:  _savingSecurity ? null : _saveSecurity,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ADMINS TAB
  // ═══════════════════════════════════════════
  Widget _buildAdminsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isAdmin', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final admins = snap.data?.docs ?? [];

        return AdminSectionCard(
          title:     'ADMIN ACCOUNTS',
          titleIcon: Icons.shield_rounded,
          titleColor: AdminColors.purple,
          titleActions: [
            AdminBadge(
              label: '${admins.length} admins',
              color: AdminColors.purple,
            ),
          ],
          child: admins.isEmpty
              ? const AdminEmptyState(
                  icon:     Icons.shield_outlined,
                  title:    'No admins found',
                  subtitle: 'Promote users from the Users page.',
                  color:    AdminColors.purple,
                )
              : Column(
                  children: admins.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    return _AdminAccountRow(
                      uid:    doc.id,
                      name:   (d['name']  as String?) ?? 'Unknown',
                      email:  (d['email'] as String?) ?? '',
                      onDemote: () async {
                        final ok = await AdminConfirmDialog.show(
                          context,
                          title:        'Demote Admin',
                          message:      'Remove admin privileges from "${d['name']}"?',
                          confirmLabel: 'Demote',
                          confirmColor: AdminColors.warning,
                          confirmIcon:  Icons.remove_moderator_rounded,
                        );
                        if (ok != true) return;
                        try {
                          await _service.setAdminRole(
                              doc.id, (d['name'] as String?) ?? 'Unknown', false);
                          _snack('Admin demoted.');
                        } catch (e) {
                          _snack('Error: $e', isError: true);
                        }
                      },
                    );
                  }).toList(),
                ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  // PLATFORM TAB
  // ═══════════════════════════════════════════
  Widget _buildPlatformTab() {
    return AdminSectionCard(
      title:     'PLATFORM INFORMATION',
      titleIcon: Icons.info_outline_rounded,
      titleColor: AdminColors.info,
      child: Column(
        children: [
          AdminFormField(
            label:       'Support Email',
            hint:        'support@shadowstorm.gg',
            controller:  _supportEmailCtrl,
            prefixIcon:  Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          AdminFormField(
            label:      'Discord Invite Link',
            hint:       'https://discord.gg/…',
            controller: _discordCtrl,
            prefixIcon: Icons.discord_rounded,
          ),
          const SizedBox(height: 14),
          AdminFormField(
            label:       'App Version',
            hint:        '1.0.0',
            controller:  _versionCtrl,
            prefixIcon:  Icons.tag_rounded,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AdminActionButton(
              label:  _savingPlatform ? 'Saving…' : 'Save Platform Info',
              icon:   Icons.save_rounded,
              color:  AdminColors.info,
              onTap:  _savingPlatform ? null : _savePlatform,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// AMOUNT SLIDER
// ═════════════════════════════════════════════
class _AmountSlider extends StatelessWidget {
  final String   label;
  final double   value;
  final double   min;
  final double   max;
  final Color    color;
  final void Function(double) onChanged;

  const _AmountSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: AdminTextStyles.bodyMedium
                    .copyWith(color: AdminColors.textSecondary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text('₹${value.toStringAsFixed(0)}',
                style: AdminTextStyles.titleSmall.copyWith(color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor:   color,
            inactiveTrackColor: color.withValues(alpha: 0.12),
            thumbColor:         color,
            overlayColor:       color.withValues(alpha: 0.12),
          ),
          child: Slider(
            value:    value.clamp(min, max),
            min:      min,
            max:      max,
            divisions: ((max - min) / 100).round().clamp(1, 100),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// DANGER ACTION ROW
// ═════════════════════════════════════════════
class _DangerAction extends StatelessWidget {
  final String   label;
  final String   sublabel;
  final IconData icon;
  final Color    color;
  final bool     active;
  final VoidCallback onTap;

  const _DangerAction({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        active
              ? color.withValues(alpha: 0.08)
              : AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(
            color: active ? color.withValues(alpha: 0.4) : AdminColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color:        color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AdminTextStyles.titleSmall
                      .copyWith(color: active ? color : AdminColors.textPrimary)),
                  Text(sublabel, style: AdminTextStyles.bodySmall),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color:        color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border:       Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(
                active ? 'ACTIVE' : 'ACTIVATE',
                style: AdminTextStyles.labelSmall.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ADMIN ACCOUNT ROW
// ═════════════════════════════════════════════
class _AdminAccountRow extends StatelessWidget {
  final String   uid;
  final String   name;
  final String   email;
  final VoidCallback onDemote;

  const _AdminAccountRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.onDemote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape:  BoxShape.circle,
              color:  AdminColors.purple.withValues(alpha: 0.12),
              border: Border.all(color: AdminColors.purple.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.shield_rounded,
                color: AdminColors.purple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AdminTextStyles.titleSmall),
                Text(email,
                    style: AdminTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDemote,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color:        AdminColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
                border:       Border.all(
                    color: AdminColors.warning.withValues(alpha: 0.4)),
              ),
              child: Text('DEMOTE',
                  style: AdminTextStyles.labelSmall
                      .copyWith(color: AdminColors.warning)),
            ),
          ),
        ],
      ),
    );
  }
}