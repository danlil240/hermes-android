import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Information about a GitHub release.
class ReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime publishedAt;
  final List<ReleaseAsset> assets;

  ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  /// Version string without leading 'v', e.g. "1.0.24".
  String get version =>
      tagName.startsWith('v') ? tagName.substring(1) : tagName;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final assets = (json['assets'] as List? ?? [])
        .map((a) => ReleaseAsset.fromJson(a as Map<String, dynamic>))
        .toList();
    return ReleaseInfo(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      assets: assets,
    );
  }
}

class ReleaseAsset {
  final String name;
  final String browserDownloadUrl;
  final int size;
  final String contentType;

  ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
    required this.contentType,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      contentType: json['content_type'] as String? ?? '',
    );
  }
}

/// Compares two semantic version strings.
/// Returns true if [remote] is newer than [local].
bool _isNewerVersion(String remote, String local) {
  final r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final l = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final maxLen = r.length > l.length ? r.length : l.length;
  for (var i = 0; i < maxLen; i++) {
    final rv = i < r.length ? r[i] : 0;
    final lv = i < l.length ? l[i] : 0;
    if (rv > lv) return true;
    if (rv < lv) return false;
  }
  return false;
}

/// Detects the best APK asset for the current device.
/// Tries common Android ABIs in order of prevalence.
String? _bestApkAsset(List<ReleaseAsset> assets) {
  if (!Platform.isAndroid) return null;

  // Most common ABIs in order of prevalence on modern devices.
  const abiPriority = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  for (final abi in abiPriority) {
    for (final a in assets) {
      if (a.name.endsWith('.apk') && a.name.contains(abi)) return a.name;
    }
  }
  // Fall back to any APK.
  for (final a in assets) {
    if (a.name.endsWith('.apk')) return a.name;
  }
  return null;
}

class AppUpdater {
  static const _repoOwner = 'danlil240';
  static const _repoName = 'hermes-android';
  static const _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  /// Checks GitHub for a newer release.
  /// Returns [ReleaseInfo] if an update is available, otherwise null.
  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http
          .get(Uri.parse(_apiUrl), headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          })
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final release = ReleaseInfo.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );

      if (_isNewerVersion(release.version, currentVersion)) {
        return release;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads an APK asset to a temporary file and returns its path.
  static Future<String> downloadApk(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/${asset.name}';
    final file = File(filePath);
    if (await file.exists()) await file.delete();

    final request = http.Request('GET', Uri.parse(asset.browserDownloadUrl));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }

    final total = response.contentLength ?? asset.size;
    var received = 0;

    final sink = file.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();

    return filePath;
  }

  /// Returns the best matching APK asset for this device, or null.
  static ReleaseAsset? getBestApk(ReleaseInfo release) {
    final name = _bestApkAsset(release.assets);
    if (name == null) return null;
    return release.assets.where((a) => a.name == name).firstOrNull;
  }
}
