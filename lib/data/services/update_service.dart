import 'dart:io';

import 'package:dio/dio.dart';

/// A newer release the app can offer to install.
class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.version,
    required this.notes,
    required this.downloadUrl,
  });

  final int build;
  final String version;
  final String notes;

  /// The APK (Android) or installer EXE (Windows) to fetch.
  final String downloadUrl;
}

/// Checks a small `version.json` published in the repo for a newer build, and
/// downloads the platform artifact. Install itself is triggered by the caller
/// (system installer on Android, run the installer on Windows) — a sideload
/// app can't self-install silently.
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Raw file on the main branch: updating it is just a commit, and it's read
  /// through GitHub's CDN. The `apk`/`exe` fields point at the stable
  /// `releases/latest/download/...` URLs.
  static const _versionUrl =
      'https://raw.githubusercontent.com/BrokenSak/Broken-IPTV/main/version.json';

  /// Returns an [UpdateInfo] when the published build is higher than
  /// [currentBuild], else null. Never throws — a failed check (offline, etc.)
  /// just means "no update offered".
  Future<UpdateInfo?> check(int currentBuild) async {
    try {
      final resp = await _dio.get<dynamic>(
        _versionUrl,
        options: Options(
          responseType: ResponseType.json,
          // Avoid a stale cached copy hiding a fresh release.
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );
      final data = resp.data;
      if (data is! Map) return null;
      return updateFromJson(data.cast<String, dynamic>(), currentBuild);
    } catch (_) {
      return null;
    }
  }

  /// Downloads the artifact to [savePath], reporting 0..1 progress.
  Future<void> download(
    String url,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
  }
}

int? _asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

/// Pure comparison (testable): pick the right artifact for the platform and
/// only return it when [json]'s build is strictly newer than [currentBuild].
/// [isWindows] defaults to the real platform; tests pass it explicitly (the
/// test host is itself Windows, so it must override rather than OR).
UpdateInfo? updateFromJson(
  Map<String, dynamic> json,
  int currentBuild, {
  bool? isWindows,
}) {
  final build = _asInt(json['build']);
  if (build == null || build <= currentBuild) return null;

  final key = (isWindows ?? Platform.isWindows) ? 'exe' : 'apk';
  final url = json[key] as String?;
  if (url == null || url.isEmpty) return null;

  return UpdateInfo(
    build: build,
    version: json['version']?.toString() ?? '',
    notes: json['notes']?.toString() ?? '',
    downloadUrl: url,
  );
}
