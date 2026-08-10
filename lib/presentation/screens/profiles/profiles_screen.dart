import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/xtream_profile.dart';
import '../../../state/profile_providers.dart';
import '../../../state/provisioning_providers.dart';
import '../../common/app_dialogs.dart';
import '../../common/ask_for_help.dart';
import '../../common/app_logo.dart';
import '../../common/icon_action.dart';
import '../../common/tv_focusable.dart';

class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  Timer? _provisionTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // ⚠️ This — not the add-playlist form — is the first screen after the
    // device picker, so it is where someone who can't set the app up alone
    // actually stops. Shipping the code and the wait only on the form meant
    // the person never got that far: reported the day 1.9.0 went out ("non
    // gli dà il codice dispositivo sotto"). Both live here now.
    if (ref.read(profilesProvider).isEmpty && !underFlutterTest) {
      _provisionTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _checkForPlaylist(),
      );
      _checkForPlaylist();
    }
  }

  Future<void> _checkForPlaylist() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final applied = await ref.read(provisioningProvider.notifier).checkAndApply();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: tvBackButton(context),
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
      ),
      body: profiles.isEmpty
          ? _EmptyState(
              onAdd: () => context.push('/profiles/add'),
              code: ref.watch(deviceCodeProvider),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: profiles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final profile = profiles[index];
                return _ProfileTile(
                  profile: profile,
                  autofocus: index == 0,
                  onSelect: () => context.push('/profiles/add', extra: profile),
                  onEdit: () => context.push('/profiles/add', extra: profile),
                  onDelete: () => _confirmDelete(context, ref, profile),
                );
              },
            ),
      // One D-pad stop with a visible ring: a bare FAB has invisible focus with
      // this theme, so on TV this was the unreachable-looking way to add a
      // SECOND playlist. Black ring — the FAB is white.
      floatingActionButton: profiles.isEmpty
          ? null
          : TvFocusable(
              borderRadius: 16,
              onTap: () => context.push('/profiles/add'),
              child: ExcludeFocus(
                child: FloatingActionButton.extended(
                  onPressed: () => context.push('/profiles/add'),
                  icon: const Icon(Icons.add),
                  label: const Text('Aggiungi playlist'),
                ),
              ),
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, XtreamProfile profile) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Eliminare playlist?',
      message: '"${profile.name}" verrà rimossa insieme alle credenziali salvate.',
      confirmLabel: 'Elimina',
    );
    if (confirmed) {
      await ref.read(profilesProvider.notifier).remove(profile.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.code});

  final VoidCallback onAdd;
  final String code;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No big icon here: this screen must fit WITHOUT scrolling. On a
          // D-pad the list only scrolls by following the focus, and the help
          // block below is plain text, so anything that doesn't fit is
          // unreachable — the defect reported on the add form.
          Text('Nessuna playlist', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Aggiungi le credenziali Xtream Codes per iniziare',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          // D-pad: the fresh-install flow lands here right after the device
          // picker — the remote needs a focused button to press OK on, WITH a
          // visible ring (black: the button is white). One focus stop only.
          TvFocusable(
            borderRadius: 14,
            autofocus: true,
            onTap: onAdd,
            child: ExcludeFocus(
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi playlist'),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AskForHelpWithCode(code: code),
          ),
        ],
      ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    this.autofocus = false,
  });

  final XtreamProfile profile;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // select · modifica · elimina as three side-by-side D-pad focus stops. The
    // edit/delete buttons used to be nested inside the tile's TvFocusable, where
    // a remote could never move focus into them; as siblings each is reachable
    // with its own focus ring.
    return Card(
      child: Row(
        children: [
          Expanded(
            child: TvFocusable(
              onTap: onSelect,
              autofocus: autofocus,
              borderRadius: 12,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.surfaceElevated,
                      child: Icon(Icons.playlist_play, color: AppColors.accent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${profile.username}@${profile.host}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconAction(icon: Icons.edit_outlined, onTap: onEdit, tooltip: 'Modifica'),
          IconAction(icon: Icons.delete_outline, onTap: onDelete, tooltip: 'Elimina'),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

