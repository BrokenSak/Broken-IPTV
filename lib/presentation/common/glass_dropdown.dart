import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'tv_focusable.dart';

class GlassDropdownEntry<T> {
  const GlassDropdownEntry({required this.value, required this.label, this.trailing});

  final T value;
  final String label;

  /// Optional secondary text shown right-aligned in the menu (e.g. "10 ep.").
  final String? trailing;
}

/// A dropdown styled like the player's dark rounded panels — a translucent
/// black field and a rounded, glass-bordered menu — instead of the dated
/// default Material dropdown. The menu scrolls when there are many entries.
///
/// TV-ready: the trigger and every menu entry go through [TvFocusable], so a
/// remote sees the white focus ring and OK activates them (the previous
/// InkWell/MenuItemButton had invisible focus here — the theme zeroes
/// `highlightColor` and uses `NoSplash` — which on TV read as "not
/// selectable"). When the menu opens, the current entry autofocuses so the
/// D-pad lands inside the menu; on phone/Windows that's policy-gated off and
/// tap/click work as before.
class GlassDropdown<T> extends StatefulWidget {
  const GlassDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.leadingIcon,
    this.expand = false,
  });

  final T value;
  final List<GlassDropdownEntry<T>> items;
  final ValueChanged<T> onChanged;
  final IconData? leadingIcon;

  /// When true the field stretches to fill its parent's width.
  final bool expand;

  @override
  State<GlassDropdown<T>> createState() => _GlassDropdownState<T>();
}

class _GlassDropdownState<T> extends State<GlassDropdown<T>> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final current =
        items.firstWhere((e) => e.value == widget.value, orElse: () => items.first);

    // Cap the menu width to the screen so it never gets clipped on the left, and
    // ellipsize long labels within that width.
    final screenW = MediaQuery.of(context).size.width;
    final menuMaxW = (screenW - 40).clamp(200.0, 400.0);
    final labelMaxW = menuMaxW - 96;

    return MenuAnchor(
      controller: _controller,
      // A tap outside closes the menu without also hitting what's underneath
      // (e.g. the player overlay's dismiss area).
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xF01C1C1E)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
        ),
        maximumSize: WidgetStatePropertyAll(Size(menuMaxW, 460)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6, horizontal: 4)),
      ),
      menuChildren: [
        for (final e in items)
          _GlassMenuItem(
            selected: e.value == current.value,
            // The D-pad lands on the current entry when the menu opens.
            // Policy-gated inside TvFocusable: no stray highlight on phones,
            // no-op on Windows.
            autofocus: e.value == current.value,
            label: e.label,
            trailing: e.trailing,
            labelMaxWidth: labelMaxW,
            onTap: () {
              _controller.close();
              widget.onChanged(e.value);
            },
          ),
      ],
      builder: (context, controller, _) {
        final label = Text(
          current.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        );
        return TvFocusable(
          borderRadius: 14,
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (widget.leadingIcon != null) ...[
                  Icon(widget.leadingIcon, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                ],
                widget.expand ? Expanded(child: label) : Flexible(child: label),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more, color: Colors.white70, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One entry of the glass menu: a [TvFocusable] row (ring + OK on TV, tap on
/// touch, hover on Windows) with the check mark on the current value.
class _GlassMenuItem extends StatelessWidget {
  const _GlassMenuItem({
    required this.selected,
    required this.autofocus,
    required this.label,
    required this.trailing,
    required this.labelMaxWidth,
    required this.onTap,
  });

  final bool selected;
  final bool autofocus;
  final String label;
  final String? trailing;
  final double labelMaxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 10,
      autofocus: autofocus,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check,
              size: 18,
              color: selected ? Colors.white : Colors.transparent,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: labelMaxWidth),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 16),
              Text(
                trailing!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
