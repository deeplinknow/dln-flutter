package com.deeplinknow.flutter

import android.content.Context
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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
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
}
