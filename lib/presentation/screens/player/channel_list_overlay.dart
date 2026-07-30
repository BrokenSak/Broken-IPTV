import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
// ScrollCacheExtent lives in rendering, not re-exported by material.
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/channel.dart';
import '../../../state/live_providers.dart';
import '../../common/glass_dropdown.dart';
import '../../common/tv_focusable.dart';

/// Bottom-left overlay listing live channels so you can zap without leaving the
/// player. It also lets you navigate between categories. A tap on the dim area
/// closes it; picking a channel switches playback in place.
///
/// Every stop is a [TvFocusable] (rows, category dropdown, close button): the
/// bare ListTile/IconButton the first version used had invisible focus on TV
/// (the theme zeroes `highlightColor`), which read as "not selectable".
class ChannelListOverlay extends ConsumerStatefulWidget {
  const ChannelListOverlay({
    super.key,
    required this.currentStreamId,
    required this.onClose,
    required this.onSelect,
  });

  final String? currentStreamId;
  final VoidCallback onClose;
  final void Function(String streamId, String name) onSelect;

  @override
  ConsumerState<ChannelListOverlay> createState() => _ChannelListOverlayState();
}

class _ChannelListOverlayState extends ConsumerState<ChannelListOverlay> {
  // null = "Tutti i canali" (all channels across categories).
  String? _catId;

  /// First row of the list, so a category change can drop the D-pad straight
  /// back into the (rebuilt) list instead of leaving the focus stranded.
  final _firstRowNode = FocusNode(debugLabel: 'channels.first');

  /// The row of the channel playing right now, so the remote opens ON it.
  final _currentRowNode = FocusNode(debugLabel: 'channels.current');

  /// One focus node per channel, **owned by the state**.
  ///
  /// ⚠️ A ListView.builder destroys rows that scroll out of view together with
  /// any focus node they created, so scrolling a long channel list with the
  /// D-pad kept dropping the focus. Owning the nodes here means a recycled row
  /// re-attaches the SAME node and the focus survives.
  final _rowNodes = <String, FocusNode>{};

  FocusNode _nodeFor(Channel c, {required bool current, required bool first}) {
    if (current) return _currentRowNode;
    if (first) return _firstRowNode;
    return _rowNodes.putIfAbsent(
        c.streamId, () => FocusNode(debugLabel: 'channel.${c.streamId}'));
  }

  bool _focusClaimed = false;

  @override
  void dispose() {
    _firstRowNode.dispose();
    _currentRowNode.dispose();
    for (final n in _rowNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Pulls the D-pad into the list as soon as the channels exist.
  ///
  /// ⚠️ `autofocus` alone does nothing here: the player's controls (the
  /// "Canali" button) still hold the focus when this overlay mounts, and
  /// Flutter honours autofocus only while the scope has no focused child.
  void _claimFocus() {
    if (_focusClaimed) return;
    _focusClaimed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _currentRowNode.canRequestFocus ? _currentRowNode : _firstRowNode;
      target.requestFocus();
    });
  }

  void _selectCategory(String? id) {
    setState(() => _catId = id);
    // After the menu closes and the re-keyed list mounts, land on row one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstRowNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final panelW = (size.width * 0.9).clamp(260.0, 420.0);
    // Sit above the bottom controls (bottomOffset) and below the top bar.
    const bottomOffset = 140.0;
    final panelH = (size.height - bottomOffset - 96).clamp(220.0, 560.0);

    final cats = ref.watch(liveCategoriesProvider).value ?? const [];
    // Always read the full channel list and filter by category on the device:
    // some panels ignore category_id and return an empty per-category list (see
    // the note in live_tv's _ChannelGrid), which left the overlay blank.
    final channelsAsync = ref.watch(allChannelsProvider);

    return Positioned.fill(
      child: Stack(
        children: [
          // Tap outside the panel to dismiss.
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onClose),
          ),
          Positioned(
            left: 12,
            bottom: bottomOffset,
            width: panelW,
            height: panelH,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              // ListTile paints its selected background on the nearest
              // Material: give it a transparent one INSIDE the decorated panel
              // (without it, Flutter asserts in debug and the selected
              // highlight can vanish).
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: category dropdown (categories can be many) + close.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: GlassDropdown<String?>(
                            value: _catId,
                            expand: true,
                            onChanged: _selectCategory,
                            items: [
                              const GlassDropdownEntry<String?>(
                                value: null,
                                label: 'Tutti i canali',
                              ),
                              for (final c in cats)
                                GlassDropdownEntry<String?>(value: c.id, label: c.name),
                            ],
                          ),
                        ),
                        TvIconButton(
                          tooltip: 'Chiudi',
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: channelsAsync.when(
                      data: (all) {
                        final list = _catId == null
                            ? all
                            : all.where((c) => c.categoryId == _catId).toList();
                        if (list.isEmpty) {
                          return const Center(
                            child: Text('Nessun canale.',
                                style: TextStyle(color: AppColors.textSecondary)),
                          );
                        }
                        // Rows exist now: take the D-pad off the controls.
                        _claimFocus();
                        return ListView.builder(
                          // Re-keyed per category: scroll back to the top and
                          // re-fire the first row's autofocus on a switch.
                          key: ValueKey(_catId),
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                          // Build past the viewport: directional focus can only
                          // reach rows that exist (see the note on _rowNodes).
                          scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final Channel c = list[index];
                            final selected = c.streamId == widget.currentStreamId;
                            return TvFocusable(
                              // Stable key so a recycled row keeps its state.
                              key: ValueKey(c.streamId),
                              borderRadius: 12,
                              // D-pad: enter the list right away when the
                              // overlay opens (the real entry point is
                              // _claimFocus — autofocus alone is ignored here).
                              autofocus: index == 0,
                              focusNode: _nodeFor(c,
                                  current: selected, first: index == 0),
                              onTap: () => widget.onSelect(c.streamId, c.name),
                              child: DecoratedBox(
                                // The channel playing right now: white bar on
                                // the left edge. Distinct from the focus ring,
                                // which answers a different question.
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: selected
                                      ? Colors.white.withValues(alpha: 0.10)
                                      : Colors.transparent,
                                  border: selected
                                      ? const Border(
                                          left: BorderSide(color: Colors.white, width: 4),
                                        )
                                      : null,
                                ),
                                child: ListTile(
                                dense: true,
                                leading: SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: c.logoUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: c.logoUrl!,
                                          fit: BoxFit.contain,
                                          errorWidget: (_, _, _) =>
                                              const Icon(Icons.tv, color: Colors.white54),
                                        )
                                      : const Icon(Icons.tv, color: Colors.white54),
                                ),
                                title: Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected ? Colors.white : AppColors.textPrimary,
                                    fontWeight:
                                        selected ? FontWeight.w700 : FontWeight.normal,
                                  ),
                                ),
                                subtitle: selected
                                    ? const Text(
                                        'In riproduzione',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    : null,
                                trailing: selected
                                    ? const Icon(Icons.equalizer, color: Colors.white, size: 18)
                                    : null,
                              ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('$e', style: const TextStyle(color: AppColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
