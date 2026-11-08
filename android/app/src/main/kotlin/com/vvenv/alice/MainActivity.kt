package com.vvenv.alice

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 接收「分享到 Alice」的纯文本，以及应用内更新的 APK 安装。
 *
 * 分享：从微信 / 浏览器 / 备忘录里选中一段单词，分享过来直接成词表 ——
 * 比拍照识别更快。Dart 侧见 lib/services/share_intake.dart。
 *
 * 安装：Dart 下完 APK 后走 alice/install，用 FileProvider 调起系统安装器。
 * 见 lib/services/apk_installer.dart。
 *
 * 分享两条路径：
 * - 冷启动：分享意图在 configureFlutterEngine 之前就到了，先存着，等 Dart
 *   侧起来主动来取（takeSharedText）。
 * - 已经在运行：onNewIntent 直接推给 Dart（sharedText）。引擎万一还没就绪，
 *   仍然退回「存着等取」。
 */
class MainActivity : FlutterActivity() {

    private var shareChannel: MethodChannel? = null
    private var pendingText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingText = sharedTextFrom(intent) ?: pendingText

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).apply {
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canInstallPackages())
                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "path required", null)
                        return@setMethodCallHandler
                    }
                    result.success(installApk(path))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val text = sharedTextFrom(intent) ?: return
        val target = shareChannel
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

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    /**
     * 调起系统安装界面。返回值约定给 Dart：
     * - "launched" 已打开安装器
     * - "needPermission" 还没授权「安装未知应用」，已跳设置页
     * - "failed" 文件不存在 / 调不起安装器
     */
    private fun installApk(path: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !canInstallPackages()) {
            openInstallSettings()
            return "needPermission"
        }

        val file = File(path)
        if (!file.isFile || file.length() <= 0L) return "failed"

        return try {
            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "launched"
        } catch (e: Exception) {
            "failed"
        }
    }

    private companion object {
        const val SHARE_CHANNEL = "alice/share"
        const val INSTALL_CHANNEL = "alice/install"
    }
}
