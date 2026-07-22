import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/fullscreen.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'state/sync_providers.dart';

class BrokenIptvApp extends ConsumerStatefulWidget {
  const BrokenIptvApp({super.key});

  @override
  ConsumerState<BrokenIptvApp> createState() => _BrokenIptvAppState();
}

class _BrokenIptvAppState extends ConsumerState<BrokenIptvApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Android fullscreen is permanent: the system puts the bars back after an
    // app switch (and sometimes after dialogs/keyboard), so re-assert it on
    // every resume — there is no way to turn it off.
    // The same listener carries the sync's upload trigger: going to the
    // background is the one moment we know the user isn't mid-action.
    if (Platform.isAndroid) {
      _lifecycle = AppLifecycleListener(
        onResume: () => applyAndroidImmersive(),
        onPause: _syncInBackground,
      );
    }
    // Reconciliation at startup: pulls what the other devices did and pushes
    // anything a crash (or a swipe-kill) left unsent. No-op when sync is off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(syncProvider.notifier).syncNow());
    });
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
        }
        return content;
      },
    );
  }
}
