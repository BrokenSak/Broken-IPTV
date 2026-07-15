import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adult_filter.dart';
import '../../core/fullscreen.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/xtream_category.dart';
import 'grid_metrics.dart';
import 'tv_focusable.dart';

// Re-exported so catalog screens (which already import this file) can reuse it.
export '../../core/adult_filter.dart' show isAdultCategory;

const kFavoritesCategoryId = '__favorites__';
const kContinueCategoryId = '__continue__';
const kAllCategoryId = '__all__';
const kRecentCategoryId = '__recent__';

/// Shared chrome for the TV / Series / Film catalog screens: back button,
/// title, an in-catalog search field toggle, a fullscreen button and an
/// always-available settings button.
class CatalogScaffold extends ConsumerStatefulWidget {
  const CatalogScaffold({
    super.key,
    required this.title,
    required this.onSearch,
    required this.body,
    this.initialQuery = '',
  });

  final String title;
  final ValueChanged<String> onSearch;
  final Widget body;
  final String initialQuery;

  @override
  ConsumerState<CatalogScaffold> createState() => _CatalogScaffoldState();
}

class _CatalogScaffoldState extends ConsumerState<CatalogScaffold> {
  late final TextEditingController _controller;
  late bool _searching;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _searching = widget.initialQuery.isNotEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _controller.clear();
    widget.onSearch('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final isFullscreen = ref.watch(fullscreenProvider);
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _controller,
                autofocus: true,
                onChanged: widget.onSearch,
                decoration: InputDecoration(
                  hintText: 'Cerca in ${widget.title}...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(color: AppColors.textPrimary),
              )
            : Text(widget.title),
        actions: [
          if (_searching)
            IconButton(icon: const Icon(Icons.close), onPressed: _closeSearch)
          else
            IconButton(
              tooltip: 'Cerca',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _searching = true),
            ),
          IconButton(
            tooltip: isFullscreen ? 'Esci da schermo intero' : 'Schermo intero',
            icon: Icon(isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: () => ref.read(fullscreenProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: widget.body,
    );
  }
}

/// Left-hand category list. Pins "CONTINUA A GUARDARE" (only when
/// [showContinue]), "PREFERITI", and optionally "TUTTI"/"ULTIMI AGGIUNTI"
/// ([showAll]/[showRecent]) on top, lists the normal categories, and groups all
/// adult categories under a single collapsible "ADULTI" entry at the bottom.
class CategorySidebar extends StatefulWidget {
  const CategorySidebar({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    this.counts = const {},
    this.showContinue = false,
    this.showAll = false,
    this.showRecent = false,
    this.favoritesCount = 0,
    this.continueCount = 0,
    this.allCount = 0,
    this.recentCount = 0,
  });

  final List<XtreamCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Map<String, int> counts;
  final bool showContinue;
  final bool showAll;
  final bool showRecent;
  final int favoritesCount;
  final int continueCount;
  final int allCount;
  final int recentCount;

  @override
  State<CategorySidebar> createState() => _CategorySidebarState();
}

class _CategorySidebarState extends State<CategorySidebar> {
  bool _adultExpanded = false;

  @override
  Widget build(BuildContext context) {
    final normal = <XtreamCategory>[];
    final adult = <XtreamCategory>[];
    for (final c in widget.categories) {
      (isAdultCategory(c.name) ? adult : normal).add(c);
    }

    // If the currently selected category is an adult one, keep the group open.
    final selectedIsAdult = adult.any((c) => c.id == widget.selectedId);
    final adultOpen = _adultExpanded || selectedIsAdult;

    final rows = <Widget>[];
    var first = true;

    void addRow(String id, String label, IconData? icon, int? count,
        {bool indent = false, VoidCallback? onTapOverride, bool bold = false}) {
      final selected = id == widget.selectedId;
      final autofocus = first;
      first = false;
      rows.add(TvFocusable(
        autofocus: autofocus,
        borderRadius: 12,
        onTap: onTapOverride ?? () => widget.onSelect(id),
        child: Container(
          color: selected ? AppColors.surfaceElevated : Colors.transparent,
          padding: EdgeInsets.fromLTRB(indent ? 30 : 16, 14, 16, 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: selected ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: (selected || bold) ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Text('$count',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ],
          ),
        ),
      ));
    }

    if (widget.showContinue) {
      addRow(kContinueCategoryId, 'CONTINUA A GUARDARE', Icons.live_tv, widget.continueCount);
    }
    addRow(kFavoritesCategoryId, 'PREFERITI', Icons.favorite, widget.favoritesCount);
    if (widget.showAll) {
      addRow(kAllCategoryId, 'TUTTI', Icons.grid_view, widget.allCount);
    }
    if (widget.showRecent) {
      addRow(kRecentCategoryId, 'ULTIMI AGGIUNTI', Icons.fiber_new, widget.recentCount);
    }
    for (final c in normal) {
      addRow(c.id, c.name, null, widget.counts[c.id]);
    }

    // Collapsible "ADULTI" group at the very bottom.
    if (adult.isNotEmpty) {
      rows.add(_AdultHeader(
        expanded: adultOpen,
        count: adult.length,
        onTap: () => setState(() => _adultExpanded = !adultOpen),
      ));
      if (adultOpen) {
        for (final c in adult) {
          addRow(c.id, c.name, null, widget.counts[c.id], indent: true);
        }
      }
    }

    return SizedBox(
      // Narrower on Android so the grid gets more columns (see GridMetrics).
      width: GridMetrics.sidebarWidth,
      child: Scrollbar(
        child: ListView(
          // Reserve gutters on both sides so the selection highlight/glow is
          // never clipped by the screen edge (left) or the scrollbar (right).
          padding: const EdgeInsets.only(left: 12, right: 10),
          children: rows,
        ),
      ),
    );
  }
}

class _AdultHeader extends StatelessWidget {
  const _AdultHeader({required this.expanded, required this.count, required this.onTap});

  final bool expanded;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 12,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.explicit, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'ADULTI',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
            Text('$count',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(width: 4),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
