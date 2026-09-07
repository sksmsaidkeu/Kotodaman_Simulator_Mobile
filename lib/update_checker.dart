import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const kManifestUrl =
    'https://raw.githubusercontent.com/sksmsaidkeu/Kotodaman_Simulator/main/latest.json';

class MobileUpdateInfo {
  final String version;
  final String apkUrl;
  final String apkSha256;

  const MobileUpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.apkSha256,
  });
}

/// latest.json의 mobile.* 필드를 현재 설치된 앱 버전과 비교한다.
/// 새 버전이 없거나 조회에 실패하면 null을 반환한다(조용히 무시 — 필수 기능 아님).
Future<MobileUpdateInfo?> checkForUpdate() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(kManifestUrl));
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final mobile = data['mobile'] as Map<String, dynamic>?;
    if (mobile == null) return null;

    final version = mobile['version'] as String?;
    final apkUrl = mobile['apkUrl'] as String?;
    final apkSha256 = mobile['apkSha256'] as String?;
    if (version == null || apkUrl == null || apkSha256 == null) return null;

    final info = await PackageInfo.fromPlatform();
    if (!_isNewer(version, info.version)) return null;

    return MobileUpdateInfo(version: version, apkUrl: apkUrl, apkSha256: apkSha256);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

bool _isNewer(String remote, String current) {
  List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final r = parts(remote);
  final c = parts(current);
  for (var i = 0; i < r.length || i < c.length; i++) {
    final rv = i < r.length ? r[i] : 0;
    final cv = i < c.length ? c[i] : 0;
    if (rv != cv) return rv > cv;
  }
  return false;
}

/// APK를 내려받아 SHA256을 검증한 뒤 시스템 설치 화면을 띄운다(탭 한 번으로 설치, PRD FR-6).
Future<void> downloadAndInstallUpdate(
  MobileUpdateInfo update, {
  void Function(int received, int total)? onProgress,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(update.apkUrl));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('다운로드 실패: HTTP ${response.statusCode}');
    }
    final total = response.contentLength;
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      onProgress?.call(bytes.length, total);
    }

    final digest = sha256.convert(bytes).toString();
    if (digest.toLowerCase() != update.apkSha256.toLowerCase()) {
      throw Exception('다운로드한 파일이 손상되었습니다(체크섬 불일치).');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kotodaman-update-${update.version}.apk');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception('설치 화면을 열지 못했습니다: ${result.message}');
    }
  } finally {
    client.close();
  }
}
