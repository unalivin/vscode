package dev.sonixdevs.kodra

import android.app.Activity
import android.os.Build
import android.view.View
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/**
 * Edge-to-edge, immersive bars, display cutout and IME handling.
 *
 * Owner decision: immersive by default (transient bars by swipe), edge to edge, with an
 * in-app setting to turn it off. Because the WebView draws behind the system bars, the
 * workbench gets the full screen height and its own layout does the rest — nothing here
 * reflows or shrinks the workbench UI.
 */
object InsetsBridge {
    fun apply(activity: Activity, webView: View, immersive: Boolean = true) {
        WindowCompat.setDecorFitsSystemWindows(activity.window, false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // `window.attributes` hands back a copy; writing to it without assigning it
            // back is a silent no-op.
            val lp = activity.window.attributes
            lp.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            activity.window.attributes = lp
        }

        val controller = WindowInsetsControllerCompat(activity.window, webView)
        // Swipe from an edge reveals the bars momentarily without leaving immersive mode.
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.isAppearanceLightStatusBars = !isDark(activity)

        if (immersive) {
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }

        // Edge to edge means the system no longer shrinks the window for the keyboard,
        // so the WebView is padded by the IME (and, when the bars are visible, by the
        // navigation bar) and the workbench keeps its status bar and last editor line
        // reachable above the extra-keys row.
        webView.setOnApplyWindowInsetsListener { view, insets ->
            val compat = WindowInsetsCompat.toWindowInsetsCompat(insets, view)
            val bottom = maxOf(
                compat.getInsets(WindowInsetsCompat.Type.ime()).bottom,
                compat.getInsets(WindowInsetsCompat.Type.systemBars()).bottom
            )
            if (view.paddingBottom != bottom) {
                view.setPadding(view.paddingLeft, view.paddingTop, view.paddingRight, bottom)
            }
            insets
        }
    }

    fun setImmersive(activity: Activity, webView: View, enabled: Boolean) =
        apply(activity, webView, enabled)

    private fun isDark(activity: Activity): Boolean {
        val nightMode = activity.resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK
        return nightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
    }
}
