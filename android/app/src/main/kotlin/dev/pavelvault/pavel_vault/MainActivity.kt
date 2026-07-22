package dev.pavelvault.pavel_vault

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.StatFs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var processText: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureProcessText(intent)
    }

    private fun captureProcessText(value: Intent?) {
        if (value?.action == Intent.ACTION_PROCESS_TEXT) {
            processText = value.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureProcessText(intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.pavelvault/quick_capture",
        ).setMethodCallHandler { call, result ->
            if (call.method != "takeProcessText") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(processText)
            processText = null
        }
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
