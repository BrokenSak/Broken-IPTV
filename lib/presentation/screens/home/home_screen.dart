import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/download_support.dart';
import '../../../core/fullscreen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../state/catalog_refresh.dart';
import '../../../state/live_providers.dart'
    show expiryDateProvider, liveCategoriesProvider;
import '../../../state/series_providers.dart' show seriesCategoriesProvider;
import '../../../state/vod_providers.dart' show vodCategoriesProvider;
import '../../../state/update_providers.dart';
import '../../common/app_dialogs.dart';
import '../../common/app_logo.dart';
import '../../common/tv_focusable.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instantiate the refresher so its 24h auto-refresh timer runs.
    ref.watch(catalogRefreshProvider);
    // Warm the three catalogs in the background: on slow panels (tens of
    // seconds per call) the fetch starts now instead of on the first tap on
    // TV/Film/Serie. read(...) doesn't subscribe, and the FutureProviders
    // cache the in-flight future, so repeated builds are no-ops. Errors are
    // ignored here — the catalog screens surface them with a retry.
    ref.read(liveCategoriesProvider.future).ignore();
    ref.read(vodCategoriesProvider.future).ignore();
    ref.read(seriesCategoriesProvider.future).ignore();
    final isFullscreen = ref.watch(fullscreenProvider);

    // The home is the root route: a system Back here would kill the app cold.
    // Ask first (app-themed dialog, D-pad friendly) — mainly for TV remotes.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final exit = await showAppConfirmDialog(
          context,
          title: 'Uscire da Broken IPTV?',
          message: 'Vuoi chiudere l\'applicazione?',
          confirmLabel: 'Esci',
        );
        if (exit) SystemNavigator.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 30),
            const SizedBox(width: 12),
            Text('Broken IPTV', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerca',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          // Offline downloads: phone (touch) mode on the APK only.
          if (downloadsSupported())
            IconButton(
              tooltip: 'Scaricati',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => context.push('/downloads'),
            ),
          // Windows only: on Android the app is permanently fullscreen.
          if (fullscreenToggleAvailable)
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Size tiles to the available space so three always fit, whatever
          // the window/screen size.
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final horizontalPadding = (w * 0.04).clamp(12.0, 48.0);
          final gap = (w * 0.02).clamp(8.0, 24.0);
          final usableW = w - horizontalPadding * 2 - gap * 2;
          final tileW = usableW / 3;
          final tileH = (h * 0.62).clamp(120.0, tileW * 1.25);

          return Column(
            children: [
              const _UpdateBanner(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _HomeTile(
                          label: 'TV',
                          icon: Icons.live_tv,
                          width: tileW,
                          height: tileH,
                          // D-pad: land on TV when the home opens.
                          autofocus: true,
                          onTap: () => context.push('/live'),
                        ),
                        SizedBox(width: gap),
                        _HomeTile(
                          label: 'Serie',
                          icon: Icons.video_library_outlined,
                          width: tileW,
                          height: tileH,
                          onTap: () => context.push('/series'),
                        ),
                        SizedBox(width: gap),
                        _HomeTile(
                          label: 'Film',
                          icon: Icons.movie_outlined,
                          width: tileW,
                          height: tileH,
                          onTap: () => context.push('/vod'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const _ExpiryLine(),
              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 8),
                child: _RefreshButton(),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.label,
    required this.icon,
    required this.width,
    required this.height,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final double width;
  final double height;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final iconSize = (width * 0.22).clamp(28.0, 64.0);
    final fontSize = (width * 0.12).clamp(16.0, 26.0);

    return SizedBox(
      width: width,
      height: height,
      child: TvFocusable(
        borderRadius: 20,
        autofocus: autofocus,
        onTap: onTap,
        child: Card(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: Colors.white),
              SizedBox(height: height * 0.06),
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown at the top of the home when a newer release is published (checked on
/// open, see updateCheckProvider). Tapping "Aggiorna" downloads the artifact
/// in-app and hands it to the OS to install (one system confirmation on
/// Android; the installer runs on Windows).
class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateCheckProvider).value;
    if (info == null) return const SizedBox.shrink();
    final download = ref.watch(updateDownloadProvider);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Aggiornamento disponibile (${info.version})',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                if (download.error != null)
                  Text(download.error!,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))
                else if (info.notes.isNotEmpty)
                  Text(info.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (download.downloading)
            _DownloadProgress(progress: download.progress)
          else
            TvFocusable(
              borderRadius: 12,
              onTap: () => ref.read(updateDownloadProvider.notifier).downloadAndInstall(info),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Aggiorna',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress > 0 ? progress : null,
            strokeWidth: 3,
            color: Colors.white,
            backgroundColor: Colors.white24,
          ),
          Text('${(progress * 100).round()}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}

String formatExpiry(DateTime d) {
  final local = d.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mi = local.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${local.year} $hh:$mi';
}

class _ExpiryLine extends ConsumerWidget {
  const _ExpiryLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiry = ref.watch(expiryDateProvider);
    return expiry.maybeWhen(
      data: (date) {
        if (date == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Abbonamento valido fino al ${formatExpiry(date)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RefreshButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends ConsumerState<_RefreshButton> {
  // Transient outcome shown inside the button itself (no snackbar).
  String? _result;
  bool _ok = true;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _doRefresh() async {
    final error = await ref.read(catalogRefreshProvider).refreshNow();
    if (!mounted) return;
    setState(() {
      _ok = error == null;
      _result = error == null ? 'Lista aggiornata' : 'Aggiornamento non riuscito';
    });
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _result = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = ref.watch(catalogRefreshingProvider);
    final label = refreshing ? 'Aggiornamento...' : (_result ?? 'Aggiorna lista');
    final Widget icon;
    if (refreshing) {
      icon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_result != null) {
      icon = Icon(_ok ? Icons.check_circle_outline : Icons.error_outline);
    } else {
      icon = const Icon(Icons.refresh);
    }

    return TvFocusable(
      borderRadius: 14,
      onTap: refreshing ? () {} : _doRefresh,
      // The TvFocusable is the one D-pad node: the inner button must not be a
      // second focus stop (mouse clicks still reach it).
      child: ExcludeFocus(
        child: OutlinedButton.icon(
          onPressed: refreshing ? null : _doRefresh,
          icon: icon,
          label: Text(label),
        ),
      ),
    );
  }
}
