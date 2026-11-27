package app.luch.luch

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEEP_LINK_CHANNEL = "app.luch.luch/deep_link"
    }

    private var deepLinkChannel: MethodChannel? = null
    private var initialLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialLink = extractLink(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEEP_LINK_CHANNEL)
        deepLinkChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    val link = initialLink
                    initialLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractLink(intent) ?: return
        val channel = deepLinkChannel
        if (channel != null) {
            channel.invokeMethod("onLink", link)
        } else {
            initialLink = link
        }
    }

    private fun extractLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null
        return intent.dataString
    }
}
