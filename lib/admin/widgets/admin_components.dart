// lib/admin/widgets/admin_components.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Shared Components
// Phase 5: Extracted reusable widgets (dialog headers/footers, form inputs, chips)
// Import this instead of duplicating in individual pages.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/admin_theme.dart';

// ═════════════════════════════════════════════
// DIALOG HEADER
// Standard header for all admin dialogs
// ═════════════════════════════════════════════
class AdminDialogHeader extends StatelessWidget {
  final String   title;
  final IconData icon;
  final Color    color;
  final String?  subtitle;

  const AdminDialogHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(color: AdminColors.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AdminTextStyles.titleMedium.copyWith(color: AdminColors.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AdminTextStyles.bodySmall),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color:        AdminColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: AdminColors.border),
              ),
              child: const Icon(Icons.close_rounded,
                  color: AdminColors.textMuted, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// DIALOG FOOTER
// Standard footer with action buttons
// ═════════════════════════════════════════════
class AdminDialogFooter extends StatelessWidget {
  final String    cancelLabel;
  final String    confirmLabel;
  final IconData  confirmIcon;
  final Color     confirmColor;
  final VoidCallback? onConfirm;
  final bool      loading;
  final bool      danger;

  const AdminDialogFooter({
    super.key,
    this.cancelLabel   = 'Cancel',
    required this.confirmLabel,
    required this.confirmIcon,
    this.confirmColor  = AdminColors.purple,
    this.onConfirm,
    this.loading       = false,
    this.danger        = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color:        AdminColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: AdminColors.border),
                ),
                child: Center(
                  child: Text(cancelLabel,
                      style: AdminTextStyles.labelLarge.copyWith(
                          color: AdminColors.textSecondary)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: loading ? null : onConfirm,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      confirmColor,
                      confirmColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color:      confirmColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset:     const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(confirmIcon, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(confirmLabel,
                                style: AdminTextStyles.labelLarge.copyWith(
                                    color: Colors.white)),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// DIALOG CONTAINER
// Standard dialog wrapper
// ═════════════════════════════════════════════
class AdminDialogContainer extends StatelessWidget {
  final Widget  child;
  final double  maxWidth;

  const AdminDialogContainer({
    super.key,
    required this.child,
    this.maxWidth = 480,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    double maxWidth = 480,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => AdminDialogContainer(
        maxWidth: maxWidth,
        child: child,
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ADMIN FORM FIELD
// Standard styled text input
// ═════════════════════════════════════════════
class AdminFormField extends StatelessWidget {
  final String            label;
  final String?           hint;
  final TextEditingController? controller;
  final String?           initialValue;
  final IconData?         prefixIcon;
  final Widget?           suffix;
  final TextInputType?    keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool              obscureText;
  final int               maxLines;
  final String?           Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool              readOnly;
  final Color?            borderColor;

  const AdminFormField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.maxLines    = 1,
    this.validator,
    this.onChanged,
    this.readOnly    = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AdminTextStyles.labelMedium.copyWith(
                color: AdminColors.textSecondary, letterSpacing: 1)),
        const SizedBox(height: 6),
        TextFormField(
          controller:        controller,
          initialValue:      controller == null ? initialValue : null,
          keyboardType:      keyboardType,
          inputFormatters:   inputFormatters,
          obscureText:       obscureText,
          maxLines:          maxLines,
          readOnly:          readOnly,
          validator:         validator,
          onChanged:         onChanged,
          style: AdminTextStyles.bodyMedium.copyWith(
              color: AdminColors.textPrimary),
          decoration: InputDecoration(
            hintText:  hint,
            hintStyle: AdminTextStyles.bodySmall,
            filled:    true,
            fillColor: AdminColors.surfaceElevated,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: AdminColors.textMuted, size: 18)
                : null,
            suffix: suffix,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: borderColor ?? AdminColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: borderColor ?? AdminColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AdminColors.purple),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AdminColors.danger),
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// SECTION HEADER (for settings sections)
// ═════════════════════════════════════════════
class AdminSectionHeader extends StatelessWidget {
  final String   label;
  final Color    color;
  final IconData? icon;

  const AdminSectionHeader({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(
            color:        color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        if (icon != null) ...[
          Icon(icon!, color: color, size: 16),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: AdminTextStyles.labelLarge.copyWith(
              color: AdminColors.textSecondary, letterSpacing: 2),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// STAT CHIP (small inline stat)
// ═════════════════════════════════════════════
class AdminStatChip extends StatelessWidget {
  final String   label;
  final String   value;
  final Color    color;
  final IconData? icon;

  const AdminStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon!, color: color, size: 14),
            const SizedBox(height: 4),
          ],
          Text(value,
              style: AdminTextStyles.titleSmall.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(label, style: AdminTextStyles.bodySmall),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// CONFIRMATION DIALOG
// Standard destructive action confirmation
// ═════════════════════════════════════════════
class AdminConfirmDialog extends StatelessWidget {
  final String   title;
  final String   message;
  final String   confirmLabel;
  final Color    confirmColor;
  final IconData confirmIcon;
  final bool     loading;
  final VoidCallback? onConfirm;

  const AdminConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel  = 'Confirm',
    this.confirmColor  = AdminColors.danger,
    this.confirmIcon   = Icons.warning_rounded,
    this.loading       = false,
    this.onConfirm,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String   confirmLabel = 'Confirm',
    Color    confirmColor = AdminColors.danger,
    IconData confirmIcon  = Icons.warning_rounded,
  }) {
    return AdminDialogContainer.show<bool>(
      context:  context,
      maxWidth: 400,
      child: _ConfirmDialogContent(
        title:        title,
        message:      message,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        confirmIcon:  confirmIcon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ConfirmDialogContent(
      title:        title,
      message:      message,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      confirmIcon:  confirmIcon,
    );
  }
}

class _ConfirmDialogContent extends StatelessWidget {
  final String   title;
  final String   message;
  final String   confirmLabel;
  final Color    confirmColor;
  final IconData confirmIcon;

  const _ConfirmDialogContent({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    required this.confirmIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminDialogHeader(
          title:    title,
          icon:     confirmIcon,
          color:    confirmColor,
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message,
              style: AdminTextStyles.bodyMedium,
              textAlign: TextAlign.center),
        ),
        AdminDialogFooter(
          confirmLabel: confirmLabel,
          confirmIcon:  confirmIcon,
          confirmColor: confirmColor,
          danger:       true,
          onConfirm:    () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// LOADING SHIMMER TILE
// ═════════════════════════════════════════════
class AdminShimmerTile extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const AdminShimmerTile({
    super.key,
    this.height = 60,
    this.width,
    this.radius = 12,
  });

  @override
  State<AdminShimmerTile> createState() => _AdminShimmerTileState();
}

class _AdminShimmerTileState extends State<AdminShimmerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

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
      builder: (_, _) => Container(
        width:  widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            AdminColors.surfaceCard,
            AdminColors.surfaceElevated,
            _anim.value,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: AdminColors.border),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// EMPTY STATE
// ═════════════════════════════════════════════
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Color    color;
  final Widget?  action;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color   = AdminColors.textMuted,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                color:  color.withValues(alpha: 0.08),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, color: color.withValues(alpha: 0.5), size: 32),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: AdminTextStyles.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: AdminTextStyles.bodyMedium,
                textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// TOGGLE CARD (for settings toggles)
// ═════════════════════════════════════════════
class AdminToggleCard extends StatelessWidget {
  final String   title;
  final String   subtitle;
  final IconData icon;
  final Color    activeColor;
  final bool     value;
  final bool     loading;
  final void Function(bool) onChanged;
  final bool     isWarning;

  const AdminToggleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.activeColor,
    required this.value,
    required this.onChanged,
    this.loading    = false,
    this.isWarning  = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: value
            ? activeColor.withValues(alpha: 0.06)
            : AdminColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? activeColor.withValues(alpha: 0.35)
              : AdminColors.border,
          width: value ? 1.5 : 1,
        ),
        boxShadow: value
            ? [BoxShadow(
                color:      activeColor.withValues(alpha: 0.12),
                blurRadius: 16,
              )]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color:        (value ? activeColor : AdminColors.textMuted).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(
                  color: (value ? activeColor : AdminColors.textMuted).withValues(alpha: 0.25)),
            ),
            child: Icon(icon,
                color: value ? activeColor : AdminColors.textMuted,
                size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AdminTextStyles.titleSmall.copyWith(
                        color: value ? activeColor : AdminColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: AdminTextStyles.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          loading
              ? SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: activeColor),
                )
              : Switch(
                  value:            value,
                  onChanged:        onChanged,
                  activeThumbColor:      activeColor,
                  inactiveThumbColor: AdminColors.textMuted,
                  inactiveTrackColor: AdminColors.surfaceElevated,
                ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// PLATFORM ALERT BANNER (for dashboard)
// ═════════════════════════════════════════════
class AdminAlertBanner extends StatelessWidget {
  final String   message;
  final Color    color;
  final IconData icon;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;
  final String?  actionLabel;

  const AdminAlertBanner({
    super.key,
    required this.message,
    required this.color,
    required this.icon,
    this.onDismiss,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        border:       Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: AdminTextStyles.bodyMedium.copyWith(color: color)),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border:       Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(actionLabel!,
                    style: AdminTextStyles.labelSmall.copyWith(color: color)),
              ),
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close_rounded,
                  color: color.withValues(alpha: 0.6), size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// GRID — AdminGrid (already in admin_page_container.dart, but exported here
//        for components that import only admin_components.dart)
// ═════════════════════════════════════════════
class AdminGrid extends StatelessWidget {
  final List<Widget> children;
  final int          mobileColumns;
  final int          tabletColumns;
  final int          desktopColumns;
  final double       spacing;
  final double       runSpacing;

  const AdminGrid({
    super.key,
    required this.children,
    this.mobileColumns  = 1,
    this.tabletColumns  = 2,
    this.desktopColumns = 3,
    this.spacing        = 16,
    this.runSpacing     = 16,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols  = width > 900
        ? desktopColumns
        : width > 600
            ? tabletColumns
            : mobileColumns;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing:    spacing,
          runSpacing: runSpacing,
          children: children.map((child) =>
              SizedBox(width: itemWidth, child: child)).toList(),
        );
      },
    );
  }
}