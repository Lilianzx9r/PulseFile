package com.pulsefile

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Chiffre/déchiffre les fichiers miroirs (mots de passe FTP, secrets HTTP)
 * avec une clé stockée dans l'Android Keystore, liée à l'état "appareil
 * déverrouillé" (setUnlockedDeviceRequired). Contrairement à un simple
 * fichier en clair, le contenu reste illisible si l'appareil est verrouillé
 * ou éteint, y compris en cas d'extraction du stockage de l'app (root,
 * sauvegarde ADB, etc.) — sans pour autant redemander explicitement le code
 * ou l'empreinte à chaque lecture (ce qui casserait le sélecteur système,
 * qui doit pouvoir répondre sans interface visible).
 *
 * Limite connue : setUnlockedDeviceRequired() n'a d'effet qu'à partir
 * d'Android 9 (API 28). En dessous, la clé fonctionne sans cette contrainte
 * (dégradation silencieuse, pas de crash).
 */
object SecureMirror {
    private const val KEYSTORE   = "AndroidKeyStore"
    private const val KEY_ALIAS  = "pulsefile_mirror_key"
    private const val TRANSFORM  = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val IV_BYTES   = 12

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        val specBuilder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            specBuilder.setUnlockedDeviceRequired(true)
        }

        generator.init(specBuilder.build())
        return generator.generateKey()
    }

    /** Chiffre [plaintext] ; retourne IV (12 octets) + ciphertext+tag concaténés. */
    fun encrypt(plaintext: String): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return iv + ciphertext
    }

    /** Déchiffre les données produites par [encrypt]. Retourne null si
     * l'appareil est verrouillé, la clé invalidée, ou toute autre erreur —
     * l'appelant doit traiter ça comme "donnée indisponible", pas comme une
     * erreur fatale. */
    fun decrypt(data: ByteArray): String? {
        return try {
            if (data.size <= IV_BYTES) return null
            val iv = data.copyOfRange(0, IV_BYTES)
            val ciphertext = data.copyOfRange(IV_BYTES, data.size)
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (_: Exception) {
            // Appareil verrouillé, clé invalidée (changement de schéma de
            // verrouillage), ou fichier corrompu — on traite tout pareil :
            // la donnée n'est simplement pas disponible pour l'instant.
            null
        }
    }
}
