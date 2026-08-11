import 'package:flutter/material.dart';

import '../../data/services/provisioning_service.dart';

/// "Can't do this yourself? Read this code to whoever gave you the app."
///
/// Shown on **both** first-run screens — the empty playlist list and the add
/// form. Putting it only on the form was the whole reason it failed the first
/// time it met a real person: the list is what you land on after the device
/// picker, and someone who can't fill a playlist in doesn't press "Aggiungi
/// playlist" to go looking for help.
///
/// Plain text on purpose: nothing here is interactive, so a D-pad never stops
/// on it — a focus stop that does nothing is exactly the defect this project
/// keeps fixing.
class AskForHelpWithCode extends StatelessWidget {
  const AskForHelpWithCode({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'La playlist te la mette chi ti ha dato questa applicazione.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Leggigli questo codice e arriva da sola, senza toccare niente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          DeviceCodeBox(code: code),
        ],
      ),
    );
  }
}

/// The code itself, in a box big enough to read out over the phone.
///
/// Plain text, never a focusable: it is shown on the setup screen **and** in
/// Impostazioni, and in both places it is something you read aloud, not
/// something you press.
class DeviceCodeBox extends StatelessWidget {
  const DeviceCodeBox({super.key, required this.code, this.fontSize = 24});

  final String code;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        DeviceCode.grouped(code),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          letterSpacing: 3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
