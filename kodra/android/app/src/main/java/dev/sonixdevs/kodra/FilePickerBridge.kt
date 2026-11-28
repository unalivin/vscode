package dev.sonixdevs.kodra

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

/**
 * System picker for Open File / Open Folder (SAF). Converts SAF Uris to real POSIX paths
 * only when the provider is filesystem-backed; otherwise returns ERR_CONTENT_URI.
 *
 * Owner choice: system picker for Open File/Open Folder; VS Code simple dialog for
 * Save As / Select Folder / Git Clone (handled in JS, not here).
 *
 * See PORTING_NOTES Architecture §7 + Gate 0 report SAF risk.
 */
class FilePickerBridge(private val activity: AppCompatActivity) {

    fun interface Callback { fun onPicked(result: Result<String>) }

    private var pending: Callback? = null

    private val openFile = activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        handle(uri, pending); pending = null
    }
    private val openFolder = activity.registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        handle(uri, pending); pending = null
    }

    fun pickFile(callback: Callback) {
        pending = callback
        // Generic — server will filter; Stage 6 may add mime-type allowlist
        openFile.launch(arrayOf("*/*"))
    }

    fun pickFolder(callback: Callback) {
        pending = callback
        openFolder.launch(null)
    }

    private fun handle(uri: Uri?, cb: Callback?) {
        if (uri == null || cb == null) return
        // Persist permission so server can read across restarts
        runCatching {
            activity.contentResolver.takePersistableUriPermission(uri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        val path = resolveToPath(activity, uri)
        if (path != null) cb.onPicked(Result.success(path))
        else cb.onPicked(Result.failure(ContentUriException(activity.getString(R.string.err_content_uri))))
    }

    /**
     * Try to get a real filesystem path. Supports ExternalStorageProvider, DownloadsProvider
     * (when _data column exists), MediaProvider fallback. Returns null for content-only URIs.
     */
    fun resolveToPath(context: Context, uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        if (!DocumentsContract.isDocumentUri(context, uri)) {
            // Non-document content:// — try _data column, else fail explicitly
            return queryDataColumn(context.contentResolver, uri)
        }
        val docId = DocumentsContract.getDocumentId(uri)
        // ExternalStorageProvider
        if (isExternalStorageDocument(uri)) {
            val split = docId.split(":")
            val type = split[0]
            val rel = split.getOrNull(1) ?: ""
            if (type == "primary") return "/storage/emulated/0/$rel"
            // SD card: /storage/<type>/$rel — check if mounted
            val sd = "/storage/$type/$rel"
            if (java.io.File(sd).exists()) return sd
        }
        // DownloadsProvider / MediaProvider expose a real path through _data on the
        // providers Kodra supports; anything else stays a content-only URI and is
        // rejected rather than handed to the server as a bogus path.
        return queryDataColumn(context.contentResolver, uri)
    }

    private fun queryDataColumn(cr: ContentResolver, uri: Uri): String? = runCatching {
        cr.query(uri, arrayOf("_data"), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex("_data")
                if (idx >= 0) c.getString(idx)?.takeIf { it.isNotBlank() } else null
            } else null
        }
    }.getOrNull()

    private fun isExternalStorageDocument(uri: Uri) = "com.android.externalstorage.documents" == uri.authority

    class ContentUriException(msg: String) : IllegalArgumentException(msg)
}
