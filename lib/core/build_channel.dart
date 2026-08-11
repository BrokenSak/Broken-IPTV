/// Da quale canale viene questa build.
///
/// Si decide al momento della compilazione (`--dart-define=BETA=true`) e non a
/// runtime: una copia di prova e una vera devono poter **convivere sullo stesso
/// dispositivo**, e per farlo devono essere due applicazioni diverse fin dal
/// pacchetto — non la stessa app con un interruttore dentro.
///
/// Su Android il pacchetto cambia con il flavor `prova`
/// (`…broken_iptv.prova`), su Windows con un installer separato: qui restano le
/// tre conseguenze che riguardano il codice.
const bool kIsBeta = bool.fromEnvironment('BETA');

/// Come si chiama questa copia quando bisogna dirlo a schermo.
const String kChannelLabel = kIsBeta ? 'PROVA' : '';

/// Le due copie **non devono mescolare i dati**: playlist, codice del
/// dispositivo, preferiti e progressi sono cose diverse.
///
/// Su Android arriva gratis (pacchetto diverso = cartella diversa). Su Windows
/// no: Hive scrive nella cartella Documenti dell'utente, che è la stessa per
/// tutti e due — senza questo sottolivello la copia di prova aprirebbe i box
/// della copia vera e ci scriverebbe dentro.
const String? kDataSubdirectory = kIsBeta ? 'Broken IPTV Prova' : null;

/// La copia di prova **non si aggiorna da sola**.
///
/// Il file degli aggiornamenti descrive la copia vera, che ha un altro
/// pacchetto: seguirlo vorrebbe dire proporre "aggiorna" e poi installare
/// l'altra app di fianco, per sempre. Una build di prova si installa a mano,
/// che è esattamente il punto del canale di prova.
const bool kUpdatesEnabled = !kIsBeta;
