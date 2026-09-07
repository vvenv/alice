package com.vvenv.alice

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 接收「分享到 Alice」的纯文本。
 *
 * 从微信 / 浏览器 / 备忘录里选中一段单词，分享过来直接成词表 —— 比拍照识别
 * 更快，也不消耗 credits。Dart 侧见 lib/services/share_intake.dart。
 *
 * 两条路径：
 * - 冷启动：分享意图在 configureFlutterEngine 之前就到了，先存着，等 Dart
 *   侧起来主动来取（takeSharedText）。
 * - 已经在运行：onNewIntent 直接推给 Dart（sharedText）。引擎万一还没就绪，
 *   仍然退回「存着等取」。
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var pendingText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingText = sharedTextFrom(intent) ?: pendingText

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeSharedText" -> {
                        result.success(pendingText)
                        pendingText = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val text = sharedTextFrom(intent) ?: return
        val target = channel
        if (target == null) {
            pendingText = text
        } else {
            target.invokeMethod("sharedText", text)
        }
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
    }

    private companion object {
        const val CHANNEL = "alice/share"
    }
}
