import 'abort.dart';
import 'tts_cache_api.dart';

/// Web 端的发音缓存实现：什么都不做。
///
/// 浏览器里没有可写的本地文件系统（也没必要 —— 有道音频本身就是
/// 一次 HTTP 请求），所以 `canUseDiskCache` 为 false，调用方会跳过
/// 预取与本地播放，直接用系统 TTS 朗读。
///
/// 与 RN 版 tts.ts 里 `canUseDiskCache()` 在 web 上返回 false 的行为一致。
class TtsCache implements TtsCacheApi {
  const TtsCache();

  @override
  bool get canUseDiskCache => false;

  @override
  Future<String?> readyPath(String text) async => null;

  @override
  Future<String?> download(String text, AbortSignal signal) async => null;

  @override
  Future<int> clear() async => 0;
}
