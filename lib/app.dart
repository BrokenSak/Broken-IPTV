import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/fullscreen.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class BrokenIptvApp extends StatefulWidget {
  const BrokenIptvApp({super.key});

  @override
  State<BrokenIptvApp> createState() => _BrokenIptvAppState();
}

class _BrokenIptvAppState extends State<BrokenIptvApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Android fullscreen is permanent: the system puts the bars back after an
    // app switch (and sometimes after dialogs/keyboard), so re-assert it on
    // every resume — there is no way to turn it off.
    if (Platform.isAndroid) {
      _lifecycle = AppLifecycleListener(onResume: () => applyAndroidImmersive());
    }
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
