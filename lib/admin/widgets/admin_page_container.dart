// lib/admin/widgets/admin_page_container.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Page Container
// Reusable wrapper for all admin pages
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/admin_theme.dart';

class AdminPageContainer extends StatelessWidget {
  final String        title;
  final String?       subtitle;
  final List<Widget>? actions;
  final Widget        child;
  final bool          scrollable;
  final EdgeInsets?   padding;

  const AdminPageContainer({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    required this.child,
    this.scrollable = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageHeader(),
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: padding ?? const EdgeInsets.all(24),
                  child: child,
                )
              : Padding(
                  padding: padding ?? const EdgeInsets.all(24),
                  child: child,
                ),
        ),
      ],
    );
  }

  Widget _buildPageHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AdminColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AdminTextStyles.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: AdminTextStyles.bodyMedium),
                ],
              ],
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions!
                  .map((a) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: a,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN STAT CARD (reusable)
// ─────────────────────────────────────────────
class AdminStatCard extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;
  final String?  subLabel;
  final Widget?  trend;

  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subLabel,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
        boxShadow: AdminShadows.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              ?trend,
            ],
          ),

          const SizedBox(height: 16),

          Text(
            value,
            style: AdminTextStyles.displayMedium.copyWith(color: color),
          ),

          const SizedBox(height: 4),

          Text(label, style: AdminTextStyles.labelLarge),

          if (subLabel != null) ...[
            const SizedBox(height: 2),
            Text(subLabel!, style: AdminTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN SECTION CARD
// ─────────────────────────────────────────────
class AdminSectionCard extends StatelessWidget {
  final String?       title;
  final IconData?     titleIcon;
  final Color?        titleColor;
  final List<Widget>? titleActions;
  final Widget        child;
  final EdgeInsets?   contentPadding;
  final bool          glowing;

  const AdminSectionCard({
    super.key,
    this.title,
    this.titleIcon,
    this.titleColor,
    this.titleActions,
    required this.child,
    this.contentPadding,
    this.glowing = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = titleColor ?? AdminColors.purple;

    return Container(
      decoration: AdminDecorations.card(glowing: glowing),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AdminColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    if (titleIcon != null) ...[
                      Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(titleIcon!, color: color, size: 16),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      title!,
                      style: AdminTextStyles.labelLarge.copyWith(
                        color: AdminColors.textSecondary,
                        letterSpacing: 1.5,
                        fontSize: 11,
                      ),
                    ),
                    if (titleActions != null) ...[
                      const Spacer(),
                      ...titleActions!,
                    ],
                  ],
                ),
              ),
            ],
            Padding(
              padding: contentPadding ?? const EdgeInsets.all(18),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN BADGE (status pill)
// ─────────────────────────────────────────────
class AdminBadge extends StatelessWidget {
  final String  label;
  final Color   color;
  final bool    glowing;

  const AdminBadge({
    super.key,
    required this.label,
    required this.color,
    this.glowing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: glowing
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Text(
        label.toUpperCase(),
        style: AdminTextStyles.labelSmall.copyWith(
          color: color,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN ACTION BUTTON
// ─────────────────────────────────────────────
class AdminActionButton extends StatefulWidget {
  final String   label;
  final IconData icon;
  final Color?   color;
  final VoidCallback? onTap;
  final bool     outlined;

  const AdminActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
    this.outlined = false,
  });

  @override
  State<AdminActionButton> createState() => _AdminActionButtonState();
}

class _AdminActionButtonState extends State<AdminActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color   = widget.color ?? AdminColors.purple;
    final enabled = widget.onTap != null;

    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) { setState(() => _pressed = false); widget.onTap?.call(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: widget.outlined
              ? null
              : LinearGradient(
                  colors: [color, color.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: widget.outlined
              ? color.withValues(alpha: 0.08)
              : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.outlined
                ? color.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          boxShadow: widget.outlined || !enabled
              ? null
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: 15,
              color: widget.outlined ? color : Colors.white,
            ),
            const SizedBox(width: 7),
            Text(
              widget.label,
              style: AdminTextStyles.labelLarge.copyWith(
                color: widget.outlined ? color : Colors.white,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}