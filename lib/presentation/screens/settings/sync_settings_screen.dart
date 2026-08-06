import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/sync_merge.dart';
import '../../../state/sync_providers.dart';
import '../../common/app_dialogs.dart';
import '../../common/tv_focusable.dart';
import '../../common/tv_text_field.dart';

const _kItemTitle = TextStyle(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.bold,
);
const _kItemDesc = TextStyle(
  color: AppColors.textSecondary,
  fontStyle: FontStyle.italic,
);

/// Types the sync code for you: uppercase, junk dropped, capped at 12 and
/// grouped as `ABCD-EFGH-JKLM` — the separator appearing as soon as a group of
/// four is complete, so it is visibly automatic and nobody adds one by hand.
class SyncCodeFormatter extends TextInputFormatter {
  const SyncCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    // Shorter than before = deleting, which suppresses the trailing separator
    // (see syncCodeAsTyped) so backspace can get past it.
    final text = syncCodeAsTyped(
      next.text,
      deleting: next.text.length < old.text.length,
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The editable side of the sync settings, on its own screen.
///
/// Settings only shows the state; the fields live here — same shape as the
/// playlists, where the box is a summary and everything editable is behind
/// "modifica". Keeps a working sync code out of reach of a stray tap.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _codeCtrl;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    final sync = ref.read(syncProvider);
    _endpointCtrl = TextEditingController(text: sync.endpoint);
    _codeCtrl = TextEditingController(
      text: sync.code == null ? '' : formatSyncCode(sync.code!),
    );
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(syncProvider.notifier);
    notifier.setEndpoint(_endpointCtrl.text);
    final raw = _codeCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _codeError = 'Inserisci o genera un codice.');
      return;
    }
    if (!notifier.setCode(raw)) {
      setState(() => _codeError = 'Codice non valido: servono 12 caratteri.');
      return;
    }
    setState(() => _codeError = null);
    await notifier.syncNow();
    if (!mounted) return;
    final error = ref.read(syncProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Sincronizzazione completata.')),
    );
    if (error == null && context.canPop()) context.pop();
  }

  Future<void> _generate() async {
    // Generating replaces a code that other devices may already be using, so
    // it asks first — the old one is not recoverable from here.
    if (ref.read(syncProvider).code != null) {
      final ok = await showAppConfirmDialog(
        context,
        title: 'Generare un nuovo codice?',
        message: 'Questo dispositivo smetterà di sincronizzarsi con gli altri, '
            'che continueranno a usare il codice attuale.',
        confirmLabel: 'Genera',
      );
      if (!ok) return;
    }
    final code = ref.read(syncProvider.notifier).createCode();
    _codeCtrl.text = formatSyncCode(code);
    ref.read(syncProvider.notifier).setEndpoint(_endpointCtrl.text);
    setState(() => _codeError = null);
  }

  Future<void> _disable() async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Disattivare la sincronizzazione?',
      message: 'I preferiti e "Continua a guardare" di questo dispositivo restano '
          'come sono. Gli altri dispositivi continuano a sincronizzarsi.',
      confirmLabel: 'Disattiva',
    );
    if (!ok) return;
    ref.read(syncProvider.notifier).disable();
    _codeCtrl.clear();
    setState(() => _codeError = null);
    if (mounted && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: tvBackButton(context),
        title: const Text('Sincronizzazione'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Tiene allineati preferiti e "Continua a guardare" tra telefono, TV e PC. '
            'Usa lo stesso codice su ogni dispositivo. Le playlist e le password NON '
            'vengono sincronizzate.',
            style: _kItemDesc,
          ),
          const SizedBox(height: 20),
          TvTextFormField(
            controller: _codeCtrl,
            // The remote's landing spot. Without it this screen opened with
            // NOTHING focused: OK did nothing at all, and the first arrow press
            // jumped up to the back button (seen on the Firestick). Navigation
            // focus, not editing — the keyboard should not pop up by itself.
            autofocusNavigation: true,
            inputFormatters: const [SyncCodeFormatter()],
            decoration: InputDecoration(
              labelText: 'Codice di sincronizzazione',
              hintText: 'ABCD-EFGH-JKLM',
              errorText: _codeError,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Su un altro dispositivo scrivi lo stesso codice: genera un codice nuovo '
            'solo sul primo.',
            style: _kItemDesc,
          ),
          const SizedBox(height: 16),
          TvTextFormField(
            controller: _endpointCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Indirizzo del servizio',
              hintText: 'https://...workers.dev',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Già compilato: cambialo solo se sai cosa stai facendo.',
            style: _kItemDesc,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TvFocusable(
                  borderRadius: 14,
                  onTap: sync.running ? () {} : _save,
                  child: _ActionChip(
                    label: sync.running ? 'Sincronizzo…' : 'Salva e sincronizza',
                    filled: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TvFocusable(
                  borderRadius: 14,
                  onTap: _generate,
                  child: const _ActionChip(label: 'Genera codice'),
                ),
              ),
            ],
          ),
          if (sync.enabled) ...[
            const SizedBox(height: 12),
            TvFocusable(
              onTap: _disable,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.link_off),
                title: Text('Disattiva su questo dispositivo', style: _kItemTitle),
                subtitle: Text(
                  'i dati locali restano; gli altri dispositivi continuano',
                  style: _kItemDesc,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Chiunque conosca il codice può leggere e modificare questi dati: '
            'trattalo come una password.',
            style: _kItemDesc,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, this.filled = false});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: filled ? Colors.white : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.black : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
