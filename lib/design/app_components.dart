import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app_design_system.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    this.appBar,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
    this.safeArea = true,
    super.key,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            minWidth: 0,
          ),
          child: SizedBox(
            width: constraints.maxWidth < maxWidth
                ? constraints.maxWidth
                : maxWidth,
            child: Padding(padding: padding, child: body),
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: appBar,
      body: safeArea ? SafeArea(child: content) : content,
    );
  }
}

class _GlassBlurBudget {
  _GlassBlurBudget._();

  static const int maxConcurrentSurfaces = 2;
  static final Set<Object> _active = <Object>{};

  static bool acquire(Object owner) {
    if (_active.contains(owner)) return true;
    if (_active.length >= maxConcurrentSurfaces) return false;
    _active.add(owner);
    return true;
  }

  static void release(Object owner) => _active.remove(owner);
}

class GlassSurface extends StatefulWidget {
  const GlassSurface({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppRadius.large),
    ),
    this.blurSigma = 16,
    this.forceOpaque = false,
    this.enableBlur = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BorderRadius borderRadius;
  final double blurSigma;
  final bool forceOpaque;
  final bool enableBlur;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  bool _hasBlurSlot = false;

  bool get _accessibilityFallback {
    final media = MediaQuery.maybeOf(context);
    return widget.forceOpaque ||
        media?.disableAnimations == true ||
        media?.highContrast == true ||
        kIsWeb;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateBlurSlot();
  }

  @override
  void didUpdateWidget(covariant GlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBlurSlot();
  }

  void _updateBlurSlot() {
    final shouldBlur = widget.enableBlur && !_accessibilityFallback;
    if (shouldBlur && !_hasBlurSlot) {
      _hasBlurSlot = _GlassBlurBudget.acquire(this);
    } else if (!shouldBlur && _hasBlurSlot) {
      _GlassBlurBudget.release(this);
      _hasBlurSlot = false;
    }
  }

  @override
  void dispose() {
    if (_hasBlurSlot) _GlassBlurBudget.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = widget.color ??
        (theme.brightness == Brightness.dark
            ? AppDesignTokens.darkSurface
            : AppDesignTokens.lightSurface);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill.withValues(alpha: _hasBlurSlot ? 0.75 : 1),
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.90),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.16 : 0.06,
            ),
            blurRadius: AppElevation.raised * 4,
            offset: const Offset(0, AppElevation.raised),
          ),
        ],
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );
    if (!_hasBlurSlot) return surface;
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: widget.blurSigma.clamp(12, 20),
          sigmaY: widget.blurSigma.clamp(12, 20),
        ),
        child: surface,
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height =
        AppBreakpoints.of(context) == AppViewport.expanded ? 44.0 : 48.0;
    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(0, height),
        maximumSize: Size(double.infinity, height),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: loading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : icon == null
                    ? const SizedBox.shrink()
                    : Icon(icon, size: 20),
          ),
          if (loading || icon != null) const SizedBox(width: AppSpacing.x2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      width: expand ? double.infinity : null,
      height: height,
      child: button,
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height =
        AppBreakpoints.of(context) == AppViewport.expanded ? 44.0 : 48.0;
    final child = icon == null
        ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: AppSpacing.x2),
              Flexible(
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          );
    return SizedBox(
      width: expand ? double.infinity : null,
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(minimumSize: Size(0, height)),
        child: child,
      ),
    );
  }
}

class TextActionButton extends StatelessWidget {
  const TextActionButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

class IconActionButton extends StatelessWidget {
  const IconActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onPressed,
        constraints: const BoxConstraints(
          minWidth: AppSpacing.x12,
          minHeight: AppSpacing.x12,
        ),
        icon: Icon(icon, color: color),
      );
}

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.x4),
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(
      clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.x4),
    this.forceOpaque = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool forceOpaque;

  @override
  Widget build(BuildContext context) => GlassSurface(
        padding: padding,
        forceOpaque: forceOpaque,
        child: child,
      );
}

class ListRow extends StatelessWidget {
  const ListRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        child: ListTile(
          minTileHeight: AppSpacing.x12,
          leading: leading,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: trailing,
          onTap: onTap,
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (action != null && onAction != null)
            TextActionButton(label: action!, onPressed: onAction),
        ],
      );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.label,
    this.hint,
    this.onChanged,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    super.key,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        maxLines: obscureText ? 1 : maxLines,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
      );
}

class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
      );
}

class AppTag extends StatelessWidget {
  const AppTag({
    required this.label,
    this.icon,
    this.color,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: icon == null ? null : Icon(icon, size: 18, color: color),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      side: BorderSide(color: color ?? scheme.outlineVariant),
      backgroundColor: (color ?? scheme.surface).withValues(alpha: 0.10),
      visualDensity: VisualDensity.compact,
    );
  }
}

class StepIndicator extends StatelessWidget {
  const StepIndicator({
    required this.currentStep,
    required this.totalSteps,
    required this.label,
    super.key,
  })  : assert(totalSteps > 0),
        assert(currentStep >= 0 && currentStep < totalSteps);

  final int currentStep;
  final int totalSteps;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        value: '${currentStep + 1} / $totalSteps',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.x2),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: (currentStep + 1) / totalSteps,
                minHeight: AppSpacing.x1,
              ),
            ),
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.message,
    this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: AppSpacing.x12,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.x3),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.x2),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.x4),
                action!,
              ],
            ],
          ),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.title,
    required this.retryLabel,
    required this.onRetry,
    this.message,
    super.key,
  });

  final String title;
  final String retryLabel;
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => EmptyState(
        title: title,
        message: message,
        icon: Icons.cloud_off_outlined,
        action: SecondaryButton(
          label: retryLabel,
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
          expand: false,
        ),
      );
}

class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({
    required this.semanticLabel,
    this.width,
    this.height = AppSpacing.x4,
    this.borderRadius = AppRadius.small,
    super.key,
  });

  final String semanticLabel;
  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        child: RepaintBoundary(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          ),
        ),
      );
}

class ConfirmDialog {
  const ConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextActionButton(
            label: cancelLabel,
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class AppBottomSheet {
  const AppBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: isScrollControlled,
        builder: builder,
      );
}

class AppSnackbar {
  const AppSnackbar._();

  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    required this.label,
    this.size = AppSpacing.x12,
    super.key,
  }) : assert(value >= 0 && value <= 1);

  final double value;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        value: '${(value * 100).round()}%',
        child: SizedBox.square(
          dimension: size,
          child: CircularProgressIndicator(value: value),
        ),
      );
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.label,
    this.imageUrl,
    this.size = AppSpacing.x12,
    super.key,
  });

  final String label;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uri = imageUrl == null ? null : Uri.tryParse(imageUrl!);
    final validUrl = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    return Semantics(
      image: true,
      label: label,
      child: CircleAvatar(
        radius: size / 2,
        backgroundImage: validUrl ? NetworkImage(imageUrl!) : null,
        child: validUrl
            ? null
            : Text(
                label.trim().isEmpty
                    ? '?'
                    : String.fromCharCode(label.trim().runes.first)
                        .toUpperCase(),
              ),
      ),
    );
  }
}

class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    this.color,
    super.key,
  });

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final badgeColor = color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: badgeColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x1,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: badgeColor,
                ),
          ),
        ),
      ),
    );
  }
}

class AppNavigationItem {
  const AppNavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class GlassTopBar extends StatelessWidget {
  const GlassTopBar({
    required this.title,
    this.leading,
    this.actions = const [],
    super.key,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => GlassSurface(
        borderRadius: BorderRadius.zero,
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.x4,
          AppSpacing.x2,
          AppSpacing.x2,
          AppSpacing.x2,
        ),
        child: SizedBox(
          height: AppSpacing.x12 + AppSpacing.x2,
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.x3),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final action in actions) action,
            ],
          ),
        ),
      );
}

class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  })  : assert(items.length == 5),
        assert(selectedIndex >= 0 && selectedIndex < items.length);

  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RepaintBoundary(
      child: GlassSurface(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.large),
          topRight: Radius.circular(AppRadius.large),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x1,
          vertical: AppSpacing.x1,
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: index == selectedIndex,
                    label: items[index].label,
                    child: InkWell(
                      key: ValueKey('app-bottom-nav-$index'),
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      onTap: () => onSelected(index),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppSpacing.x12,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              index == selectedIndex
                                  ? items[index].selectedIcon
                                  : items[index].icon,
                              size: 22,
                              color: index == selectedIndex
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x1,
                              ),
                              child: Text(
                                items[index].label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: AppTypography.caption,
                                  color: index == selectedIndex
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                  fontWeight: index == selectedIndex
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.width = 88,
    super.key,
  });

  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: NavigationRail(
        backgroundColor: scheme.surface,
        minWidth: width,
        labelType: NavigationRailLabelType.all,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        destinations: [
          for (final item in items)
            NavigationRailDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon, color: scheme.primary),
              label: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.logo,
    required this.productName,
    this.width = 248,
    super.key,
  });

  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget logo;
  final String productName;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: BorderDirectional(
            end: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.x4,
                AppSpacing.x6,
                AppSpacing.x4,
                AppSpacing.x6,
              ),
              child: Row(
                children: [
                  logo,
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Text(
                      productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = index == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.x1),
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: item.label,
                      child: Material(
                        color: selected
                            ? scheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        child: InkWell(
                          key: ValueKey('dashboard-nav-$index'),
                          borderRadius: BorderRadius.circular(AppRadius.medium),
                          onTap: () => onSelected(index),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: AppSpacing.x12,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x3,
                                vertical: AppSpacing.x2,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected ? item.selectedIcon : item.icon,
                                    size: 22,
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: AppSpacing.x3),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        color: selected
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
