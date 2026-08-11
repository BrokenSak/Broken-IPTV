import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/fullscreen.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'state/provisioning_providers.dart';
import 'state/sync_providers.dart';
import 'state/update_providers.dart';

class BrokenIptvApp extends ConsumerStatefulWidget {
  const BrokenIptvApp({super.key});

  @override
  ConsumerState<BrokenIptvApp> createState() => _BrokenIptvAppState();
}

class _BrokenIptvAppState extends ConsumerState<BrokenIptvApp> {
  AppLifecycleListener? _lifecycle;

  /// When the update check last ran, so coming back to the front doesn't
  /// re-fetch on every window focus (desktop reports one per focus change).
  DateTime _lastUpdateCheck = DateTime.now();
  static const _updateRecheckInterval = Duration(minutes: 30);

  /// Lo stesso, per la playlist lasciata dal pannello: un dispositivo acceso e
  /// lasciato lì non si accorgeva di un indirizzo corretto finché qualcuno non
  /// riapriva l'app da zero. Ora basta tornarci sopra.
  DateTime _lastProvisionCheck = DateTime.now();
  static const _provisionRecheckInterval = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    // Android fullscreen is permanent: the system puts the bars back after an
    // app switch (and sometimes after dialogs/keyboard), so re-assert it on
    // every resume — there is no way to turn it off.
    // The same listener carries the sync's upload trigger: going to the
    // background is the one moment we know the user isn't mid-action.
    // Registered on every platform (not just Android) because the update
    // re-check below matters just as much on the desktop.
    _lifecycle = AppLifecycleListener(
      onResume: _onResume,
      onPause: _syncInBackground,
    );
    // Reconciliation at startup: pulls what the other devices did and pushes
    // anything a crash (or a swipe-kill) left unsent. No-op when sync is off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(syncProvider.notifier).syncNow());
    });
  }

  void _onResume() {
    if (Platform.isAndroid) applyAndroidImmersive();
    // The startup check is a one-shot, so an app left open never noticed a
    // release: a version published while it sat on the home screen only showed
    // up after a restart (reported — "non vedo aggiornamenti"). Re-check when
    // the app comes back to the front, rate-limited because on desktop this
    // fires on every window focus.
    if (DateTime.now().difference(_lastUpdateCheck) > _updateRecheckInterval) {
      _lastUpdateCheck = DateTime.now();
      ref.invalidate(updateCheckProvider);
    }
    // Idem per il pannello: se il proprietario corregge l'indirizzo mentre la
    // TV è accesa, prima bisognava chiudere e riaprire l'app. Ora arriva al
    // primo ritorno in primo piano. Stesso freno di sopra, perché su desktop
    // questo scatta a ogni cambio di finestra.
    if (!underFlutterTest &&
        DateTime.now().difference(_lastProvisionCheck) > _provisionRecheckInterval) {
      _lastProvisionCheck = DateTime.now();
      unawaited(ref.read(provisioningProvider.notifier).checkAndApply());
    }
  }

  void _syncInBackground() {
    unawaited(ref.read(syncProvider.notifier).syncIfChanged());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Broken IPTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      builder: (context, child) {
        // NB: the abstract background is applied per-screen (see app_router)
        // so each pushed page is opaque and fully covers the previous one
        // during transitions — no see-through flash.
        Widget content = child ?? const SizedBox.shrink();
        // On Windows we drive the UI with mouse + keyboard only: swallow the
        // arrow keys at the root so they never trigger focus traversal.
        // Text fields' own handlers sit nearer the focus and still win.
        if (Platform.isWindows) {
          content = Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowUp): DoNothingAndStopPropagationIntent(),
              SingleActivator(LogicalKeyboardKey.arrowDown): DoNothingAndStopPropagationIntent(),
              SingleActivator(LogicalKeyboardKey.arrowLeft): DoNothingAndStopPropagationIntent(),
              SingleActivator(LogicalKeyboardKey.arrowRight): DoNothingAndStopPropagationIntent(),
            },
            child: content,
          );
        } else if (Platform.isAndroid) {
          // TV/remote: tell the framework a directional pad drives navigation.
          // Without this a focused Slider (the player's seek bar) eats Up/Down
          // to nudge its value and TRAPS the D-pad on it — in directional mode
          // a Slider only takes Left/Right, so Up/Down move focus off it to the
          // buttons. Harmless on a touch phone (no arrow keys are ever sent).
          content = MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(navigationMode: NavigationMode.directional),
            child: content,
          );
        }
        return content;
      },
    );
  }
}
