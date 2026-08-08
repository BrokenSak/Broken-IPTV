import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/services/sync_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Il server rifiuta i codici che il proprietario non ha abilitato (403).
///
/// È un caso a parte da qualsiasi altro errore: dire "controlla codice e
/// indirizzo" manderebbe l'utente a sistemare due cose che sono giuste. Serve
/// invece la frase che dice cosa fare davvero — farsi abilitare.
void main() {
  SyncService serviceReplying(int status, String body) {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (_) => ResponseBody.fromString(
          body,
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    return SyncService(dio: dio);
  }

  group('rifiuto del server (403)', () {
    test('fetch di un codice sconosciuto lancia il rifiuto, non un errore di rete',
        () async {
      final service = serviceReplying(403, '{"error":"unknown_code"}');
      expect(
        () => service.fetch(endpoint: 'https://x', code: 'ABCDEFGHJKLM'),
        throwsA(isA<SyncNotAllowedException>()
            .having((e) => e.reason, 'reason', 'unknown_code')),
      );
    });

    test('push con la sincronizzazione spenta lancia il rifiuto', () async {
      final service = serviceReplying(403, '{"error":"sync_disabled"}');
      expect(
        () => service.push(
          endpoint: 'https://x',
          code: 'ABCDEFGHJKLM',
          blob: const {'favorites': []},
        ),
        throwsA(isA<SyncNotAllowedException>()
            .having((e) => e.reason, 'reason', 'sync_disabled')),
      );
    });

    test('403 senza corpo leggibile resta un rifiuto (nessuna eccezione strana)',
        () async {
      final service = serviceReplying(403, '<html>vietato</html>');
      expect(
        () => service.fetch(endpoint: 'https://x', code: 'ABCDEFGHJKLM'),
        throwsA(isA<SyncNotAllowedException>()),
      );
    });

    test('404 resta "niente di salvato", non un rifiuto', () async {
      // Il primo dispositivo di un codice nuovo passa di qui: se diventasse un
      // errore, la prima sincronizzazione fallirebbe sempre.
      final service = serviceReplying(404, '{"error":"empty"}');
      expect(
        await service.fetch(endpoint: 'https://x', code: 'ABCDEFGHJKLM'),
        isNull,
      );
    });

    test('500 resta un errore di rete (lo gestisce il messaggio generico)',
        () async {
      final service = serviceReplying(500, 'boom');
      expect(
        () => service.fetch(endpoint: 'https://x', code: 'ABCDEFGHJKLM'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('messaggi', () {
    test('sincronizzazione spenta: dice di farsela accendere', () {
      final message = syncRefusalMessage('sync_disabled');
      expect(message, contains('non è attiva'));
      expect(message, contains('accenderla'));
      expect(message, isNot(contains('indirizzo')));
    });

    test('codice sconosciuto: dice di farlo abilitare', () {
      expect(syncRefusalMessage('unknown_code'), contains('abilitat'));
    });

    test('ragione mancante o inattesa: comunque una frase utile', () {
      for (final reason in [null, '', 'qualcosa_di_nuovo']) {
        expect(syncRefusalMessage(reason), isNotEmpty);
        expect(syncRefusalMessage(reason), contains('app'));
      }
    });

    test('syncErrorCode legge la ragione e tollera la spazzatura', () {
      expect(syncErrorCode('{"error":"sync_disabled"}'), 'sync_disabled');
      expect(syncErrorCode('non json'), isNull);
      expect(syncErrorCode(''), isNull);
      expect(syncErrorCode(null), isNull);
      expect(syncErrorCode('[]'), isNull);
    });
  });
}
