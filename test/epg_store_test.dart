import 'dart:convert';
import 'dart:io';

import 'package:broken_iptv/data/services/epg_store.dart';
import 'package:flutter_test/flutter_test.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// XMLTV timestamp (UTC) for [d].
String _ts(DateTime d) {
  final u = d.toUtc();
  return '${u.year}${_two(u.month)}${_two(u.day)}'
      '${_two(u.hour)}${_two(u.minute)}${_two(u.second)} +0000';
}

String _fixtureXml() {
  final now = DateTime.now();
  final live = '<programme start="${_ts(now.subtract(const Duration(minutes: 10)))}" '
      'stop="${_ts(now.add(const Duration(minutes: 50)))}" channel="rai1.it">'
      '<title>Adesso in onda</title><desc>Descrizione</desc></programme>';
  final next = '<programme start="${_ts(now.add(const Duration(minutes: 50)))}" '
      'stop="${_ts(now.add(const Duration(hours: 2)))}" channel="rai1.it">'
      '<title>Dopo</title></programme>';
  final old = '<programme start="${_ts(now.subtract(const Duration(days: 2)))}" '
      'stop="${_ts(now.subtract(const Duration(days: 2, hours: -1)))}" channel="rai1.it">'
      '<title>Vecchio</title></programme>';
  final other = '<programme start="${_ts(now.subtract(const Duration(minutes: 5)))}" '
      'stop="${_ts(now.add(const Duration(minutes: 25)))}" channel="canale5.it">'
      '<title>Altro canale</title></programme>';
  return '<?xml version="1.0" encoding="UTF-8"?><tv>$live$next$old$other</tv>';
}

void main() {
  test('parseXmltv windows out old programmes and groups by channel', () {
    final map = parseXmltv(_fixtureXml());
    expect(map['rai1.it']!.map((p) => p.title), ['Adesso in onda', 'Dopo']);
    expect(map['canale5.it']!.single.title, 'Altro canale');
  });

  test('parseXmltvBytes handles gzip', () {
    final bytes = GZipCodec().encode(utf8.encode(_fixtureXml()));
    final map = parseXmltvBytes(bytes);
    expect(map['rai1.it'], isNotEmpty);
  });

  test('EpgStore fetches once and serves lookups locally', () async {
    var fetches = 0;
    final store = EpgStore(fetch: () async {
      fetches++;
      return utf8.encode(_fixtureXml());
    });

    expect(await store.ensureLoaded(), isTrue);
    expect(await store.ensureLoaded(), isTrue); // single-flight, no re-fetch
    expect(fetches, 1);

    final programs = store.programsFor('rai1.it')!;
    expect(programs.first.title, 'Adesso in onda');
    expect(store.programsFor('sconosciuto'), isNull);
  });

  test('EpgStore reads a fresh cache file instead of the network', () async {
    final tmp = await Directory.systemTemp.createTemp('epg_store_test');
    addTearDown(() => tmp.delete(recursive: true));
    final file = File('${tmp.path}${Platform.pathSeparator}epg_test.xml');
    await file.writeAsBytes(utf8.encode(_fixtureXml()));

    var fetches = 0;
    final store = EpgStore(
      fetch: () async {
        fetches++;
        return null;
      },
      cacheFile: file,
    );
    expect(await store.ensureLoaded(), isTrue);
    expect(fetches, 0);
    expect(store.programsFor('rai1.it'), isNotEmpty);
  });
}
