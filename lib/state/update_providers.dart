import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../data/services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

/// Checked once at startup (the home watches it): resolves to the newer
/// release when there is one, else null. Never throws.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final build = int.tryParse(info.buildNumber) ?? 0;
  return ref.read(updateServiceProvider).check(build);
});

class UpdateDownloadState {
  const UpdateDownloadState({this.downloading = false, this.progress = 0, this.error});

  final bool downloading;
  final double progress;
  final String? error;
}

/// Downloads the artifact and hands it to the OS to install. A sideload app
/// can't install silently: on Android the system installer shows one
/// confirmation; on Windows the downloaded installer runs and the app exits so
/// its files can be replaced.
class UpdateDownloadController extends Notifier<UpdateDownloadState> {
  @override
  UpdateDownloadState build() => const UpdateDownloadState();

  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (state.downloading) return;
    state = const UpdateDownloadState(downloading: true);
    try {
      final dir = await getTemporaryDirectory();
      final ext = Platform.isWindows ? 'exe' : 'apk';
      final path = '${dir.path}${Platform.pathSeparator}BrokenIPTV-update.$ext';

      await ref.read(updateServiceProvider).download(
        info.downloadUrl,
        path,
        onProgress: (p) => state = UpdateDownloadState(downloading: true, progress: p),
      );

      if (Platform.isWindows) {
        // Launch the installer detached, then exit so it can overwrite the
        // running app's files (Inno Setup closes/replaces/relaunches).
        await Process.start(path, const [], mode: ProcessStartMode.detached);
        state = const UpdateDownloadState();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        exit(0);
      } else {
        // Opens the APK → the system package installer (one confirmation).
        await OpenFilex.open(path);
        state = const UpdateDownloadState();
      }
    } catch (_) {
      state = const UpdateDownloadState(error: 'Aggiornamento non riuscito. Riprova.');
    }
  }
}

final updateDownloadProvider =
    NotifierProvider<UpdateDownloadController, UpdateDownloadState>(
  UpdateDownloadController.new,
);
