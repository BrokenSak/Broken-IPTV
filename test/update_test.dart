import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/services/update_service.dart';

/// The version check is a plain build-number comparison; the artifact picked
/// depends on the platform. Both are pure (updateFromJson) and tested here.
void main() {
  Map<String, dynamic> json(int build) => {
        'build': build,
        'version': '9.9.9',
        'notes': 'nuove cose',
        'apk': 'https://x/BrokenIPTV.apk',
        'exe': 'https://x/BrokenIPTV.exe',
      };

  test('offers the update only when the published build is newer', () {
    expect(updateFromJson(json(5), 4), isNotNull);
    expect(updateFromJson(json(5), 5), isNull, reason: 'same build = no update');
    expect(updateFromJson(json(5), 6), isNull, reason: 'older remote = no update');
  });

  test('picks the APK on mobile and the EXE on Windows', () {
    expect(updateFromJson(json(5), 1, isWindows: false)!.downloadUrl, endsWith('.apk'));
    expect(updateFromJson(json(5), 1, isWindows: true)!.downloadUrl, endsWith('.exe'));
  });

  test('carries version and notes through', () {
    final info = updateFromJson(json(7), 1)!;
    expect(info.build, 7);
    expect(info.version, '9.9.9');
    expect(info.notes, 'nuove cose');
  });

  test('malformed json yields no update (never throws)', () {
    expect(updateFromJson(const {}, 1), isNull);
    expect(updateFromJson(const {'build': 'x'}, 1), isNull);
    // build present but the platform artifact URL missing.
    expect(updateFromJson(const {'build': 9}, 1, isWindows: false), isNull);
  });
}
