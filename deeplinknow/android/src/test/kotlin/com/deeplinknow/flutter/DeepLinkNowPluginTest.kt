package com.deeplinknow.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.deeplinknow.DLNAppInfo
import com.deeplinknow.DLNConfig
import com.deeplinknow.DLNErrorCode
import com.deeplinknow.DLNException
import com.deeplinknow.DeeplinkMatch
import com.deeplinknow.DeferredDeepLink
import com.deeplinknow.DeferredDeepLinkSource
import com.deeplinknow.DeviceMatchDetails
import com.deeplinknow.LocaleMatchDetails
import com.deeplinknow.Match
import com.deeplinknow.MatchComponentDetails
import com.deeplinknow.MatchDetails
import com.deeplinknow.MatchQuality
import com.deeplinknow.MatchResponse
import com.deeplinknow.ParsedDeepLink
import com.deeplinknow.QueryValue
import com.deeplinknow.ReferrerData
import com.deeplinknow.TimeProximityDetails
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Records what the plugin sends back over the channel. */
private class RecordingResult : MethodChannel.Result {
    var value: Any? = null
    var errorCode: String? = null
    var errorMessage: String? = null
    var errorDetails: Any? = null
    var notImplemented = false
    var replies = 0

    override fun success(result: Any?) {
        value = result
        replies++
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.errorDetails = errorDetails
        replies++
    }

    override fun notImplemented() {
        notImplemented = true
        replies++
    }
}

/** A scripted dln-android. */
private class FakeBackend : DLNBackend {
    var initArgs: List<Any?>? = null
    var initResult: Result<DLNAppInfo> = Result.success(appInfo())
    var checkArgs: Pair<Double?, Boolean>? = null
    var checkResult: Result<DeferredDeepLink?> = Result.success(null)
    var findResult: Result<MatchResponse> = Result.success(MatchResponse(emptyList(), 3600))
    var referrer: ReferrerData? = null
    var clipboard: String? = null
    var token = false
    var parsed: ParsedDeepLink? = null
    var resets = 0
    var throwOnCheck: Exception? = null

    override fun init(context: Context, apiKey: String, enableLogs: Boolean, baseUrl: String, timeoutMs: Long, retryAttempts: Int) {
        initArgs = listOf(apiKey, enableLogs, baseUrl, timeoutMs, retryAttempts)
    }

    override suspend fun awaitInitialization() = initResult
    override suspend fun checkDeferredDeepLink(minConfidence: Double?, force: Boolean): Result<DeferredDeepLink?> {
        throwOnCheck?.let { throw it }
        checkArgs = minConfidence to force
        return checkResult
    }
    override fun resetDeferredDeepLink() { resets++ }
    override suspend fun findDeferredUser() = findResult
    override suspend fun awaitReferrer() = referrer
    override suspend fun checkClipboard() = clipboard
    override suspend fun hasDeepLinkToken() = token
    override fun parseDeepLink(url: String) = parsed
    override fun isValidDomain(host: String) = host == "myapp.deeplinknow.com"

    companion object {
        fun appInfo() = DLNAppInfo(
            appId = "app_1",
            alias = "myapp",
            name = null,
            linkDomains = linkedSetOf("myapp.deeplinknow.com", "go.myapp.com"),
            accountStatus = "active",
            creditsRemaining = 5,
        )
    }
}

private fun details() = MatchDetails(
    ipMatch = MatchComponentDetails(true, 40.0),
    deviceMatch = DeviceMatchDetails(true, 30.0, DeviceMatchDetails.DeviceComponents(true, true, true, false)),
    timeProximity = TimeProximityDetails(20.0, 2),
    localeMatch = LocaleMatchDetails(false, 0.0, LocaleMatchDetails.LocaleComponents(false, true)),
)

internal class DeepLinkNowPluginTest {
    private val backend = FakeBackend()
    private val plugin = DeepLinkNowPlugin(backend).also {
        it.attachContextForTesting(Mockito.mock(Context::class.java), CoroutineScope(Dispatchers.Unconfined))
    }

    private fun call(method: String, args: Map<String, Any?>? = null): RecordingResult {
        val result = RecordingResult()
        plugin.onMethodCall(MethodCall(method, args), result)
        assertEquals(1, result.replies, "exactly one reply for $method")
        return result
    }

    @Test
    fun `FLT-04 initialize passes the key and config, and returns the app info`() {
        val r = call(
            "initialize",
            mapOf("apiKey" to "dln_pub_x", "config" to mapOf("enableLogs" to true, "baseUrl" to "https://s.example.com", "timeoutMs" to 5000, "retryAttempts" to 1)),
        )
        assertEquals(listOf("dln_pub_x", true, "https://s.example.com", 5000L, 1), backend.initArgs)
        @Suppress("UNCHECKED_CAST")
        val info = r.value as Map<String, Any?>
        assertEquals("app_1", info["id"])
        assertEquals(listOf("myapp.deeplinknow.com", "go.myapp.com"), info["domains"])
        assertEquals("go.myapp.com", info["primaryDomain"])
        assertEquals(5, info["creditsRemaining"])
    }

    @Test
    fun `FLT-04 initialize uses the native defaults for unset config`() {
        call("initialize", mapOf("apiKey" to "dln_pub_x", "config" to mapOf("enableLogs" to false)))
        assertEquals(
            listOf("dln_pub_x", false, DLNConfig.DEFAULT_BASE_URL, DLNConfig.DEFAULT_TIMEOUT_MS, DLNConfig.DEFAULT_RETRY_ATTEMPTS),
            backend.initArgs,
        )
    }

    @Test
    fun `FLT-07 a failed initialize is a channel error with the shared code and details`() {
        backend.initResult = Result.failure(DLNException(DLNErrorCode.INVALID_API_KEY, httpStatus = 401, serverMessage = "Invalid API key"))
        val r = call("initialize", mapOf("apiKey" to "bad"))
        assertEquals("invalidApiKey", r.errorCode)
        assertEquals(mapOf("status" to 401, "serverMessage" to "Invalid API key"), r.errorDetails)
    }

    @Test
    fun `FLT-06 checkDeferredDeepLink passes minConfidence and force through`() {
        call("checkDeferredDeepLink", mapOf("minConfidence" to 75, "useClipboard" to true, "force" to true))
        assertEquals(75.0 to true, backend.checkArgs)
        call("checkDeferredDeepLink", mapOf("minConfidence" to null, "useClipboard" to true, "force" to false))
        assertEquals(null to false, backend.checkArgs)
    }

    @Test
    fun `FLT-05 checkDeferredDeepLink returns the camelCase shape`() {
        backend.checkResult = Result.success(
            DeferredDeepLink(
                path = "/promo",
                queryParams = linkedMapOf("code" to QueryValue.Single("SAVE20"), "debug" to QueryValue.Flag, "t" to QueryValue.Multiple(listOf("a", "b"))),
                fullPath = "/promo?code=SAVE20&debug&t=a&t=b",
                url = "https://go.myapp.com/promo?code=SAVE20&debug&t=a&t=b",
                source = DeferredDeepLinkSource.FINGERPRINT,
                confidenceScore = 62.5,
                matchQuality = MatchQuality.MEDIUM,
                deeplinkId = "dl_1",
                metadata = mapOf("weight" to 1.5f),
                matchDetails = details(),
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val link = call("checkDeferredDeepLink", mapOf("force" to false)).value as Map<String, Any?>
        assertEquals("/promo", link["path"])
        assertEquals(mapOf("code" to "SAVE20", "debug" to true, "t" to listOf("a", "b")), link["queryParams"])
        assertEquals("fingerprint", link["source"])
        assertEquals(62.5, link["confidenceScore"])
        assertEquals("MEDIUM", link["matchQuality"])
        assertEquals("dl_1", link["deeplinkId"])
        assertTrue("targetUrl" !in link, "absent optionals are omitted")
        assertEquals(mapOf("weight" to 1.5), link["metadata"], "Float becomes a codec-safe Double")
        @Suppress("UNCHECKED_CAST")
        val md = link["matchDetails"] as Map<String, Map<String, Any?>>
        assertEquals(mapOf("matched" to true, "score" to 40.0), md["ip_match"])
        assertEquals(2, md["time_proximity"]!!["time_difference_minutes"])
    }

    @Test
    fun `FLT-07 notInitialized carries its cause`() {
        backend.checkResult = Result.failure(
            DLNException(DLNErrorCode.NOT_INITIALIZED, cause = DLNException(DLNErrorCode.NETWORK)),
        )
        val r = call("checkDeferredDeepLink", emptyMap())
        assertEquals("notInitialized", r.errorCode)
        @Suppress("UNCHECKED_CAST")
        val d = r.errorDetails as Map<String, Any?>
        assertEquals("network", d["causeCode"])
    }

    @Test
    fun `FLT-08 an exception from the SDK becomes invalidResponse, never a crash`() {
        backend.throwOnCheck = IllegalStateException("boom")
        val r = call("checkDeferredDeepLink", emptyMap())
        assertEquals("invalidResponse", r.errorCode)
        assertEquals("boom", r.errorMessage)
    }

    @Test
    fun `FLT-12 findDeferredUser returns the snake_case wire shape in server order`() {
        val deeplink = DeeplinkMatch(
            id = "dl_1",
            targetUrl = "https://go.myapp.com/a",
            metadata = emptyMap(),
            campaignId = null,
            matchedAt = "2026-10-21T10:00:00Z",
            expiresAt = "2026-10-21T11:00:00Z",
            queryParams = mapOf("x" to "1"),
            fullPath = "/a?x=1",
        )
        backend.findResult = Result.success(
            MatchResponse(
                listOf(
                    Match(deeplink, 90.0, details(), "HIGH"),
                    Match(null, 55.0, details(), null),
                ),
                3600,
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val r = call("findDeferredUser").value as Map<String, Any?>
        assertEquals(3600, r["ttl_seconds"])
        @Suppress("UNCHECKED_CAST")
        val matches = r["matches"] as List<Map<String, Any?>>
        assertEquals(90.0, matches[0]["confidence_score"])
        assertEquals("HIGH", matches[0]["match_quality"])
        @Suppress("UNCHECKED_CAST")
        val dl = matches[0]["deeplink"] as Map<String, Any?>
        assertEquals("https://go.myapp.com/a", dl["target_url"])
        assertEquals(mapOf("x" to "1"), dl["query_params"])
        assertEquals("/a?x=1", dl["full_path"])
        assertEquals("MEDIUM", matches[1]["match_quality"], "older servers: derived from the score (SDK-16)")
        assertTrue("deeplink" !in matches[1])
    }

    @Test
    fun `FLT-11 resetDeferredDeepLink calls the SDK`() {
        assertEquals(true, call("resetDeferredDeepLink").value)
        assertEquals(1, backend.resets)
    }

    @Test
    fun `FLT-13 getReferrerData omits absent optional keys`() {
        backend.referrer = ReferrerData("fp_id=abc", "abc", null, null, 1792576800000L)
        assertEquals(
            mapOf("referrerString" to "fp_id=abc", "processedAt" to 1792576800000L, "fpId" to "abc"),
            call("getReferrerData").value,
        )
        backend.referrer = null
        assertNull(call("getReferrerData").value)
    }

    @Test
    fun `FLT-14 clipboard calls return the SDK results`() {
        backend.clipboard = "https://myapp.deeplinknow.com/a"
        backend.token = true
        assertEquals("https://myapp.deeplinknow.com/a", call("checkClipboard").value)
        assertEquals(true, call("hasDeepLinkToken").value)
    }

    @Test
    fun `FLT-15 parseDeepLink returns the camelCase shape or null`() {
        assertNull(call("parseDeepLink", mapOf("url" to "https://evil.com/")).value)
        assertNull(call("parseDeepLink", emptyMap()).value)
        backend.parsed = ParsedDeepLink("/a", linkedMapOf("k" to QueryValue.Flag), "/a?k", "https://myapp.deeplinknow.com/a?k")
        assertEquals(
            mapOf("path" to "/a", "queryParams" to mapOf("k" to true), "fullPath" to "/a?k", "url" to "https://myapp.deeplinknow.com/a?k"),
            call("parseDeepLink", mapOf("url" to "https://myapp.deeplinknow.com/a?k")).value,
        )
    }

    @Test
    fun `FLT-16 isValidDomain returns the SDK answer, false without a host`() {
        assertEquals(true, call("isValidDomain", mapOf("host" to "myapp.deeplinknow.com")).value)
        assertEquals(false, call("isValidDomain", mapOf("host" to "evil.com")).value)
        assertEquals(false, call("isValidDomain", emptyMap()).value)
    }

    @Test
    fun `FLT-01 unknown methods are not implemented`() {
        assertTrue(call("getPlatformVersion").notImplemented)
    }

    private fun viewIntent(url: String?, flags: Int = 0): Intent {
        val intent = Mockito.mock(Intent::class.java)
        Mockito.`when`(intent.action).thenReturn(Intent.ACTION_VIEW)
        Mockito.`when`(intent.dataString).thenReturn(url)
        Mockito.`when`(intent.flags).thenReturn(flags)
        return intent
    }

    @Test
    fun `SDK-87 FLT-26 the launch URL is buffered until Dart calls startLinks`() {
        plugin.handleIntent(viewIntent("https://myapp.deeplinknow.com/launch"))
        assertEquals(listOf("https://myapp.deeplinknow.com/launch"), call("startLinks").value)
        assertEquals(emptyList<String>(), call("startLinks").value, "taken once")
    }

    @Test
    fun `SDK-87 FLT-26 only ACTION_VIEW intents with data are links`() {
        val main = Mockito.mock(Intent::class.java)
        Mockito.`when`(main.action).thenReturn(Intent.ACTION_MAIN)
        plugin.handleIntent(main)
        plugin.handleIntent(viewIntent(null))
        plugin.handleIntent(null)
        assertEquals(emptyList<String>(), call("startLinks").value)
    }

    @Test
    fun `SDK-88 FLT-27 the same intent object (onCreate plus onNewIntent) is read once`() {
        val intent = viewIntent("https://myapp.deeplinknow.com/a")
        plugin.handleIntent(intent)
        assertFalse(plugin.onNewIntent(intent), "observes only, never consumes the intent")
        assertEquals(listOf("https://myapp.deeplinknow.com/a"), call("startLinks").value)
    }

    @Test
    fun `SDK-88 FLT-27 an activity reopened from Recents does not replay its link`() {
        plugin.handleIntent(viewIntent("https://myapp.deeplinknow.com/a", DLNLinkRelay.FLAG_LAUNCHED_FROM_HISTORY))
        assertEquals(emptyList<String>(), call("startLinks").value)
    }

    @Test
    fun `SDK-87 FLT-26 after startLinks each new URL is pushed, and a failed push is buffered again`() {
        val pushed = mutableListOf<String>()
        var answer = true
        val relay = DLNLinkRelay { url, delivered ->
            pushed += url
            delivered(answer)
        }
        relay.offer("https://a/1")
        assertEquals(listOf("https://a/1"), relay.start())
        relay.offer("https://a/2")
        assertEquals(listOf("https://a/2"), pushed)
        answer = false // Dart has no handler (hot restart)
        relay.offer("https://a/3")
        relay.offer("https://a/4")
        assertEquals(listOf("https://a/2", "https://a/3"), pushed, "stops pushing after a failed push")
        assertEquals(listOf("https://a/3", "https://a/4"), relay.start())
    }

    @Test
    fun `SDK-87 FLT-26 without a Flutter engine a URL stays buffered`() {
        plugin.handleIntent(viewIntent("https://myapp.deeplinknow.com/x"))
        call("startLinks")
        plugin.onNewIntent(viewIntent("https://myapp.deeplinknow.com/y"))
        assertEquals(listOf("https://myapp.deeplinknow.com/y"), call("startLinks").value)
    }

    @Test
    fun `SDK-87 FLT-26 isAppScheme answers from the manifest check, lowercased`() {
        plugin.declaresScheme = { it.startsWith("myapp:") }
        assertEquals(true, call("isAppScheme", mapOf("scheme" to "MyApp")).value)
        assertEquals(false, call("isAppScheme", mapOf("scheme" to "other")).value)
        assertEquals(false, call("isAppScheme", emptyMap()).value)
    }

    @Test
    fun `SDK-87 FLT-33 isAppScheme probes the manifest with the real URL, so host-restricted filters match`() {
        val probed = mutableListOf<String>()
        // A filter like FlutterFlow's: scheme myapp, host myapp.com.
        plugin.declaresScheme = { url -> probed += url; url.startsWith("myapp://myapp.com") }
        val args = mapOf("scheme" to "myapp", "url" to "myapp://myapp.com/products/1?x=1")
        assertEquals(true, call("isAppScheme", args).value)
        assertEquals(listOf("myapp://myapp.com/products/1?x=1"), probed)
        // A URL that doesn't belong to the scheme is never probed.
        assertEquals(false, call("isAppScheme", mapOf("scheme" to "myapp", "url" to "other://x")).value)
        assertEquals("myapp://dln", probed.last())
    }

    private fun attach(url: String): Pair<() -> Unit, ActivityPluginBinding> {
        var posted: (() -> Unit)? = null
        plugin.postToMain = { posted = it }
        val activity = Mockito.mock(Activity::class.java)
        val intent = viewIntent(url)
        Mockito.`when`(activity.intent).thenReturn(intent)
        val binding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(binding.activity).thenReturn(activity)
        plugin.onAttachedToActivity(binding)
        return { posted!!.invoke() } to binding
    }

    @Test
    fun `SDK-88 FLT-32 an activity re-created from saved state does not forward its launch URL again`() {
        val (runPosted, binding) = attach("https://myapp.deeplinknow.com/launch")
        Mockito.verify(binding).addOnSaveStateListener(plugin)
        val saved = Mockito.mock(Bundle::class.java)
        Mockito.`when`(saved.getBoolean(DeepLinkNowPlugin.STATE_LAUNCH_READ, false)).thenReturn(true)
        plugin.onRestoreInstanceState(saved) // same onCreate, after the attach
        runPosted()
        assertEquals(emptyList<String>(), call("startLinks").value)
    }

    @Test
    fun `SDK-87 FLT-32 a fresh launch forwards its URL once the activity is created, and saves the mark`() {
        val (runPosted, _) = attach("https://myapp.deeplinknow.com/launch")
        plugin.onRestoreInstanceState(null)
        runPosted()
        assertEquals(listOf("https://myapp.deeplinknow.com/launch"), call("startLinks").value)
        val out = Mockito.mock(Bundle::class.java)
        plugin.onSaveInstanceState(out)
        Mockito.verify(out).putBoolean(DeepLinkNowPlugin.STATE_LAUNCH_READ, true)
    }
}
