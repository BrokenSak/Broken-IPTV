import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/xtream_profile.dart';
import '../../../data/services/content_source.dart';
import '../../../data/services/device_mode_service.dart';
import '../../../data/services/speed_test_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../state/favorites_providers.dart';
import '../../../state/live_providers.dart';
import '../../../state/player_settings_providers.dart';
import '../../../state/profile_providers.dart';
import '../../../state/series_providers.dart';
import '../../../state/vod_providers.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/tv_focusable.dart';

// Shared text styles for settings: **bold** titles, *italic* descriptions.
const _kSectionTitle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.bold,
  letterSpacing: -0.2,
  color: AppColors.textPrimary,
);
const _kItemTitle = TextStyle(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.bold,
);
const _kItemDesc = TextStyle(
  color: AppColors.textSecondary,
  fontStyle: FontStyle.italic,
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _deviceModeService = DeviceModeService();
  DeviceMode? _currentMode;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _currentMode = _deviceModeService.getSaved();
    }
  }

  Future<void> _setMode(DeviceMode mode) async {
    await _deviceModeService.save(mode);
    if (mounted) setState(() => _currentMode = mode);
  }

  Future<void> _clearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Svuota cache?'),
        content: const Text(
          'Verranno eliminati preferiti, cronologia "Continua a guardare" e '
          'immagini/cataloghi in cache. Le playlist salvate restano.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Svuota')),
        ],
      ),
    );
    if (ok != true) return;

    await DefaultCacheManager().emptyCache();
    await StorageService.favoritesBox.clear();
    await StorageService.watchProgressBox.clear();
    await StorageService.catalogCacheBox.clear();
    // Bulk EPG files (one per profile), best-effort.
    try {
      final dir = await getApplicationSupportDirectory();
      await for (final f in dir.list()) {
        if (f is File && f.uri.pathSegments.last.startsWith('epg_')) {
          await f.delete();
        }
      }
    } catch (_) {}
    ref.invalidate(favoritesProvider);
    ref.invalidate(watchProgressProvider);
    ref.invalidate(liveCategoriesProvider);
    ref.invalidate(vodCategoriesProvider);
    ref.invalidate(seriesCategoriesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dati personali eliminati.')),
      );
    }
  }

  Future<void> _confirmDeletePlaylist(XtreamProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare playlist?'),
        content: Text('"${profile.name}" verrà rimossa insieme alle credenziali salvate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(profilesProvider.notifier).remove(profile.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    final selectedId = ref.watch(selectedProfileIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Playlist', style: _kSectionTitle),
          const SizedBox(height: 8),
          // Each playlist shows only its name; the selected one is filled white
          // like the other setting chips. Edit/delete live on the box itself.
          ...profiles.map((p) => _PlaylistTile(
                profile: p,
                selected: p.id == selectedId,
                onSelect: () => ref.read(selectedProfileIdProvider.notifier).select(p.id),
                onEdit: () => context.push('/profiles/add', extra: p),
                onDelete: () => _confirmDeletePlaylist(p),
              )),
          const SizedBox(height: 4),
          TvFocusable(
            borderRadius: 14,
            onTap: () => context.push('/profiles/add'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, color: AppColors.textPrimary),
                  SizedBox(width: 12),
                  Text('Aggiungi playlist', style: _kItemTitle),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Account', style: _kSectionTitle),
          const SizedBox(height: 8),
          const _AccountSection(),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 24),
            const Text('Modalità dispositivo', style: _kSectionTitle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TvFocusable(
                    onTap: () => _setMode(DeviceMode.tv),
                    child: _ModeChip(label: 'TV / Telecomando', selected: _currentMode == DeviceMode.tv),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TvFocusable(
                    onTap: () => _setMode(DeviceMode.touch),
                    child: _ModeChip(label: 'Telefono / Tablet', selected: _currentMode == DeviceMode.touch),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Text('Riproduzione', style: _kSectionTitle),
          const SizedBox(height: 8),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.aspect_ratio),
            title: Text('Rapporto d\'aspetto predefinito', style: _kItemTitle),
          ),
          Row(
            children: [
              for (final aspect in VideoAspect.values) ...[
                Expanded(
                  child: TvFocusable(
                    borderRadius: 14,
                    onTap: () => ref.read(playerSettingsProvider.notifier).setAspect(aspect),
                    child: _ModeChip(
                      label: aspect.label,
                      selected: ref.watch(playerSettingsProvider).aspect == aspect,
                    ),
                  ),
                ),
                if (aspect != VideoAspect.values.last) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.subtitles_outlined),
            title: const Text('Sottotitoli', style: _kItemTitle),
            subtitle: const Text('Disattivati per impostazione predefinita', style: _kItemDesc),
            value: ref.watch(playerSettingsProvider).subtitlesEnabled,
            onChanged: (v) => ref.read(playerSettingsProvider.notifier).setSubtitlesEnabled(v),
          ),
          const SizedBox(height: 12),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.forward_10),
            title: Text('Salto avanti/indietro', style: _kItemTitle),
            subtitle: Text('Solo film e serie', style: _kItemDesc),
          ),
          Row(
            children: [
              for (final s in kSkipOptions) ...[
                Expanded(
                  child: TvFocusable(
                    borderRadius: 14,
                    onTap: () => ref.read(playerSettingsProvider.notifier).setSkipSeconds(s),
                    child: _ModeChip(
                      label: '$s s',
                      selected: ref.watch(playerSettingsProvider).skipSeconds == s,
                    ),
                  ),
                ),
                if (s != kSkipOptions.last) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 24),
          const Text('Rete', style: _kSectionTitle),
          const SizedBox(height: 8),
          const _SpeedTestTile(),
          const SizedBox(height: 24),
          const Text('Cache', style: _kSectionTitle),
          const SizedBox(height: 8),
          TvFocusable(
            onTap: _clearData,
            child: const ListTile(
              leading: Icon(Icons.cleaning_services_outlined),
              title: Text('Svuota cache', style: _kItemTitle),
              subtitle: Text(
                'elimina tutti i dati personali dell\'applicazione sul dispositivo',
                style: _kItemDesc,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.profile,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final XtreamProfile profile;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : AppColors.textPrimary;
    final subFg = selected ? Colors.black54 : AppColors.textSecondary;
    return TvFocusable(
      borderRadius: 14,
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.playlist_play, color: selected ? Colors.black : AppColors.accent),
            const SizedBox(width: 12),
            // Only the name is shown here — host/username appear only in Edit.
            Expanded(
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            IconButton(
              tooltip: 'Modifica',
              icon: Icon(Icons.edit_outlined, color: subFg),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Elimina',
              icon: Icon(Icons.delete_outline, color: subFg),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  static String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  static String _countdown(DateTime expiry) {
    final diff = expiry.difference(DateTime.now());
    if (diff.isNegative) return 'Scaduto';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    if (days > 0) return 'tra ${days}g ${hours}h';
    final minutes = diff.inMinutes % 60;
    return 'tra ${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountInfoProvider);
    return account.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const Text('Informazioni account non disponibili.', style: _kItemDesc),
      data: (AccountInfo? a) {
        if (a == null) {
          return const Text('Informazioni account non disponibili.', style: _kItemDesc);
        }
        final rows = <Widget>[];
        void row(IconData icon, String label, String value) {
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Text('$label: ', style: _kItemTitle),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(color: AppColors.textPrimary),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ));
        }

        if (a.status != null) {
          row(Icons.verified_user_outlined, 'Stato',
              a.isTrial == true ? '${a.status} (prova)' : a.status!);
        }
        if (a.expiresAt != null) {
          row(Icons.event_outlined, 'Scadenza', '${_fmtDate(a.expiresAt!)}  •  ${_countdown(a.expiresAt!)}');
        }
        if (a.maxConnections != null || a.activeConnections != null) {
          final active = a.activeConnections?.toString() ?? '?';
          final max = a.maxConnections?.toString() ?? '?';
          row(Icons.lan_outlined, 'Connessioni', '$active / $max attive');
        }
        if (a.serverUrl != null && a.serverUrl!.isNotEmpty) {
          row(Icons.dns_outlined, 'Server', a.serverUrl!);
        }
        if (rows.isEmpty) {
          return const Text('Informazioni account non disponibili.', style: _kItemDesc);
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
        );
      },
    );
  }
}

class _SpeedTestTile extends ConsumerStatefulWidget {
  const _SpeedTestTile();

  @override
  ConsumerState<_SpeedTestTile> createState() => _SpeedTestTileState();
}

class _SpeedTestTileState extends ConsumerState<_SpeedTestTile> {
  bool _running = false;
  SpeedTestResult? _result;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await SpeedTestService().run();
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = 'Test non riuscito. Controlla la connessione.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TvFocusable(
          onTap: _running ? () {} : _run,
          child: ListTile(
            leading: _running
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speed),
            title: Text(_running ? 'Test in corso...' : 'Esegui speed test', style: _kItemTitle),
            subtitle: const Text('Misura la velocità della tua connessione (fast.com)', style: _kItemDesc),
          ),
        ),
        if (_result != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_result!.mbps.toStringAsFixed(1)} Mbps — ${_result!.verdict}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_result!.detail, style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
          ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
