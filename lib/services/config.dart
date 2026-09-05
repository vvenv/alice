/// 应用配置。对应 RN 版 src/lib/config.ts（那边通过 app.config.js 把 .env
/// 注入 expo-constants 的 extra）。
///
/// Flutter 侧走编译期常量：
///   flutter build apk --dart-define=ZHIPU_API_KEY=xxx
///
/// Web 构建不要传 ZHIPU_API_KEY —— Web bundle 是公开 JS，绝不能内嵌共享密钥
/// （与 RN 版 app.config.js 里 isWebBuild 的处理保持一致）。
class AppConfig {
  const AppConfig._();

  static const String zhipuApiKey = String.fromEnvironment('ZHIPU_API_KEY');

  static const String zhipuBaseUrl = String.fromEnvironment(
    'ZHIPU_BASE_URL',
    defaultValue: 'https://open.bigmodel.cn/api/paas/v4',
  );

  static const String visionModel = String.fromEnvironment(
    'VISION_MODEL',
    defaultValue: 'glm-4v-flash',
  );
}
