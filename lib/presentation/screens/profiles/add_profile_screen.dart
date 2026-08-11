import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui_mode.dart';
import '../../../data/models/xtream_profile.dart';
import '../../../data/services/xtream_api_service.dart';
import '../../../state/profile_providers.dart';
import '../../../state/provisioning_providers.dart';
import '../../common/tv_focusable.dart';
import '../../common/tv_text_field.dart';

/// Il modulo per scrivere la playlist a mano.
///
/// ⚠️ Ci si arriva **solo** dalla schermata di attesa, e solo dopo aver letto
/// il codice del dispositivo e la frase che spiega che non serve fare niente
/// (72°/74° giro): l'inserimento a mano è la via di riserva per chi le
/// credenziali ce le ha già in mano, non la strada principale. Non modifica
/// niente: scrive **l'unica** playlist del dispositivo, che resta una sola.
class AddProfileScreen extends ConsumerStatefulWidget {
  const AddProfileScreen({super.key});

  @override
  ConsumerState<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends ConsumerState<AddProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _hostController;
  late final TextEditingController _m3uController;
  late final TextEditingController _epgController;

  bool _obscurePassword = true;
  bool _saving = false;
  late PlaylistKind _kind;

  /// Set only on the first-playlist screen: see [_waitForPlaylist].
  Timer? _provisionTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _kind = PlaylistKind.xtream;
    _nameController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _hostController = TextEditingController();
    _m3uController = TextEditingController();
    _epgController = TextEditingController();

    // First playlist ever: the owner may be filling it in from the panel right
    // now, while the person holds the phone. Watch for it instead of making
    // them close and reopen the app.
    //
    // Not under `flutter test`: a real HTTP call there leaves Dio's timer
    // pending under the fake clock and fails suites that only wanted to look
    // at this screen. What it does is covered without a widget, by driving
    // `provisioningProvider` over a fake service (provisioning_apply_test).
    if (ref.read(profilesProvider).isEmpty && !underFlutterTest) {
      _waitForPlaylist();
    }
  }

  /// Polls the service while this screen is open. Ten seconds is short enough
  /// to feel immediate during a phone call and rare enough to be nothing at
  /// all for the free plan; the timer dies with the screen.
  void _waitForPlaylist() {
    _provisionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkForPlaylist();
    });
    _checkForPlaylist();
  }

  Future<void> _checkForPlaylist() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final applied =
          await ref.read(provisioningProvider.notifier).checkAndApply();
      if (applied && mounted) {
        _provisionTimer?.cancel();
        context.go('/home');
      }
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _provisionTimer?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    _m3uController.dispose();
    _epgController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repo = ref.read(profileRepositoryProvider);
    // Una sola playlist: se per qualsiasi motivo ce n'è già una, questa la
    // SOSTITUISCE invece di affiancarsene un'altra.
    final id = ref.read(profilesProvider).firstOrNull?.id ?? repo.newId();

    final XtreamProfile profile;
    String? password;
    if (_kind == PlaylistKind.m3u) {
      profile = XtreamProfile(
        id: id,
        name: _nameController.text.trim(),
        host: '',
        username: '',
        kind: PlaylistKind.m3u,
        m3uUrl: _m3uController.text.trim(),
        epgUrl: _epgController.text.trim().isEmpty ? null : _epgController.text.trim(),
      );
    } else {
      profile = XtreamProfile(
        id: id,
        name: _nameController.text.trim(),
        host: XtreamApiService.normalizeHost(_hostController.text),
        username: _usernameController.text.trim(),
        kind: PlaylistKind.xtream,
      );
      password = _passwordController.text;
    }

    await ref.read(profilesProvider.notifier).upsert(profile, password: password);

    if (!mounted) return;
    setState(() => _saving = false);

    ref.read(selectedProfileIdProvider.notifier).select(profile.id);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: tvBackButton(context),
        title: const Text('Playlist a mano'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Playlist type selector.
            Row(
              children: [
                Expanded(
                  child: _TypeChip(
                    label: 'Xtream Codes',
                    selected: _kind == PlaylistKind.xtream,
                    onTap: () => setState(() => _kind = PlaylistKind.xtream),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeChip(
                    label: 'M3U / Link',
                    selected: _kind == PlaylistKind.m3u,
                    onTap: () => setState(() => _kind = PlaylistKind.m3u),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TvTextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Playlist'),
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
            ),
            const SizedBox(height: 16),
            if (_kind == PlaylistKind.xtream) ...[
              TvTextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TvTextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        // On TV the reveal toggle sits BESIDE the field (below):
                        // a suffix icon lives inside the field, whose subtree is
                        // skipTraversal, so a D-pad can never reach it. Touch and
                        // mouse keep it inline as a suffix.
                        suffixIcon: isTvMode()
                            ? null
                            : IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                              ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.isEmpty) ? 'Obbligatorio' : null,
                    ),
                  ),
                  // TV: separate focusable button so the remote can reveal the
                  // password (see the note above).
                  if (isTvMode()) ...[
                    const SizedBox(width: 8),
                    TvFocusable(
                      borderRadius: 12,
                      onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TvTextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Link',
                  hintText: 'http://server.example.com:8080',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
              ),
            ] else ...[
              TvTextFormField(
                controller: _m3uController,
                decoration: const InputDecoration(
                  labelText: 'Link M3U',
                  hintText: 'http://server/get.php?...&type=m3u_plus',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
              ),
              const SizedBox(height: 16),
              TvTextFormField(
                controller: _epgController,
                decoration: const InputDecoration(
                  labelText: 'Link EPG (XMLTV) — opzionale',
                  hintText: 'http://server/xmltv.php?... (.xml o .xml.gz)',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
              ),
            ],
            const SizedBox(height: 24),
            // One D-pad stop with a visible (black-on-white) ring; the inner
            // button is not a second focus stop.
            TvFocusable(
              borderRadius: 14,
              onTap: () {
                if (!_saving) _save();
              },
              child: ExcludeFocus(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Salva'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // TvFocusable (not a bare GestureDetector) so the type can also be
    // switched with a TV remote.
    return TvFocusable(
      borderRadius: 14,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
