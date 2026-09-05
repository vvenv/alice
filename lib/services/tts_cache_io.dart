import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'abort.dart';
import 'logger.dart';
import 'tts_cache_api.dart';

/// 原生端（iOS / Android / desktop）的发音缓存实现。
///
/// 对应 RN 版 tts.ts 里那段 expo-file-system 的逻辑：缓存目录、
/// 文件名编码、最小字节校验、两个有道音源依次重试，全部一比一保留。
const _log = Logger('TTSCache');

const int _minAudioBytes = 256;
const String _cacheDirName = 'tts';
const Map<String, String> _downloadHeaders = {
  'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
};

Directory? _cacheDir;

class TtsCache implements TtsCacheApi {
  const TtsCache();

  @override
  bool get canUseDiskCache => true;

  Future<Directory> _ensureCacheDir() async {
    final cached = _cacheDir;
    if (cached != null && cached.existsSync()) return cached;

    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/$_cacheDirName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  String _cacheKeyFor(String text) => text.trim().toLowerCase();

  String _cacheFileName(String text) {
    final safe = Uri.encodeComponent(_cacheKeyFor(text)).replaceAll('%', '_');
    return '${safe.isEmpty ? 'unknown' : safe}.mp3';
  }

  Future<File> _cacheFileFor(String text) async {
    final dir = await _ensureCacheDir();
    return File('${dir.path}/${_cacheFileName(text)}');
  }

  List<String> _youdaoUrls(String text) {
    final q = Uri.encodeComponent(text);
    // 优先美音 (type=2)，其次英音 (type=1)
    return [
      'https://dict.youdao.com/dictvoice?audio=$q&type=2',
      'https://dict.youdao.com/dictvoice?audio=$q&type=1',
    ];
  }

  bool _isValid(File file) =>
      file.existsSync() && file.lengthSync() >= _minAudioBytes;

  @override
  Future<String?> readyPath(String text) async {
    final cached = await _cacheFileFor(text);
    return _isValid(cached) ? cached.path : null;
  }

  @override
  Future<String?> download(String text, AbortSignal signal) async {
    final dest = await _cacheFileFor(text);
    if (_isValid(dest)) return dest.path;

    for (final url in _youdaoUrls(text)) {
      if (signal.aborted) return null;

      final client = http.Client();
      // Dart 的 http 没有 AbortController —— 关掉 client 就是取消。
      void closeOnAbort() => client.close();
      signal.addListener(closeOnAbort);

      try {
        if (dest.existsSync()) {
          try {
            dest.deleteSync();
          } catch (_) {}
        }

        final response =
            await client.get(Uri.parse(url), headers: _downloadHeaders);
        if (signal.aborted) return null;

        if (response.statusCode == 200 &&
            response.bodyBytes.length >= _minAudioBytes) {
          dest.writeAsBytesSync(response.bodyBytes);
          return dest.path;
        }
      } catch (e) {
        if (signal.aborted) return null;
        _log.debug('有道音频下载失败: $url $e');
      } finally {
        signal.removeListener(closeOnAbort);
        client.close();
      }
    }

    return null;
  }

  @override
  Future<String?> readyClipPath(String name) async {
    final dir = await _ensureCacheDir();
    final file = File('${dir.path}/$name');
    return _isValid(file) ? file.path : null;
  }

  @override
  Future<String?> writeClip(String name, List<int> bytes) async {
    if (bytes.length < _minAudioBytes) return null;
    try {
      final dir = await _ensureCacheDir();
      final file = File('${dir.path}/$name');
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      file.writeAsBytesSync(bytes);
      return file.path;
    } catch (e) {
      _log.debug('写入 TTS 片段失败: $name $e');
      return null;
    }
  }

  @override
  Future<int> clear() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/$_cacheDirName');
    if (!dir.existsSync()) return 0;

    var count = 0;
    try {
      for (final entry in dir.listSync()) {
        if (entry is File) count += 1;
      }
      dir.deleteSync(recursive: true);
      _cacheDir = null;
    } catch (e) {
      _log.warn('clearTtsCache 失败: $e');
      rethrow;
    }
    return count;
  }
}
