package dev.pavelvault.pavel_vault

import android.content.ClipboardManager
import android.content.Context
import android.os.StatFs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.pavelvault/clipboard",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getHtml") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val item = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
            result.success(item?.htmlText ?: item?.coerceToHtmlText(this))
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.pavelvault/storage",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getFreeSpace") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("invalid_path", "Path is required", null)
            } else {
                result.success(StatFs(path).availableBytes)
            }
        }
    }
}
