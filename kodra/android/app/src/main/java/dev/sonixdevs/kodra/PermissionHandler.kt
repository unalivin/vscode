package dev.sonixdevs.kodra

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

/**
 * Handles runtime permissions for Kodra:
 * - POST_NOTIFICATIONS (Android 13+)
 * - MANAGE_EXTERNAL_STORAGE (All files access for /storage/emulated/0/Kodra, targetSdk 28)
 * - REQUEST_IGNORE_BATTERY_OPTIMIZATIONS via docs/BATTERY.md
 */
class PermissionHandler(private val activity: AppCompatActivity) {

    private val requestNotifications = activity.registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* no-op — notification will just not show if denied */ }

    private val manageAllFiles = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { /* user returns from Settings — check again */ }

    fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager()
        else true // targetSdk 28: legacy storage still allows /sdcard/Kodra via WRITE_EXTERNAL_STORAGE

    fun requestAllFilesAccess() {
        if (!hasAllFilesAccess() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                manageAllFiles.launch(intent)
            }.onFailure {
                manageAllFiles.launch(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        }
    }

}
