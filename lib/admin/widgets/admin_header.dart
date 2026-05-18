// lib/admin/widgets/admin_header.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Top Header
// Desktop-first header bar with breadcrumb + actions
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../navigation/admin_nav_model.dart';
import '../theme/admin_theme.dart';

class AdminHeader extends StatefulWidget {
  final AdminNavState navState;
  final User          adminUser;
  final bool          sidebarCollapsed;
  final VoidCallback? onToggleSidebar;

  const AdminHeader({
    super.key,
    required this.navState,
    required this.adminUser,
    required this.sidebarCollapsed,
    this.onToggleSidebar,
  });

  @override
  State<AdminHeader> createState() => _AdminHeaderState();
}

class _AdminHeaderState extends State<AdminHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: AdminDecorations.header,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            _buildLeftSection(),
            const Spacer(),
            _buildRightSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSection() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sidebar toggle (mobile / collapsed)
        if (widget.sidebarCollapsed)
          GestureDetector(
            onTap: widget.onToggleSidebar,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AdminColors.surfaceCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.border),
              ),
              child: const Icon(
                Icons.menu_rounded,
                color: AdminColors.textSecondary,
                size: 18,
              ),
            ),
          ),

        if (widget.sidebarCollapsed) const SizedBox(width: 14),

        // Breadcrumb
        ListenableBuilder(
          listenable: widget.navState,
          builder: (_, _) => _Breadcrumb(
            activeItem: widget.navState.activeItem,
          ),
        ),
      ],
    );
  }

  Widget _buildRightSection() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live status indicator
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AdminColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AdminColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdminColors.success.withValues(
                        alpha: 0.6 + 0.4 * _pulse.value),
                    boxShadow: [
                      BoxShadow(
                        color: AdminColors.success.withValues(alpha: 0.5),
                        blurRadius: 6 * _pulse.value,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'SYSTEM LIVE',
                  style: AdminTextStyles.labelSmall.copyWith(
                    color: AdminColors.success,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Notification bell (placeholder)
        _HeaderIconButton(
          icon: Icons.notifications_outlined,
          onTap: () {},
          badge: '3',
        ),

        const SizedBox(width: 8),

        // Admin profile chip
        _AdminProfileChip(user: widget.adminUser),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// BREADCRUMB
// ─────────────────────────────────────────────
class _Breadcrumb extends StatelessWidget {
  final AdminNavItem activeItem;

  const _Breadcrumb({required this.activeItem});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Home crumb
        Text(
          'Admin',
          style: AdminTextStyles.bodyMedium.copyWith(
            color: AdminColors.textMuted,
            fontSize: 13,
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            Icons.chevron_right_rounded,
            color: AdminColors.textMuted,
            size: 16,
          ),
        ),

        // Active crumb
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activeItem.iconActive,
              color: activeItem.accentColor ?? AdminColors.purple,
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              activeItem.label,
              style: AdminTextStyles.titleSmall.copyWith(
                color: activeItem.accentColor ?? AdminColors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// HEADER ICON BUTTON
// ─────────────────────────────────────────────
class _HeaderIconButton extends StatefulWidget {
  final IconData  icon;
  final VoidCallback onTap;
  final String?   badge;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.badge,
  });

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _hovered
                    ? AdminColors.surfaceElevated
                    : AdminColors.surfaceCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hovered
                      ? AdminColors.borderBright
                      : AdminColors.border,
                ),
              ),
              child: Icon(
                widget.icon,
                color: _hovered
                    ? AdminColors.textPrimary
                    : AdminColors.textSecondary,
                size: 18,
              ),
            ),

            if (widget.badge != null)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AdminColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AdminColors.background,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN PROFILE CHIP
// ─────────────────────────────────────────────
class _AdminProfileChip extends StatefulWidget {
  final User user;
  const _AdminProfileChip({required this.user});

  @override
  State<_AdminProfileChip> createState() => _AdminProfileChipState();
}

class _AdminProfileChipState extends State<_AdminProfileChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _hovered
              ? AdminColors.surfaceElevated
              : AdminColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered ? AdminColors.borderBright : AdminColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AdminColors.purple.withValues(alpha: 0.5),
                ),
              ),
              child: user.photoURL != null
                  ? ClipOval(
                      child: Image.network(
                        user.photoURL!,
                        width: 26,
                        height: 26,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.person_rounded,
                          color: AdminColors.textMuted,
                          size: 14,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.person_rounded,
                      color: AdminColors.textMuted,
                      size: 14,
                    ),
            ),

            const SizedBox(width: 8),

            Text(
              user.displayName?.split(' ').first ?? 'Admin',
              style: AdminTextStyles.titleSmall.copyWith(fontSize: 12),
            ),

            const SizedBox(width: 6),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AdminColors.purple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'ADMIN',
                style: AdminTextStyles.labelSmall.copyWith(
                  color: AdminColors.purple,
                  fontSize: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}