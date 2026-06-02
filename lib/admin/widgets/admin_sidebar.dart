// lib/admin/widgets/admin_sidebar.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Sidebar
// F2: Live badge counts for pending items in nav items
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../navigation/admin_nav_model.dart';
import '../auth/admin_auth_service.dart';
import '../theme/admin_theme.dart';

class AdminSidebar extends StatefulWidget {
  final AdminNavState navState;
  final User          adminUser;
  final bool          isCollapsed;
  final VoidCallback? onToggleCollapse;

  const AdminSidebar({
    super.key,
    required this.navState,
    required this.adminUser,
    required this.isCollapsed,
    this.onToggleCollapse,
  });

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSignOut() async {
    final confirmed = await _showSignOutDialog();
    if (!confirmed || !mounted) return;
    setState(() => _signingOut = true);
    await AdminAuthService.instance.signOut();
  }

  Future<bool> _showSignOutDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _SignOutDialog(),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.isCollapsed;
    final width     = collapsed ? 72.0 : 240.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      width: width,
      decoration: AdminDecorations.sidebar,
      child: Column(children: [
        _buildSidebarHeader(collapsed),
        Expanded(child: _buildNavItems(collapsed)),
        _buildSidebarFooter(collapsed),
      ]),
    );
  }

  Widget _buildSidebarHeader(bool collapsed) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) => Row(children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 18 : 16),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color:        AdminColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AdminColors.purple.withValues(alpha: 0.35 + 0.25 * _pulse.value),
                ),
                boxShadow: [BoxShadow(
                  color:      AdminColors.purple.withValues(alpha: 0.12 + 0.08 * _pulse.value),
                  blurRadius: 12 + 6 * _pulse.value,
                )],
              ),
              child: const Center(child: Icon(Icons.bolt_rounded, color: AdminColors.purple, size: 20)),
            ),
          ),
          if (!collapsed) ...[
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SHADOW STORM', style: AdminTextStyles.labelMedium.copyWith(
                    color: AdminColors.purple, letterSpacing: 1.5, fontSize: 10)),
                Text('Admin Panel', style: AdminTextStyles.titleSmall),
              ],
            )),
            GestureDetector(
              onTap: widget.onToggleCollapse,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.chevron_left_rounded, color: AdminColors.textMuted, size: 20),
              ),
            ),
          ],
          if (collapsed)
            Expanded(child: GestureDetector(
              onTap: widget.onToggleCollapse,
              child: Center(child: Icon(Icons.chevron_right_rounded, color: AdminColors.textMuted, size: 18)),
            )),
        ]),
      ),
    );
  }

  Widget _buildNavItems(bool collapsed) {
    return ListenableBuilder(
      listenable: widget.navState,
      builder: (_, _) => ListenableBuilder(
        listenable: widget.navState.badges,
        builder: (_, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          children: kAdminNavItems.map((item) {
            final isActive   = widget.navState.activeId == item.id;
            final badgeCount = widget.navState.badges.badgeFor(item.id);

            return Column(children: [
              if (item.isDividerBefore) ...[
                const SizedBox(height: 4),
                Divider(
                  color: AdminColors.border,
                  height: 1,
                  indent:    collapsed ? 8 : 12,
                  endIndent: collapsed ? 8 : 12,
                ),
                const SizedBox(height: 4),
              ],
              _NavTile(
                item:       item,
                isActive:   isActive,
                collapsed:  collapsed,
                badgeCount: badgeCount,
                onTap:      () => widget.navState.setActive(item.id),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(bool collapsed) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AdminColors.border)),
      ),
      padding: const EdgeInsets.all(10),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: collapsed
            ? _buildCollapsedFooter(widget.adminUser)
            : _buildExpandedFooter(widget.adminUser),
      ),
    );
  }

  Widget _buildCollapsedFooter(User user) {
    return Column(key: const ValueKey('collapsed'), children: [
      Tooltip(
        message: user.displayName ?? 'Admin',
        child: _buildAvatar(user, 36),
      ),
      const SizedBox(height: 8),
      Tooltip(
        message: 'Sign Out',
        child: GestureDetector(
          onTap: _handleSignOut,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        AdminColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: AdminColors.danger.withValues(alpha: 0.3)),
            ),
            child: _signingOut
                ? const Center(child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: AdminColors.danger, strokeWidth: 2)))
                : const Icon(Icons.logout_rounded, color: AdminColors.danger, size: 16),
          ),
        ),
      ),
    ]);
  }

  Widget _buildExpandedFooter(User user) {
    return Column(key: const ValueKey('expanded'), children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:        AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: AdminColors.border),
        ),
        child: Row(children: [
          _buildAvatar(user, 32),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName?.split(' ').first ?? 'Admin',
                  style: AdminTextStyles.titleSmall, overflow: TextOverflow.ellipsis),
              Text('Administrator',
                  style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.purple, fontSize: 10)),
            ],
          )),
          Container(width: 8, height: 8,
              decoration: BoxDecoration(
                shape:     BoxShape.circle,
                color:     AdminColors.success,
                boxShadow: [BoxShadow(color: AdminColors.success.withValues(alpha: 0.5), blurRadius: 6)],
              )),
        ]),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _handleSignOut,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:        AdminColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: AdminColors.danger.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _signingOut
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(color: AdminColors.danger, strokeWidth: 2))
                : const Icon(Icons.logout_rounded, color: AdminColors.danger, size: 14),
            const SizedBox(width: 7),
            Text(_signingOut ? 'Signing out...' : 'Sign Out',
                style: AdminTextStyles.labelMedium.copyWith(color: AdminColors.danger)),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildAvatar(User user, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape:  BoxShape.circle,
        color:  AdminColors.surfaceElevated,
        border: Border.all(color: AdminColors.border),
      ),
      child: user.photoURL != null
          ? ClipOval(child: Image.network(user.photoURL!, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(Icons.person_rounded, color: AdminColors.textMuted, size: size * 0.5)))
          : Icon(Icons.person_rounded, color: AdminColors.textMuted, size: size * 0.5),
    );
  }
}

// ─────────────────────────────────────────────
// NAV TILE — with badge count support
// ─────────────────────────────────────────────
class _NavTile extends StatefulWidget {
  final AdminNavItem item;
  final bool         isActive;
  final bool         collapsed;
  final String?      badgeCount;
  final VoidCallback onTap;

  const _NavTile({
    required this.item, required this.isActive, required this.collapsed,
    this.badgeCount, required this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item     = widget.item;
    final isActive = widget.isActive;
    final color    = item.accentColor ?? AdminColors.purple;

    return Tooltip(
      message:    widget.collapsed ? item.label : '',
      preferBelow: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed ? 10 : 12,
              vertical: 10,
            ),
            decoration: isActive
                ? BoxDecoration(
                    color:        color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: color.withValues(alpha: 0.35)),
                    boxShadow:    [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12)],
                  )
                : BoxDecoration(
                    color:        _hovered ? AdminColors.sidebarHover : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
            child: Row(
              mainAxisAlignment: widget.collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (!widget.collapsed)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 3,
                    height: isActive ? 18 : 0,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color:        color,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow:    [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)],
                    ),
                  ),

                // Icon with badge overlay for collapsed
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isActive ? item.iconActive : item.icon,
                      color: isActive ? color : _hovered ? AdminColors.textSecondary : AdminColors.textMuted,
                      size: 18,
                    ),
                    // Badge dot on icon in collapsed mode
                    if (widget.collapsed && widget.badgeCount != null)
                      Positioned(
                        right: -4, top: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color:        AdminColors.danger,
                            borderRadius: BorderRadius.circular(7),
                            border:       Border.all(color: AdminColors.sidebarBg, width: 1.5),
                          ),
                          child: Center(child: Text(
                            widget.badgeCount!.length > 2 ? '${widget.badgeCount!.substring(0,2)}+' : widget.badgeCount!,
                            style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w800),
                          )),
                        ),
                      ),
                  ],
                ),

                if (!widget.collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    item.label,
                    style: AdminTextStyles.sidebarItem.copyWith(
                      color: isActive ? color : _hovered ? AdminColors.textSecondary : AdminColors.textMuted,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )),

                  // Badge count pill (expanded mode)
                  if (widget.badgeCount != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:        AdminColors.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.badgeCount!.length > 3 ? '99+' : widget.badgeCount!,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),

                  // Original item badge (static string like "NEW")
                  if (widget.badgeCount == null && item.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:        color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(item.badge!,
                          style: AdminTextStyles.labelSmall.copyWith(color: color)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SIGN OUT DIALOG
// ─────────────────────────────────────────────
class _SignOutDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color:        AdminColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: AdminColors.borderBright),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 40)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color:  AdminColors.danger.withValues(alpha: 0.1),
              shape:  BoxShape.circle,
              border: Border.all(color: AdminColors.danger.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.logout_rounded, color: AdminColors.danger, size: 26),
          ),
          const SizedBox(height: 16),
          Text('Sign Out', style: AdminTextStyles.titleLarge),
          const SizedBox(height: 8),
          Text('Are you sure you want to sign out of the admin control center?',
              style: AdminTextStyles.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color:        AdminColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: AdminColors.border),
                ),
                child: Center(child: Text('Cancel',
                    style: AdminTextStyles.titleSmall.copyWith(color: AdminColors.textSecondary))),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient:     AdminGradients.dangerGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                    color: AdminColors.danger.withValues(alpha: 0.35),
                    blurRadius: 12, offset: const Offset(0, 4),
                  )],
                ),
                child: Center(child: Text('Sign Out',
                    style: AdminTextStyles.titleSmall.copyWith(color: Colors.white))),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}