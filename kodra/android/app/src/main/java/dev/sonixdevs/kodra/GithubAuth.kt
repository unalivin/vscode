package dev.sonixdevs.kodra

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.edit
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stage 4: GitHub authentication — Device Flow + Keystore AES-GCM.
 *
 * Flow (no client secret in APK — `local.properties` / env only):
 * 1. POST https://github.com/login/device/code  (client_id from local.properties.example)
 *    → user_code + device_code + verification_uri
 * 2. Show user_code in Workbench notification, open verification_uri via Intent
 * 3. Poll https://github.com/login/oauth/access_token until token
 * 4. Encrypt with AndroidKeyStore AES/GCM and store at filesDir/github-token (enc) + SharedPrefs iv
 * 5. Git credential helper + `github` auth provider (VS Code extension host) read via this helper
 *
 * The token is stored only as Keystore-encrypted ciphertext plus its IV. There is
 * deliberately no plaintext copy on disk: anything that needs the token (git, the
 * `github` provider) must go through [loadToken] inside this process. Nothing here
 * is logged, and the token file path is excluded from backup by backup_rules.xml.
 * `local.properties` is ignored; CI injects `GITHUB_OAUTH_CLIENT_ID` as a build field.
 */
object GithubAuth {
    private const val PREF = "kodra_auth"
    private const val KEY_ALIAS = "kodra_github_token"
    private const val KS = "AndroidKeyStore"

    fun getClientId(context: Context): String? {
        // 1. local.properties (dev)
        // 2. env fallback is build-time only — not runtime; for scaffold read SharedPrefs override
        val sp = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        return sp.getString("gh_client_id", null)
            ?: BuildConfig.GITHUB_OAUTH_CLIENT_ID.takeIf { it.isNotEmpty() }
    }

    fun setClientId(context: Context, clientId: String) {
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit {
            putString("gh_client_id", clientId)
        }
    }

    // --- Keystore AES-GCM helpers (stubbed for scaffold — real encrypt/decrypt below) ---

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance(KS).apply { load(null) }
        ks.getKey(KEY_ALIAS, null)?.let { return it as SecretKey }
        val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KS)
        kg.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return kg.generateKey()
    }

    fun encrypt(context: Context, plaintext: String): Pair<String, String> {
        // Returns (base64(iv+ciphertext), base64(iv)) — scaffold keeps API stable
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        }
        val iv = cipher.iv
        val enc = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(enc, Base64.NO_WRAP) to Base64.encodeToString(iv, Base64.NO_WRAP)
    }

    fun decrypt(context: Context, b64Enc: String, b64Iv: String): String {
        val enc = Base64.decode(b64Enc, Base64.NO_WRAP)
        val iv = Base64.decode(b64Iv, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        }
        return String(cipher.doFinal(enc), Charsets.UTF_8)
    }

    fun storeToken(context: Context, token: String) {
        val (enc, iv) = encrypt(context, token)
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit {
            putString("gh_token_enc", enc)
            putString("gh_token_iv", iv)
        }
    }

    fun loadToken(context: Context): String? {
        val sp = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val enc = sp.getString("gh_token_enc", null) ?: return null
        val iv = sp.getString("gh_token_iv", null) ?: return null
        // A Keystore key can be invalidated (device lock change, restore to a new device);
        // an unreadable token must behave like "signed out", not crash the caller.
        return runCatching { decrypt(context, enc, iv) }.getOrNull()
    }

    fun clearToken(context: Context) {
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit {
            remove("gh_token_enc"); remove("gh_token_iv")
        }
    }
}
