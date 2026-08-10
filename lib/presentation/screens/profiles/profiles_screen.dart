import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../state/profile_providers.dart';
import '../../../state/provisioning_providers.dart';
import '../../common/ask_for_help.dart';
import '../../common/update_banner.dart';
import '../../common/app_logo.dart';
import '../../common/tv_focusable.dart';

/// The screen of a device that has no playlist yet.
///
/// ⚠️ There is nothing to press here, and that is deliberate (72° giro): the
/// playlist is **one**, and it is the one the owner sends from the panel. This
/// screen's whole job is to show the code to read out loud and to wait — it
/// polls every 10s, so the playlist lands while the person is still looking at
/// it.
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
    // ⚠️ This is the first screen after the device picker, so it is where
    // someone who can't set the app up alone actually stops. Shipping the code
    // only on the (now removed) add form meant the person never got that far:
    // reported the day 1.9.0 went out ("non gli dà il codice dispositivo").
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
      body: Column(
        children: [
          // ⚠️ Also here, not just on the home: a device without a playlist
          // never reaches the home, so the person who most needs a fix could
          // never be offered one ("non mi dice aggiorna").
          const UpdateBanner(),
          Expanded(child: _WaitingForPlaylist(code: ref.watch(deviceCodeProvider))),
        ],
      ),
    );
  }
}

class _WaitingForPlaylist extends StatelessWidget {
  const _WaitingForPlaylist({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // No big icon and nothing to press: on a D-pad a list only
              // scrolls by following the focus, so anything that doesn't fit
              // on one screen is unreachable. Everything here is plain text.
              Text(
                'Nessuna playlist',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Sto aspettando: arriva da sola appena viene configurata.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              AskForHelpWithCode(code: code),
            ],
          ),
        ),
      ),
    );
  }
}
