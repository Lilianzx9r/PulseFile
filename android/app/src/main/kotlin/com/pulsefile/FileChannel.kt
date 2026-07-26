// android/app/src/main/kotlin/com/pulsefile/FileChannel.kt
//
// Canal natif pour les opérations fichiers locales : permissions, partage,
// ouverture avec une app externe. Utilisé par FileManagerScreen (onglet Local).
//
package com.pulsefile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

class FileChannel(private val ctx: Context) {

    fun register(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    requestStoragePermission()
                    result.success(null)
                }
                "getFilesDir" -> {
                    // Utilisé pour écrire un miroir en clair des connexions HTTP
                    // (voir PulseFileDocumentsProvider.kt) : garantit le même
                    // chemin absolu que celui lu côté natif.
                    result.success(ctx.filesDir.absolutePath)
                }
                "writeSecureMirror" -> {
                    // Chiffre [content] avec la clé Android Keystore liée à
                    // l'état "appareil déverrouillé" (voir SecureMirror.kt),
                    // puis écrit le résultat dans le dossier privé de l'app.
                    // Utilisé pour les miroirs FTP/HTTP lus par
                    // PulseFileDocumentsProvider.kt.
                    val filename = call.argument<String>("filename")
                    val content  = call.argument<String>("content")
                    if (filename == null || content == null) {
                        result.success(false)
                    } else {
                        try {
                            val encrypted = SecureMirror.encrypt(content)
                            File(ctx.filesDir, filename).writeBytes(encrypted)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) { result.error("ERR", "no path", null); return@setMethodCallHandler }
                    try {
                        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", File(path))
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "*/*"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        ctx.startActivity(Intent.createChooser(intent, "Partager").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    } catch (e: Exception) { result.error("ERR", e.message, null) }
                }
                "openFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) { result.error("ERR", "no path", null); return@setMethodCallHandler }
                    try {
                        val uri  = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", File(path))
                        // .apk : on force explicitement le type MIME de l'installeur
                        // Android plutôt que de laisser contentResolver.getType()
                        // deviner — sinon Android propose parfois un chooser
                        // générique au lieu de déclencher l'installation.
                        val mime = if (path.endsWith(".apk", ignoreCase = true))
                            "application/vnd.android.package-archive"
                        else
                            ctx.contentResolver.getType(uri) ?: "*/*"
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mime)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (mime == "application/vnd.android.package-archive") {
                            // Lancement direct : ACTION_VIEW avec ce MIME déclenche
                            // l'installeur système sans passer par un chooser.
                            ctx.startActivity(intent)
                        } else {
                            ctx.startActivity(Intent.createChooser(intent, "Ouvrir avec…").apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            })
                        }
                        result.success(null)
                    } catch (e: Exception) { result.error("ERR", e.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestStoragePermission() {
        val activity = ctx as? Activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!android.os.Environment.isExternalStorageManager()) {
                try {
                    val intent = Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.data = Uri.parse("package:${ctx.packageName}")
                    activity.startActivity(intent)
                } catch (_: Exception) {
                    activity.startActivity(Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                }
            }
        } else {
            val perms = arrayOf(
                android.Manifest.permission.READ_EXTERNAL_STORAGE,
                android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
            val missing = perms.filter {
                ContextCompat.checkSelfPermission(ctx, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing.isNotEmpty()) {
                ActivityCompat.requestPermissions(activity, missing.toTypedArray(), 5501)
            }
        }
    }
}
