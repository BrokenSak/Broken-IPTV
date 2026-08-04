import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui_mode.dart';
import '../../../data/models/xtream_profile.dart';
import '../../../data/services/xtream_api_service.dart';
import '../../../state/profile_providers.dart';
import '../../common/tv_focusable.dart';
import '../../common/tv_text_field.dart';

class AddProfileScreen extends ConsumerStatefulWidget {
  const AddProfileScreen({super.key, this.existingProfile});

  final XtreamProfile? existingProfile;

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

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    _kind = p?.kind ?? PlaylistKind.xtream;
    _nameController = TextEditingController(text: p?.name ?? '');
    _usernameController = TextEditingController(text: p?.username ?? '');
    _passwordController = TextEditingController();
    _hostController = TextEditingController(text: p?.host ?? '');
    _m3uController = TextEditingController(text: p?.m3uUrl ?? '');
    _epgController = TextEditingController(text: p?.epgUrl ?? '');

    if (_isEditing && p!.kind == PlaylistKind.xtream) {
      ref.read(profileRepositoryProvider).getPassword(p.id).then((pw) {
        if (pw != null && mounted) _passwordController.text = pw;
      });
    }
  }

  @override
  void dispose() {
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
    final id = widget.existingProfile?.id ?? repo.newId();

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

    final profiles = ref.read(profilesProvider);
    if (!_isEditing && profiles.length == 1) {
      // First playlist ever: select it and enter the app directly.
      ref.read(selectedProfileIdProvider.notifier).select(profile.id);
      context.go('/home');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: tvBackButton(context),
        title: Text(_isEditing ? 'Modifica playlist' : 'Nuova playlist'),
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
              ringColor: Colors.black,
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
