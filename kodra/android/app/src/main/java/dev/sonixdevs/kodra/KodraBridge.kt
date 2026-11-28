package dev.sonixdevs.kodra

/**
 * The complete set of methods the workbench page may call across the WebView bridge.
 *
 * Everything else is refused before a platform API is touched: the workbench runs
 * arbitrary extension code, so a general-purpose JS interface would hand that code the
 * device. Adding a method here is the only way to widen the surface, and each entry
 * has to be backed by a case in [WorkbenchBridge].
 */
object KodraBridgeWhiteList {
    const val CHANNEL = "kodra"

    val allowedMethods = setOf(
        "clipboard.readText", "clipboard.writeText",
        "dialog.openFile", "dialog.openFolder",
        "auth.githubDeviceFlow", "auth.getToken", "auth.clearToken",
        "service.stop", "service.reconnect",
        "insets.setImmersive"
    )
}
