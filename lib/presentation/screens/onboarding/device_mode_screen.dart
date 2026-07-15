import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/device_mode_service.dart';
import '../../common/glass_surface.dart';
import '../../common/tv_focusable.dart';

class DeviceModeScreen extends StatefulWidget {
  const DeviceModeScreen({super.key});

  @override
  State<DeviceModeScreen> createState() => _DeviceModeScreenState();
}

class _DeviceModeScreenState extends State<DeviceModeScreen> {
  final _service = DeviceModeService();
  DeviceMode? _suggested;

  @override
  void initState() {
    super.initState();
    _service.detectIsTv().then((isTv) {
      if (mounted) setState(() => _suggested = isTv ? DeviceMode.tv : DeviceMode.touch);
    });
  }

  Future<void> _choose(DeviceMode mode) async {
    await _service.save(mode);
    if (!mounted) return;
    context.go('/profiles');
  }

  @override
  Widget build(BuildContext context) {
    // Must fit every screen, from a small phone (landscape height can be
    // ~330dp) up to a huge TV: compact metrics on low screens, cards stacked
    // vertically on narrow ones, and a scroll view as the safety net so the
    // content can never run off-screen.
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 480;
            final narrow = constraints.maxWidth < 460;

            final cards = [
              _ModeCard(
                icon: Icons.tv,
                title: 'TV / Telecomando',
                subtitle: 'Firestick, Android TV e simili',
                suggested: _suggested == DeviceMode.tv,
                autofocus: true,
                compact: compact,
                onTap: () => _choose(DeviceMode.tv),
              ),
              _ModeCard(
                icon: Icons.smartphone,
                title: 'Telefono / Tablet',
                subtitle: 'Tocco e schermo touch',
                suggested: _suggested == DeviceMode.touch,
                compact: compact,
                onTap: () => _choose(DeviceMode.touch),
              ),
            ];

            return SingleChildScrollView(
              child: ConstrainedBox(
                // Fill the screen so the content stays centered when it fits;
                // when it doesn't, the scroll view takes over.
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: compact ? 12 : 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.live_tv,
                              size: compact ? 40 : 56, color: AppColors.accent),
                          SizedBox(height: compact ? 8 : 16),
                          Text('Come stai guardando?',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 8),
                          Text(
                            'Adattiamo la navigazione al tuo dispositivo. Puoi cambiarla in qualsiasi momento dalle Impostazioni.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          SizedBox(height: compact ? 16 : 40),
                          if (narrow)
                            Column(
                              children: [
                                cards[0],
                                const SizedBox(height: 14),
                                cards[1],
                              ],
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: cards[0]),
                                const SizedBox(width: 20),
                                Expanded(child: cards[1]),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.suggested = false,
    this.autofocus = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool suggested;
  final bool autofocus;

  /// Tighter paddings/icon for screens with little height (phone landscape).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onTap: onTap,
      child: GlassSurface(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 14 : 32, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: compact ? 30 : 40, color: AppColors.accent),
              SizedBox(height: compact ? 8 : 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              if (suggested) ...[
                SizedBox(height: compact ? 8 : 12),
                const Chip(
                  label: Text('Consigliato', style: TextStyle(color: Colors.black)),
                  backgroundColor: Colors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
