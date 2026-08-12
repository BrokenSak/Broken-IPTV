import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/content_source.dart';
import '../../../data/services/device_mode_service.dart';
import '../../../data/services/provisioning_service.dart';
import '../../../data/services/speed_test_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../state/favorites_providers.dart';
import '../../../state/live_providers.dart';
import '../../../state/player_settings_providers.dart';
import '../../../state/profile_providers.dart';
import '../../../state/provisioning_providers.dart';
import '../../../state/series_providers.dart';
import '../../../state/sync_providers.dart';
import '../../../state/vod_providers.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/app_dialogs.dart';
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

/// Gancio di test: la sezione "Modalità dispositivo" esiste solo su Android, e
/// su un host Windows il layout vero della TV non si riprodurrebbe — quella
/// sezione è proprio ciò che spinge giù il resto e fa uscire il codice dallo
/// schermo. Senza questo, il test del codice visibile passava anche col layout
/// rotto: cioè non serviva a niente.
bool? debugAndroidSectionOverride;

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
    final ok = await showAppConfirmDialog(
      context,
      title: 'Svuota cache?',
      message: 'Verranno eliminati preferiti, cronologia "Continua a guardare" e '
          'immagini/cataloghi in cache. Le playlist salvate restano.',
      confirmLabel: 'Svuota',
    );
    if (!ok) return;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: tvBackButton(context),
        title: const Text('Impostazioni'),
      ),
      // ⚠️ Ogni riquadro di questa schermata è una FERMATA del telecomando
      // (`_RigaLeggibile`), anche quelli che non fanno niente. Col D-pad una
      // lista scorre solo seguendo il focus: ciò su cui non ci si può fermare
      // non si può rileggere, e infatti la sincronizzazione "non si vedeva da
      // nessuna parte" (segnalato) — il fuoco la scavalcava. Per lo stesso
      // motivo il codice del dispositivo è tornato nella lista: da riga
      // navigabile ci si torna sopra, e la barra fissa in fondo non serve più.
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ⚠️ La scheda della playlist non c'è più (81° giro, richiesta
          // dell'utente): mostrava il **nome scritto nel pannello**, che è
          // un'etichetta del proprietario ("Enrico Hoffman - Firestick
          // Salone") e sulla TV di chi guarda non ci deve stare. L'unica cosa
          // che identifica l'abbonamento per chi lo usa è il **suo nome
          // utente**, ed è finito dentro la scheda Account, dove sta il resto
          // di quello che si può dire dell'abbonamento.
          const Text('Codice del dispositivo', style: _kSectionTitle),
          const SizedBox(height: 8),
          // Punto d'atterraggio del telecomando: è il primo premibile della
          // lista ed è anche quello che serve "adesso, mentre qualcuno te lo
          // chiede al telefono" (§7).
          _RigaLeggibile(
            autofocus: true,
            child: _CodiceDispositivo(code: ref.watch(deviceCodeProvider)),
          ),
          if (debugAndroidSectionOverride ?? Platform.isAndroid) ...[
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
          const _SettingLabel(
            icon: Icons.aspect_ratio,
            title: 'Rapporto d\'aspetto predefinito',
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
          // TvFocusable wrapper: a bare SwitchListTile takes D-pad focus with
          // nothing visible (transparent highlight). OK toggles the switch;
          // the inner tile stays tappable for touch/mouse but is not a second
          // focus stop.
          TvFocusable(
            borderRadius: 14,
            onTap: () => ref.read(playerSettingsProvider.notifier).setSubtitlesEnabled(
                !ref.read(playerSettingsProvider).subtitlesEnabled),
            child: ExcludeFocus(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.subtitles_outlined),
                title: const Text('Sottotitoli', style: _kItemTitle),
                subtitle:
                    const Text('Disattivati per impostazione predefinita', style: _kItemDesc),
                value: ref.watch(playerSettingsProvider).subtitlesEnabled,
                onChanged: (v) => ref.read(playerSettingsProvider.notifier).setSubtitlesEnabled(v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _SettingLabel(
            icon: Icons.forward_10,
            title: 'Salto avanti/indietro',
            subtitle: 'Solo film e serie',
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
          const Text('Sincronizzazione', style: _kSectionTitle),
          const SizedBox(height: 8),
          const _RigaLeggibile(child: _SyncSection()),
          const SizedBox(height: 24),
          // Sotto, non in mezzo: è informazione da leggere, non da raggiungere
          // in fretta, e in cima rubava lo spazio al codice del dispositivo.
          const Text('Account', style: _kSectionTitle),
          const SizedBox(height: 8),
          const _RigaLeggibile(child: _AccountSection()),
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

/// Il codice del dispositivo, dentro la lista come riga navigabile.
///
/// Ci si può tornare sopra col telecomando (è dentro un [_RigaLeggibile]), che
/// è la cosa che serve quando qualcuno al telefono ti chiede "leggimi il
/// codice" mentre sei in fondo alle impostazioni.
class _CodiceDispositivo extends StatelessWidget {
  const _CodiceDispositivo({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.tv_outlined, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Codice di questo dispositivo — leggilo a chi ti configura l\'app',
              style: _kItemDesc,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            DeviceCode.grouped(code),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una riga che si **legge**: il telecomando ci si ferma sopra, con l'anello
/// visibile, ma premere OK non fa niente.
///
/// ⚠️ Sembra contraddire la regola del 64° giro ("mai fermate che non fanno
/// nulla"), e invece è la stessa regola: quella vietava le fermate **invisibili**
/// — ink Material che prendono il fuoco senza disegnare niente. Qui l'anello si
/// vede, e la fermata serve a una cosa concreta: col D-pad una lista scorre solo
/// seguendo il focus, quindi ciò su cui non ci si può fermare non si può
/// nemmeno **rileggere**. È il motivo per cui la sincronizzazione "non si vedeva
/// da nessuna parte" (segnalato): il fuoco la scavalcava di netto.
class _RigaLeggibile extends StatelessWidget {
  const _RigaLeggibile({required this.child, this.autofocus = false});

  final Widget child;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocusable(
        borderRadius: 14,
        autofocus: autofocus,
        onTap: () {},
        child: child,
      ),
    );
  }
}

/// The caption above a row of chips ("Rapporto d'aspetto predefinito", "Salto
/// avanti/indietro"): an icon, a title and an optional description.
///
/// ⚠️ Deliberately **not** a [ListTile]. A ListTile always builds an [InkWell],
/// and on Android — where `app.dart` installs `NavigationMode.directional` —
/// `InkResponse` reports `canRequestFocus: true` whatever its callbacks are.
/// So these captions, which have no `onTap` and nothing to activate, were real
/// D-pad stops that painted no ring: coming down through Impostazioni the
/// selection simply vanished on them ("il focus deve essere solo su elementi
/// cliccabili, non su tutte le voci"). Passing `enabled: false` does not help —
/// directional mode overrides that too. Plain widgets: no ink, no stop.
class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Matches the vertical rhythm of the ListTiles it replaced.
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: _kItemTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: _kItemDesc),
                ],
              ],
            ),
          ),
        ],
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
    // L'utenza attiva su questo dispositivo. Non il nome che il proprietario le
    // ha dato nel pannello (81° giro: quello è roba sua) ma il **nome utente**
    // dell'abbonamento, l'unico che chi guarda possa riconoscere come suo.
    final profiles = ref.watch(profilesProvider);
    final selectedId = ref.watch(selectedProfileIdProvider);
    final active = profiles.where((p) => p.id == selectedId).firstOrNull ??
        (profiles.isEmpty ? null : profiles.first);
    final utente = active?.username.trim() ?? '';

    Widget scheda(List<Widget> rows) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
        );

    Widget riga(IconData icon, String label, String value) => Padding(
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
        );

    // La riga dell'utenza c'è sempre, anche mentre il pannello IPTV non
    // risponde: viene dalla playlist salvata qui, non dalla rete.
    final utenza = riga(
      Icons.person_outline,
      'Utenza attiva',
      utente.isEmpty ? 'nessuna' : utente,
    );

    return account.when(
      loading: () => scheda([
        utenza,
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ]),
      error: (_, _) => scheda([
        utenza,
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Resto delle informazioni non disponibile.', style: _kItemDesc),
        ),
      ]),
      data: (AccountInfo? a) {
        final rows = <Widget>[utenza];
        void row(IconData icon, String label, String value) {
          rows.add(riga(icon, label, value));
        }

        if (a == null) {
          rows.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Resto delle informazioni non disponibile.', style: _kItemDesc),
          ));
          return scheda(rows);
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
        // ⚠️ Niente riga "Server" (79° giro, richiesta dell'utente): era
        // l'ultimo posto dell'app in cui l'indirizzo del pannello si leggeva a
        // schermo, e chi guarda la TV non lo deve vedere — stessa ragione per
        // cui qui compare il nome utente e non il nome scritto nel pannello.
        // `AccountInfo.serverUrl` resta: serve al codice, non agli occhi.
        return scheda(rows);
      },
    );
  }
}

/// Lo stato della sincronizzazione, in **sola lettura**.
///
/// ⚠️ Dal 72° giro qui non si configura più niente (richiesta dell'utente):
/// niente codice da digitare, niente indirizzo, niente "genera codice", niente
/// "sincronizza ora". Il motivo è che la sincronizzazione **si accende dal
/// pannello del proprietario** e costa: ogni dispositivo che la usa scrive sul
/// servizio. Un dispositivo che potesse accendersela da solo aggirerebbe
/// l'interruttore dell'utenza — e chi la trovava spenta finiva a smanettare su
/// un codice che non doveva toccare.
///
/// Niente elementi focusabili: non c'è nulla da premere, e un ink Material
/// sarebbe una fermata cieca del D-pad (vedi [_SettingLabel]).
class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  static String _fmtWhen(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final truth = sync.truth;
    final attiva = truth == SyncTruth.attiva;

    // ⚠️ "Attiva" vuol dire **funziona**, non "ho un codice salvato" (81°
    // giro, segnalato dall'utente: «dice attiva anche quando non è
    // effettivamente attiva»). Il codice ce l'ha il dispositivo e non dipende
    // da nessuno; che il server lo accetti sì, ed è quello che conta.
    final String detail = switch (truth) {
      SyncTruth.attiva => 'Ultimo aggiornamento ${_fmtWhen(sync.lastSyncAt!)}.',
      SyncTruth.spentaDalPannello =>
        'Il servizio non l\'accetta più per questo dispositivo.',
      SyncTruth.maiRiuscita => 'Non è ancora riuscita a collegarsi.',
      SyncTruth.nonRiuscita => sync.lastSyncAt == null
          ? 'L\'ultimo tentativo non è riuscito.'
          : 'L\'ultimo tentativo non è riuscito · aggiornata fino al '
              '${_fmtWhen(sync.lastSyncAt!)}.',
      SyncTruth.spenta => 'Nessuno l\'ha accesa su questo dispositivo.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            attiva ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: attiva ? AppColors.accent : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(attiva ? 'Attiva' : 'Non attiva', style: _kItemTitle),
                const SizedBox(height: 4),
                const Text(
                  'Film e serie li riprendi dal punto esatto su ogni '
                  'dispositivo: quello che guardi in salotto lo continui dal '
                  'telefono da dove sei rimasto, e i preferiti sono gli stessi '
                  'ovunque.',
                  style: _kItemDesc,
                ),
                // Solo quando non è attiva: dirlo mentre funziona sarebbe una
                // riga di istruzioni per una cosa già fatta.
                if (!attiva) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Si accende solo dal pannello di chi ti ha dato '
                    'l\'applicazione, perché ha un costo aggiuntivo.',
                    style: _kItemDesc,
                  ),
                ],
                const SizedBox(height: 6),
                Text(detail, style: _kItemDesc),
              ],
            ),
          ),
        ],
      ),
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
