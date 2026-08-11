import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/catalog_refresh.dart';

/// Il riquadro che copre la schermata mentre la lista si aggiorna.
///
/// ⚠️ Blocca **davvero**, ed è la richiesta dell'utente: "se mi lasci la
/// possibilità di continuare a fare cose l'app mi lagga". Con una sola
/// connessione verso il pannello è esattamente ciò che succede — mentre
/// scarichi i cataloghi, ogni altra cosa che l'app chiede si accoda dietro e
/// sembra che l'app si sia impuntata. Meglio fermare tutto per venti secondi e
/// **dirlo**, che lasciar credere che sia rotta.
///
/// Come blocca:
///  * è una route modale, quindi i tocchi e i clic non arrivano sotto;
///  * `PopScope(canPop: false)` mangia il tasto Indietro del telecomando;
///  * non contiene **nessun** elemento focusabile, quindi col D-pad non c'è
///    niente da premere per sbaglio.
///
/// Non ha un pulsante per chiudere di proposito: dura quanto l'aggiornamento e
/// si chiude da solo. Se il pannello non risponde, la chiamata scade da sé
/// (timeout di Dio) e il riquadro se ne va con il messaggio d'errore.
Future<void> mostraAggiornamentoInCorso(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => const _RiquadroAggiornamento(),
  );
}

class _RiquadroAggiornamento extends ConsumerWidget {
  const _RiquadroAggiornamento();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stato = ref.watch(catalogRefreshingProvider);
    final quanti = stato.totale == 0 ? '' : '${stato.passo} di ${stato.totale}';

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 22),
              Text(
                'Sto aggiornando la lista',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                stato.cosa.isEmpty
                    ? 'Un momento...'
                    : 'Scarico ${stato.cosa}${quanti.isEmpty ? '' : '  ·  $quanti'}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Finché non ho finito l\'app non risponde: sta parlando col '
                'pannello, e una cosa per volta.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
