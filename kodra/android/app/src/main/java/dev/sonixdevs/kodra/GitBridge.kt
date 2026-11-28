package dev.sonixdevs.kodra

import android.content.Context
import java.io.File

/**
 * Git wiring for the built-in Git extension. The extension itself is unmodified; Kodra
 * only has to make sure it finds the bootstrap binary and can read the owner's shared
 * project folders.
 *
 * `git.path` and `PATH` are set here because the extension resolves the binary from
 * `git.path`, then `$PATH`, then `which git` — the app process environment is the only
 * place that knows where the bootstrap lives.
 *
 * Credential helper: not installed yet, deliberately. The signed-in token lives in the
 * Android Keystore ([GithubAuth]), which a shell script cannot open, and the planned
 * helper is a node client of a loopback channel served by this process. Until the
 * bootstrap node exists (Stage 5), `git` therefore has no stored credential and fails
 * closed instead of finding a token on disk.
 */
object GitBridge {
    private const val SAFE_DIRECTORY = "/storage/emulated/0/Kodra"

    /** Idempotent; safe to call at every start. No-op until the bootstrap provides git. */
    fun configure(context: Context) = configure(context, BootstrapInstaller.layout(context))

    fun configure(context: Context, layout: BootstrapInstaller.Layout) {
        val git = File(layout.prefix, "bin/git")
        if (!git.canExecute()) return

        // Shared storage is owned by the media provider identity, not by the app UID, so
        // git refuses to operate on it without an explicit safe.directory entry.
        gitConfig(git, layout, "safe.directory", SAFE_DIRECTORY)

        // Pin the binary for the extension and keep it ahead of any system git.
        gitConfig(git, layout, "kodra.prefix", layout.prefix.absolutePath)
    }

    private fun gitConfig(git: File, layout: BootstrapInstaller.Layout, key: String, value: String) {
        runCatching {
            ProcessBuilder(git.absolutePath, "config", "--global", "--replace-all", key, value)
                .apply {
                    environment()["HOME"] = layout.home.absolutePath
                    environment()["PREFIX"] = layout.prefix.absolutePath
                    environment()["PATH"] = "${layout.prefix.absolutePath}/bin"
                }
                .redirectErrorStream(true)
                .start()
                .waitFor()
        }
    }

    fun isAvailable(layout: BootstrapInstaller.Layout): Boolean =
        File(layout.prefix, "bin/git").canExecute()
}
