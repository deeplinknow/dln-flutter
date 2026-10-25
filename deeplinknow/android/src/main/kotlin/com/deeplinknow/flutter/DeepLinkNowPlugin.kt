package com.deeplinknow.flutter

import android.content.Context
import android.content.Intent
import com.deeplinknow.DLN
import com.deeplinknow.DLNAppInfo
import com.deeplinknow.DLNConfig
import com.deeplinknow.DeferredDeepLink
import com.deeplinknow.MatchResponse
import com.deeplinknow.ParsedDeepLink
import com.deeplinknow.ReferrerData
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/**
 * The calls the plugin makes on dln-android. The production implementation forwards to `DLN`;
 * tests substitute a fake. Nothing here decides anything (FLT-01).
 */
interface DLNBackend {
    fun init(context: Context, apiKey: String, enableLogs: Boolean, baseUrl: String, timeoutMs: Long, retryAttempts: Int)
    suspend fun awaitInitialization(): Result<DLNAppInfo>
    suspend fun checkDeferredDeepLink(minConfidence: Double?, force: Boolean): Result<DeferredDeepLink?>
    fun resetDeferredDeepLink()
    suspend fun findDeferredUser(): Result<MatchResponse>
    suspend fun awaitReferrer(): ReferrerData?
    suspend fun checkClipboard(): String?
    suspend fun hasDeepLinkToken(): Boolean
    fun parseDeepLink(url: String): ParsedDeepLink?
    fun isValidDomain(host: String): Boolean
}

/** Forwards to the dln-android 1.3.0 public API. */
object DefaultDLNBackend : DLNBackend {
    override fun init(context: Context, apiKey: String, enableLogs: Boolean, baseUrl: String, timeoutMs: Long, retryAttempts: Int) =
        DLN.init(
            context = context,
            apiKey = apiKey,
            enableLogs = enableLogs,
            baseUrl = baseUrl,
            timeoutMs = timeoutMs,
            retryAttempts = retryAttempts,
        )

    override suspend fun awaitInitialization() = DLN.awaitInitialization()
    override suspend fun checkDeferredDeepLink(minConfidence: Double?, force: Boolean) =
        DLN.checkDeferredDeepLink(minConfidence = minConfidence, force = force)
    override fun resetDeferredDeepLink() = DLN.resetDeferredDeepLink()
    override suspend fun findDeferredUser() = DLN.findDeferredUserResult()
    override suspend fun awaitReferrer(): ReferrerData? {
        DLN.awaitInitialization()
        return DLN.awaitReferrer()
    }
    override suspend fun checkClipboard(): String? = instanceOrNull()?.checkClipboard()
    override suspend fun hasDeepLinkToken(): Boolean = instanceOrNull()?.hasDeepLinkToken() ?: false
    override fun parseDeepLink(url: String) = DLN.parseDeepLink(url)
    override fun isValidDomain(host: String) = DLN.isValidDomain(host)

    private fun instanceOrNull(): DLN? = try {
        DLN.getInstance()
    } catch (e: Exception) {
        null
    }
}

/**
 * Flutter plugin for DeepLinkNow on Android. Marshals the `com.deeplinknow/flutter` method channel
 * to dln-android and back (FLT-01). Every `suspend` SDK call runs in a plugin-owned scope on the
 * main thread (results must be delivered there), and the scope is cancelled when the engine
 * detaches (FLT-08).
 *
 * Since 1.4.0 it also reads the URL that launched the activity and every `onNewIntent` URL, and
 * hands them to Dart (`startLinks`, then `onLinkUrl`) for `DeepLinkNow.links` (SDK-87, FLT-26).
 * It only observes: `onNewIntent` returns `false`, so other plugins still see the intent.
 */
class DeepLinkNowPlugin internal constructor(
    private val backend: DLNBackend,
) : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener {

    constructor() : this(DefaultDLNBackend)

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var scope = newScope()
    private var activityBinding: ActivityPluginBinding? = null

    /** The last intent read, so `onCreate` + `onNewIntent` with the same intent is one open (SDK-88). */
    private var lastIntent: WeakReference<Intent>? = null

    /**
     * SDK-87: whether the app's manifest declares [scheme] in a VIEW intent filter (an activity of
     * this package answers `scheme://`). Tests replace it.
     */
    internal var declaresScheme: (String) -> Boolean = { scheme ->
        val ctx = context
        if (ctx == null) {
            false
        } else {
            val probe = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("$scheme://dln"))
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .setPackage(ctx.packageName)
            @Suppress("DEPRECATION")
            ctx.packageManager.queryIntentActivities(probe, 0).isNotEmpty()
        }
    }

    internal val links = DLNLinkRelay { url, delivered ->
        val ch = channel
        if (ch == null) {
            delivered(false)
        } else {
            ch.invokeMethod(
                "onLinkUrl",
                url,
                object : MethodChannel.Result {
                    override fun success(result: Any?) = delivered(true)
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = delivered(false)
                    override fun notImplemented() = delivered(false)
                },
            )
        }
    }

    private fun newScope() = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        scope = newScope()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        scope.cancel()
        context = null
        links.stop()
    }

    // ActivityAware: the launch intent and later intents (SDK-87).

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
        handleIntent(binding.activity.intent)
    }

    /** A rotation re-attaches the same activity: its intent was already read. */
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attachActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    override fun onNewIntent(intent: Intent): Boolean {
        handleIntent(intent)
        return false
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    private fun detachActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    /** Forwards a link intent's URL once per intent object; never throws (SDK-50). */
    internal fun handleIntent(intent: Intent?) {
        if (intent == null || lastIntent?.get() === intent) return
        try {
            val url = DLNLinkRelay.urlOf(intent.action, intent.dataString, intent.flags) ?: return
            lastIntent = WeakReference(intent)
            links.offer(url)
        } catch (e: Exception) {
            // A malformed intent is not a link.
        }
    }

    /** For tests: the context the plugin passes to `DLN.init`. */
    internal fun attachContextForTesting(context: Context, scope: CoroutineScope) {
        this.context = context
        this.scope = scope
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> initialize(call, result)
                "checkDeferredDeepLink" -> launch(result) {
                    val r = backend.checkDeferredDeepLink(
                        minConfidence = (call.argument<Any?>("minConfidence") as? Number)?.toDouble(),
                        force = call.argument<Boolean>("force") ?: false,
                    )
                    r.fold(
                        onSuccess = { link -> result.success(link?.let { DLNFlutterConverters.deferred(it) }) },
                        onFailure = { fail(result, it) },
                    )
                }
                "resetDeferredDeepLink" -> {
                    backend.resetDeferredDeepLink()
                    result.success(true)
                }
                "findDeferredUser" -> launch(result) {
                    backend.findDeferredUser().fold(
                        onSuccess = { result.success(DLNFlutterConverters.matchResponse(it)) },
                        onFailure = { fail(result, it) },
                    )
                }
                "getReferrerData" -> launch(result) {
                    result.success(backend.awaitReferrer()?.let { DLNFlutterConverters.referrerData(it) })
                }
                "checkClipboard" -> launch(result) { result.success(backend.checkClipboard()) }
                "hasDeepLinkToken" -> launch(result) { result.success(backend.hasDeepLinkToken()) }
                "parseDeepLink" -> {
                    val url = call.argument<String>("url")
                    result.success(url?.let { backend.parseDeepLink(it) }?.let { DLNFlutterConverters.parsed(it) })
                }
                "startLinks" -> result.success(links.start())
                "isAppScheme" -> {
                    val scheme = call.argument<String>("scheme")?.lowercase()
                    result.success(scheme != null && declaresScheme(scheme))
                }
                "isValidDomain" -> {
                    val host = call.argument<String>("host")
                    result.success(host != null && backend.isValidDomain(host))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            fail(result, e)
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val apiKey = call.argument<String>("apiKey") ?: ""
        val config = call.argument<Map<String, Any?>>("config") ?: emptyMap()
        val ctx = context
        if (ctx == null) {
            result.error("notInitialized", "Plugin is not attached to a Flutter engine", null)
            return
        }
        launch(result) {
            backend.init(
                context = ctx,
                apiKey = apiKey,
                enableLogs = config["enableLogs"] as? Boolean ?: false,
                baseUrl = config["baseUrl"] as? String ?: DLNConfig.DEFAULT_BASE_URL,
                timeoutMs = (config["timeoutMs"] as? Number)?.toLong() ?: DLNConfig.DEFAULT_TIMEOUT_MS,
                retryAttempts = (config["retryAttempts"] as? Number)?.toInt() ?: DLNConfig.DEFAULT_RETRY_ATTEMPTS,
            )
            backend.awaitInitialization().fold(
                onSuccess = { result.success(DLNFlutterConverters.appInfo(it)) },
                onFailure = { fail(result, it) },
            )
        }
    }

    /** Runs [block] in the plugin scope; any exception becomes a channel error (never a crash, SDK-50). */
    private fun launch(result: MethodChannel.Result, block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                fail(result, e)
            }
        }
    }

    private fun fail(result: MethodChannel.Result, t: Throwable?) {
        val e = DLNFlutterConverters.error(t)
        result.error(e.code, e.message, e.details)
    }

    companion object {
        const val CHANNEL = "com.deeplinknow/flutter"
    }
}
