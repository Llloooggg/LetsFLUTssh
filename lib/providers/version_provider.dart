import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App version read from the platform binary at runtime.
///
/// Single source of truth is `pubspec.yaml` — Flutter bakes the version
/// into each platform build, and [PackageInfo] reads it back.
final appVersionProvider =
    NotifierProvider<AppVersionNotifier, String>(AppVersionNotifier.new);

class AppVersionNotifier extends Notifier<String> {
  @override
  String build() => '';

  Future<void> load() async {
    final info = await PackageInfo.fromPlatform();
    state = info.version;
  }
}
