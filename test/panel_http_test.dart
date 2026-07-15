import 'package:broken_iptv/data/services/panel_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodePanelJson', () {
    test('decodes plain JSON string', () {
      expect(decodePanelJson('[{"category_id":"1"}]'), isA<List>());
      expect(decodePanelJson('{"user_info":{}}'), isA<Map>());
    });

    test('passes through already-decoded data', () {
      expect(decodePanelJson([1, 2]), [1, 2]);
      expect(decodePanelJson({'a': 1}), {'a': 1});
    });

    test('strips UTF-8 BOM', () {
      final data = decodePanelJson('﻿[{"category_id":"1"}]');
      expect(data, isA<List>());
      expect((data as List).length, 1);
    });

    test('extracts JSON list buried after PHP warnings', () {
      const noisy = '<br />\n<b>Warning</b>: something in '
          '/var/www/api.php on line [12]<br />\n'
          '[{"category_id":"5","category_name":"Sport"}]';
      final data = decodePanelJson(noisy);
      expect(data, isA<List>());
      expect(((data as List).first as Map)['category_id'], '5');
    });

    test('extracts JSON object buried in noise', () {
      const noisy = 'Notice: x\n{"user_info":{"exp_date":"123"}}';
      final data = decodePanelJson(noisy);
      expect(data, isA<Map>());
      expect((data as Map).containsKey('user_info'), isTrue);
    });

    test('returns null for HTML/empty', () {
      expect(decodePanelJson('<html><body>error</body></html>'), isNull);
      expect(decodePanelJson('   '), isNull);
      expect(decodePanelJson(null), isNull);
    });
  });

  group('asPanelList', () {
    test('keeps a plain list', () {
      expect(asPanelList([1, 2]), [1, 2]);
    });

    test('converts a numeric-keys object (PHP json_encode quirk)', () {
      final list = asPanelList({
        '0': {'category_id': '1'},
        '2': {'category_id': '3'},
      });
      expect(list, isA<List>());
      expect(list!.length, 2);
    });

    test('rejects non-list shapes (e.g. handshake payload)', () {
      expect(asPanelList({'user_info': {}, 'server_info': {}}), isNull);
      expect(asPanelList('nope'), isNull);
      expect(asPanelList(null), isNull);
    });
  });
}
