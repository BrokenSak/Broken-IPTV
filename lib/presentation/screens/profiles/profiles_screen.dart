import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/build_channel.dart';
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
/// Mostra il codice da dettare e **aspetta**: controlla ogni 10s, così la
/// playlist arriva mentre la persona sta ancora guardando lo schermo.
///
/// ⚠️ L'unico pulsante è la via a mano, e sta **sotto** il codice di proposito
/// (74° giro, richiesta dell'utente): prima si legge che non serve fare niente
/// se si parla con chi ha dato l'app, poi — per chi le credenziali ce le ha
/// già — c'è il modulo. La playlist resta comunque **una sola**: il modulo
/// sostituisce, non aggiunge.
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
            if (kIsBeta) ...[
              const SizedBox(width: 10),
              // ⚠️ Le due copie hanno la stessa icona e lo stesso nome dentro
              // l'app: senza questo, una volta configurate, non si distinguono
              // più e finiresti per provare la versione sbagliata.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  kChannelLabel,
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
              const SizedBox(height: 14),
              AskForHelpWithCode(code: code),
              const SizedBox(height: 16),
              // ⚠️ L'ordine è la richiesta dell'utente (74° giro): prima il
              // codice e la frase che spiega che NON serve fare niente, e solo
              // dopo la via a mano — in secondo piano, per chi le credenziali
              // ce le ha già. Se stesse in cima, chi non le ha si metterebbe a
              // compilare un modulo che non sa compilare: è esattamente il
              // difetto del 69° giro, al contrario.
              const Text(
                'Hai già indirizzo, utente e password?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              TvFocusable(
                borderRadius: 14,
                autofocus: true,
                onTap: () => context.push('/profiles/add'),
                child: ExcludeFocus(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/profiles/add'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Inseriscila a mano'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
