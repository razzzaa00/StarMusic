import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'net.dart';

class AppUpdate {
  const AppUpdate(this.version, this.downloadUrl, this.pageUrl);
  final String version;

  /// The APK on Android; null on iPhone, where the IPA is installed from a computer.
  final Uri? downloadUrl;
  final Uri pageUrl;
}

/// Compares the installed version with the latest GitHub release.
class UpdateChecker {
  static const _repo = 'razzzaa00/StarMusic';

  Future<String> installedVersion() async => (await PackageInfo.fromPlatform()).version;

  Future<AppUpdate?> check() async {
    final json = await getJson(Uri.https('api.github.com', '/repos/$_repo/releases/latest'), headers: {'Accept': 'application/vnd.github+json'});
    if (json is! Map) return null;
    final latest = '${json['tag_name'] ?? ''}'.replaceFirst(RegExp('^v'), '');
    if (!isNewer(latest, await installedVersion())) return null;
    final assets = json['assets'] is List ? (json['assets'] as List).whereType<Map>() : const <Map>[];
    final apk = assets.where((a) => '${a['name']}'.endsWith('-android.apk')).firstOrNull;
    return AppUpdate(
      latest,
      Platform.isAndroid && apk != null ? Uri.parse('${apk['browser_download_url']}') : null,
      Uri.parse('${json['html_url'] ?? 'https://github.com/$_repo/releases/latest'}'),
    );
  }
}

/// True when [candidate] ("1.10.0") is a higher version than [current] ("1.9.2").
bool isNewer(String candidate, String current) {
  List<int> parts(String v) => v.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final a = parts(candidate), b = parts(current);
  if (a.length < 3 || b.length < 3) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
