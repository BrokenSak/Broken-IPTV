import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/services/provisioning_service.dart';

/// La playlist che il pannello consegna a un dispositivo.
///
/// ⚠️ Il cifrato qui sotto è stato prodotto **dal browser** (WebCrypto, lo
/// stesso codice che gira in `sync_worker/src/admin.html.js`), non da Dart:
/// è l'unico modo di accorgersi se le due implementazioni smettono di
/// parlarsi — nonce di lunghezza diversa, tag in coda invece che in testa,
/// derivazione della chiave cambiata da un lato solo. Un round-trip
/// Dart→Dart passerebbe anche con il formato sbagliato.
const _fromPanel =
    'Uk+VyCo89axY00NVP+I1cVJ+YmjxiAZcK4mWjH/wdARki8EWHRpbzAe6GduIXJ7gDuK6/2rb'
    'R4gGyzutXZo7TSGRkG0ISL8ziYIf0HXldgFEVeNd1FvxDNgHjYVSBlGQqWEJFViD7R4Pjy/5'
    'C4y3tiOlShaeH3GiXY1hh9lcnfM7nIXPRzCNqmf7+TPDoLF6Kjn8yaoZMfCGTgZqjDk1rA==';
const _code = 'ABCDEFGHJKLM';

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
    });
  });
}
