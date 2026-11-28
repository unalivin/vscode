package dev.sonixdevs.kodra

import android.content.Context
import android.util.Log
import java.io.BufferedReader
import java.io.File
import java.util.concurrent.atomic.AtomicReference

/**
 * Owns the local Node server child process (REH-web). Binds 127.0.0.1:0 + token.
 * All stdout/stderr is redacted via TokenManager.redact before Logcat.
 *
 * Lifecycle: KodraService.startForeground() → ensureBootstrap → start() → waitForPort()
 * Stop: destroy() → SIGTERM → 2s → SIGKILL, release wakeLock is service's job.
 */
class ServerProcess(private val context: Context) {
    private var proc: Process? = null
    private val bound: AtomicReference<Bound?> = AtomicReference(null)

    data class Bound(val host: String, val port: Int)

    // Regex for server print: "Web UI available at http://127.0.0.1:1234/?tkn=..."
    // and for new remoteExtensionHostAgentServer: "Server bound to 127.0.0.1:1234 (ipv4)"
    private val webUiPattern = Regex("""https?://(?<host>127\.0\.0\.1):(?<port>\d+)[^\\s]*tkn=""")
    private val boundPattern = Regex("""Server bound to (?<host>\S+):(?<port>\d+)""")

    fun start(tokenFile: File, layout: BootstrapInstaller.Layout): Bound {
        val node = File(layout.prefix, "bin/node")
        val serverJs = File(layout.prefix, "lib/node_modules/kodra-reh/out/server-main.js")
        // Stage 3 scaffold fallback: if bionic node/reh not yet bundled, use stub that fails fast
        // (so APK still installs and WebView shows bootstrap-missing error page)
        if (!node.exists() || !serverJs.exists()) {
            Log.w(TAG, "Bootstrap not installed: node=${node.exists()} serverJs=${serverJs.exists()} — serving stub error page via KodraService")
            throw BootstrapMissingException("bootstrap not installed; run Stage 2 NDK build and bundle assets")
        }

        val pb = ProcessBuilder(
            node.absolutePath,
            serverJs.absolutePath,
            "--host", "127.0.0.1",
            "--port", "0",
            // The token file is the only credential. Passing
            // --without-connection-token as well is a hard parse error in
            // serverConnectionToken.ts, and would disable authentication anyway.
            "--connection-token-file", tokenFile.absolutePath,
            "--user-data-dir", File(context.filesDir, "user-data").absolutePath,
            "--extensions-dir", File(layout.prefix, "lib/node_modules/kodra-reh/extensions").absolutePath
        ).apply {
            environment()["HOME"] = layout.home.absolutePath
            environment()["PREFIX"] = layout.prefix.absolutePath
            environment()["TMPDIR"] = layout.tmp.absolutePath
            environment()["LD_LIBRARY_PATH"] = "${layout.prefix.absolutePath}/lib"
            directory(layout.home)
            redirectErrorStream(true)
        }

        Log.i(TAG, "Starting ${pb.command().joinToString(" ")}".let(TokenManager::redact))
        proc = pb.start()

        // Wait for bound line (15s) — parse host:port for WebView
        val reader = proc!!.inputStream.bufferedReader()
        val deadline = System.currentTimeMillis() + 15_000
        var line: String?
        while (System.currentTimeMillis() < deadline) {
            line = reader.readLine() ?: break
            val redacted = TokenManager.redact(line)
            Log.i(TAG, redacted)
            (parseBound(line) ?: parseBoundWebUi(line))?.let {
                bound.set(it)
                // Keep draining logs on background thread
                drainInBackground(reader)
                return it
            }
        }
        stop()
        throw IllegalStateException("Server did not bind within 15s — check bootstrap/node")
    }

    private fun parseBound(line: String): Bound? =
        boundPattern.find(line)?.let {
            Bound(it.groups["host"]!!.value, it.groups["port"]!!.value.toInt())
        }

    private fun parseBoundWebUi(line: String): Bound? =
        webUiPattern.find(line)?.let {
            Bound(it.groups["host"]!!.value, it.groups["port"]!!.value.toInt())
        }

    private fun drainInBackground(r: BufferedReader) {
        Thread {
            try {
                var l: String?
                while (r.readLine().also { l = it } != null) {
                    Log.i(TAG, TokenManager.redact(l!!))
                }
            } catch (_: Exception) {}
        }.also { it.isDaemon = true; it.start() }
    }

    fun stop() {
        proc?.let { p ->
            try { p.destroy() } catch (_: Exception) {}
            try { p.waitFor(2, java.util.concurrent.TimeUnit.SECONDS) } catch (_: Exception) {}
            if (p.isAlive) try { p.destroyForcibly() } catch (_: Exception) {}
        }
        proc = null
        bound.set(null)
    }

    fun isAlive(): Boolean = proc?.isAlive == true

    companion object { const val TAG = "KodraService" }

    class BootstrapMissingException(msg: String) : IllegalStateException(msg)
}
