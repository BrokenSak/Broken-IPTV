import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/services/provisioning_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.uri.path);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

/// La playlist che il pannello consegna a un dispositivo.
///
/// ⚠️ Il cifrato qui sotto è stato prodotto **dal browser** (WebCrypto, lo
/// stesso codice che gira in `sync_worker/src/admin.html.js`), non da Dart:
/// è l'unico modo di accorgersi se le due implementazioni smettono di
/// parlarsi — nonce di lunghezza diversa, tag in coda invece che in testa,
/// derivazione della chiave cambiata da un lato solo. Un round-trip
/// Dart→Dart passerebbe anche con il formato sbagliato.
///
/// Questo è il **formato vecchio** (la playlist dentro lo slot del
/// dispositivo), quello dei dispositivi configurati prima delle utenze: deve
/// continuare ad aprirsi.
const _fromPanel =
    'Uk+VyCo89axY00NVP+I1cVJ+YmjxiAZcK4mWjH/wdARki8EWHRpbzAe6GduIXJ7gDuK6/2rb'
    'R4gGyzutXZo7TSGRkG0ISL8ziYIf0HXldgFEVeNd1FvxDNgHjYVSBlGQqWEJFViD7R4Pjy/5'
    'C4y3tiOlShaeH3GiXY1hh9lcnfM7nIXPRzCNqmf7+TPDoLF6Kjn8yaoZMfCGTgZqjDk1rA==';
const _code = 'ABCDEFGHJKLM';

/// Le due caselle del giro delle utenze, **prodotte anche queste dal pannello
/// vero** guidato in un browser vero contro un Worker locale:
///
///  * [_casellina] sta nello slot del dispositivo ed è cifrata col suo codice.
///    Dentro c'è solo l'indirizzo dell'utenza e il suo codice.
///  * [_playlistUtenza] è la playlist condivisa, cifrata col **codice
///    dell'utenza** — che il pannello ricava con HMAC dal token e non salva da
///    nessuna parte. Il test non ha bisogno di conoscerlo: lo legge dalla
///    casellina, esattamente come fa l'app. Se un giorno il pannello cambiasse
///    derivazione o formato, questa catena si spezzerebbe qui.
const _casellina =
    'jmxyZdbhC7tvrGpqeyMXyO/0aVx3S+7IcSdAJHPSzyprS6cM8mCdOPRKS3T60+9B68HJwfI4'
    'FRy9iN/YyIspNg3wB5VUVU3w4TP0+Lv9C9B1XFirwhkt1oTM01mzEH+EOwWTXiJLjs6T6VcA'
    'DXZY7BTwu0/dyg2p';
const _playlistUtenza =
    'EtDBuCOvTuQefIY7omEUf/2sQp481FRJbBF2uCRGabJB+FTkb+DZVBONH40WUtn6OnENLR2q'
    '1LBGs0ThgQHATGDaEOI/na4H0uR5b13JwjyvnA9p9L00L1bRsXdLZ4eOHa2mM9yZNPX8Uumt'
    'yp7W2teAAgXtiBoWAfpEm8iNBWrwK04M2svPXjs62YiO1H0o';
const _accountId = '9d0bccd597a6cb9d307c7f69d3610770';
const _accountCode = 'VWL29SGWJZW7';

/// L'**indirizzo solo per questo dispositivo** (82° giro): stesso abbonamento,
/// altra porta d'ingresso. Anche questi due cifrati vengono dal pannello vero
/// guidato in un browser vero — l'utenza `Prova82` sta su
/// `http://uno.tv:8080` con utente `u1`, e la casellina del dispositivo porta
/// `host: http://due.tv:9090`.
///
/// È la coppia che dimostra la cosa che conta: l'eccezione sta nella casellina
/// (l'unico posto che è di **un** dispositivo), mentre utente, password e
/// codice di sincronizzazione continuano ad arrivare dall'utenza — cioè i
/// preferiti restano condivisi, che era il motivo per cui una seconda utenza
/// non andava bene.
const _casellinaConIndirizzo =
    'oqfWIO7BvRjFW9UcuHPyJxk+HQaWzM6datRdbfmAYfJ6CGp1E1/jvtgWAEG3LmmMhxJt9XrS'
    'LR8jmd+Dvy9UdRbs2TeJ4zwXiPW0lZQMNjzoEHoPD+71meHpol4xFEWPANazQlc+QzXjW7zk'
    'XSywnMZDfz3oOGKTaD2FoXjMu8zo0o99e6++psYwvAeHGi4b7FUmOA==';
const _playlistProva82 =
    'P1hkloX3seQvhbOynbubmPHhoNptqpW7/Lij7jSzX3t7H0ffDHBhgNPYL+QwMWauv6FM/n0c'
    'F52pAdfjuOlmBzUq077DtxBarbd1dEYctQNg1o7FbsgBdUv3etJJaXwRoIDaKE38OojVn/oM'
    '5g88XlFbreTra62gBkReV4k=';
const _accountIdProva82 = 'a50133be21189bce9dfcb298bdd911b6';

void main() {
  group('decifratura di quello che manda il pannello', () {
    test('apre il blob cifrato dal browser', () async {
      final payload = await decryptProvisioning(_fromPanel, _code);
      expect(payload, isNotNull);
      expect(payload!['host'], 'http://esempio.tv:8080');
      expect(payload['username'], 'mamma');
      expect(payload['password'], 'segreta');
      expect(payload['name'], 'Casa');
      expect(payload['syncCode'], 'MNPQRSTUVWXY');
    });

    test('con il codice sbagliato non apre niente (e non esplode)', () async {
      // È la garanzia che rende innocuo un dump del database: senza il codice
      // quei byte non sono nulla.
      expect(await decryptProvisioning(_fromPanel, 'MNPQRSTUVWXY'), isNull);
    });

    test('spazzatura, vuoto e blob troncato tornano null', () async {
      expect(await decryptProvisioning('', _code), isNull);
      expect(await decryptProvisioning('non-base64!!', _code), isNull);
      expect(await decryptProvisioning(_fromPanel.substring(0, 20), _code), isNull);
    });
  });

  group('quando applicare quello che è arrivato', () {
    test('la prima volta si applica sempre', () {
      expect(
        shouldApplyProvisioned(remoteUpdatedAt: 1000, appliedAt: null),
        isTrue,
      );
    });

    test('lo stesso invio non si riapplica a ogni avvio', () {
      // Senza questo, una playlist sistemata a mano verrebbe sovrascritta
      // dalla stessa copia remota a ogni apertura dell'app.
      expect(
        shouldApplyProvisioned(remoteUpdatedAt: 1000, appliedAt: 1000),
        isFalse,
      );
    });

    test('una correzione più recente si applica', () {
      // È il caso che rende utile il pannello: cambi indirizzo una volta e
      // tutti i dispositivi si allineano.
      expect(
        shouldApplyProvisioned(remoteUpdatedAt: 2000, appliedAt: 1000),
        isTrue,
      );
    });

    test('un invio più vecchio di quello già applicato si ignora', () {
      expect(
        shouldApplyProvisioned(remoteUpdatedAt: 500, appliedAt: 1000),
        isFalse,
      );
    });

    test('senza data non si applica niente', () {
      expect(
        shouldApplyProvisioned(remoteUpdatedAt: 0, appliedAt: null),
        isFalse,
      );
    });
  });

  group('come si legge il codice', () {
    test('a gruppi di quattro, come lo detti al telefono', () {
      expect(DeviceCode.grouped('ABCDEFGHJKLM'), 'ABCD-EFGH-JKLM');
    });

    test('regge anche una lunghezza non multipla di quattro', () {
      expect(DeviceCode.grouped('ABCDEF'), 'ABCD-EF');
      expect(DeviceCode.grouped(''), '');
    });
  });

  group('indirizzo chiamato dal dispositivo', () {
    test('non raddoppia la barra finale dell endpoint', () {
      expect(
        ProvisioningService.profileUri('https://x.dev/', 'ABCDEFGHJKLM').toString(),
        'https://x.dev/v1/profile/ABCDEFGHJKLM',
      );
      expect(
        ProvisioningService.accountUri('https://x.dev/', _accountId).toString(),
        'https://x.dev/v1/account/$_accountId',
      );
    });
  });

  group('dalla casellina alla playlist dell utenza', () {
    /// Il Worker come lo vede il dispositivo: la casellina nel suo slot, la
    /// playlist in quello dell'utenza.
    ({ProvisioningService service, _FakeAdapter adapter}) panel({
      String casellina = _casellina,
      int casellinaAt = 1000,
      String? playlist = _playlistUtenza,
      int accountAt = 2000,
      int sync = 1,
    }) {
      final adapter = _FakeAdapter((options) {
        if (options.uri.path.startsWith('/v1/profile/')) {
          return _json({'data': casellina, 'updatedAt': casellinaAt});
        }
        if (options.uri.path == '/v1/account/$_accountId') {
          if (playlist == null) return _json({'error': 'empty'}, 404);
          return _json({
            'data': playlist,
            'updatedAt': accountAt,
            'sync': sync,
          });
        }
        return _json({'error': 'not_found'}, 404);
      });
      return (
        service: ProvisioningService(dio: Dio()..httpClientAdapter = adapter),
        adapter: adapter,
      );
    }

    test('la casellina dice solo a quale utenza appartiene', () async {
      // Nessuna credenziale qui dentro: il dispositivo la usa per sapere dove
      // andare a prendere la playlist, e con che chiave aprirla.
      final payload = await decryptProvisioning(_casellina, _code);
      expect(payload, isNotNull);
      expect(payload!['account'], _accountCode);
      expect(payload['accountId'], _accountId);
      expect(payload.containsKey('password'), isFalse);
    });

    test('il codice dell utenza apre la playlist condivisa', () async {
      // La catena completa fatta a mano: è ciò che collega i due cifrati
      // prodotti dal browser. Se il pannello cambiasse la derivazione HMAC solo
      // da un lato, il codice nella casellina non aprirebbe più questo blob.
      final casellina = await decryptProvisioning(_casellina, _code);
      final playlist = await decryptProvisioning(
        _playlistUtenza,
        casellina!['account'].toString(),
      );
      expect(playlist, isNotNull);
      expect(playlist!['host'], 'http://esempio.tv:8080');
      expect(playlist['username'], 'mamma2026');
      expect(playlist['password'], 'segretissima');
    });

    test('il dispositivo fa i due passi e ottiene la playlist', () async {
      final p = panel();
      final result = await p.service.fetch(endpoint: 'https://x.dev', code: _code);
      expect(result, isNotNull);
      expect(result!.host, 'http://esempio.tv:8080');
      expect(result.username, 'mamma2026');
      expect(result.password, 'segretissima');
      expect(result.name, 'mamma');
      expect(p.adapter.paths, [
        '/v1/profile/$_code',
        '/v1/account/$_accountId',
      ]);
    });

    test('con i preferiti condivisi adotta il codice dell utenza', () async {
      final shared = await panel(sync: 1)
          .service
          .fetch(endpoint: 'https://x.dev', code: _code);
      expect(shared!.syncCode, _accountCode);

      // E se l'interruttore è spento non lo adotta: il server rifiuterebbe la
      // sincronizzazione sotto quel codice, e il dispositivo mostrerebbe un
      // errore per una cosa che nessuno ha chiesto.
      final alone = await panel(sync: 0)
          .service
          .fetch(endpoint: 'https://x.dev', code: _code);
      expect(alone!.syncCode, isNull);
    });

    test('vale la data più recente fra casellina e playlist', () async {
      // Una correzione alle credenziali muove la playlist...
      final corrected = await panel(casellinaAt: 1000, accountAt: 9000)
          .service
          .fetch(endpoint: 'https://x.dev', code: _code);
      expect(corrected!.updatedAt, 9000);

      // ...e spostare un dispositivo su un'altra utenza muove la casellina.
      // Senza il massimo, un'utenza con una playlist vecchia non verrebbe mai
      // applicata al dispositivo appena spostato.
      final moved = await panel(casellinaAt: 9000, accountAt: 1000)
          .service
          .fetch(endpoint: 'https://x.dev', code: _code);
      expect(moved!.updatedAt, 9000);
    });

    test('utenza senza playlist: non si applica niente', () async {
      final p = panel(playlist: null);
      expect(
        await p.service.fetch(endpoint: 'https://x.dev', code: _code),
        isNull,
      );
      expect(p.adapter.paths.length, 2, reason: 'ha comunque provato');
    });

    test('la casellina vecchia con dentro la playlist funziona ancora', () async {
      // I dispositivi configurati prima delle utenze non devono fermarsi il
      // giorno in cui aggiornano l'app.
      final p = panel(casellina: _fromPanel, casellinaAt: 4242);
      final result = await p.service.fetch(endpoint: 'https://x.dev', code: _code);
      expect(result!.host, 'http://esempio.tv:8080');
      expect(result.username, 'mamma');
      expect(result.name, 'Casa');
      expect(result.syncCode, 'MNPQRSTUVWXY');
      expect(result.updatedAt, 4242);
      expect(p.adapter.paths, ['/v1/profile/$_code'],
          reason: 'niente utenza, niente secondo giro');
    });

    test('spazzatura nella casellina non diventa una playlist', () async {
      final p = panel(casellina: 'non-e-un-blob');
      expect(
        await p.service.fetch(endpoint: 'https://x.dev', code: _code),
        isNull,
      );
    });
  });

  group('indirizzo solo per questo dispositivo (82° giro)', () {
    /// Il Worker con l'utenza `Prova82` e un dispositivo che ha un indirizzo
    /// suo dentro la casellina.
    ProvisioningService pannello({int accountAt = 2000, int sync = 1}) {
      final adapter = _FakeAdapter((options) {
        if (options.uri.path.startsWith('/v1/profile/')) {
          return _json({'data': _casellinaConIndirizzo, 'updatedAt': 3000});
        }
        if (options.uri.path == '/v1/account/$_accountIdProva82') {
          return _json({
            'data': _playlistProva82,
            'updatedAt': accountAt,
            'sync': sync,
          });
        }
        return _json({'error': 'not_found'}, 404);
      });
      return ProvisioningService(dio: Dio()..httpClientAdapter = adapter);
    }

    test('l utenza dice un indirizzo, la casellina ne dice un altro', () async {
      // I due cifrati, aperti a mano: è quello che rende il test capace di
      // accorgersi se il pannello cambia formato da un lato solo.
      final casellina = await decryptProvisioning(_casellinaConIndirizzo, _code);
      expect(casellina!['host'], 'http://due.tv:9090');
      expect(casellina['accountId'], _accountIdProva82);

      final playlist = await decryptProvisioning(
        _playlistProva82,
        casellina['account'].toString(),
      );
      expect(playlist!['host'], 'http://uno.tv:8080',
          reason: 'l\'utenza resta dov\'è: l\'eccezione è del dispositivo');
      expect(playlist['username'], 'u1');
    });

    test('vince l indirizzo del dispositivo, il resto resta dell utenza',
        () async {
      final result =
          await pannello().fetch(endpoint: 'https://x.dev', code: _code);

      expect(result!.host, 'http://due.tv:9090', reason: 'la porta d\'ingresso è sua');
      expect(result.username, 'u1', reason: 'utente e password sono dell\'utenza');
      expect(result.password, 'p1');
      expect(result.name, 'Prova82');
      // E soprattutto: resta nello stesso gruppo di sincronizzazione, che era
      // il motivo per cui "fanne due utenze" non andava bene.
      expect(result.syncCode, isNotNull);
      expect(result.fromAccount, isTrue);
    });

    test('senza preferiti condivisi l indirizzo suo vale lo stesso', () async {
      final result =
          await pannello(sync: 0).fetch(endpoint: 'https://x.dev', code: _code);
      expect(result!.host, 'http://due.tv:9090');
      expect(result.syncCode, isNull);
    });

    test('una correzione della playlist non se lo porta via', () async {
      // Il proprietario cambia la password dell'utenza mesi dopo: l'invio è
      // più recente e viene applicato, ma l'eccezione sta nella casellina e
      // viene riletta ogni volta.
      final result = await pannello(accountAt: 9999)
          .fetch(endpoint: 'https://x.dev', code: _code);
      expect(result!.host, 'http://due.tv:9090');
      expect(result.updatedAt, 9999, reason: 'vale la data più recente delle due');
    });
  });
}
