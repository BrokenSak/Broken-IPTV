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
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Non riesci a compilarla da solo?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Chiedi a chi ti ha dato questa applicazione e leggigli questo '
            'codice: la playlist arriva da sola, senza toccare niente.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              DeviceCode.grouped(code),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 26,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
