// android/app/src/main/kotlin/com/pulsefile/MainActivity.kt
package com.pulsefile

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val CH_SHARE  = "com.pulsefile/share"
        private const val CH_FILE   = "com.pulsefile/file"
        private const val CH_PICKER = "com.pulsefile/picker"
    }

    private var _pendingShare: List<String>? = null
    private var _shareChannel: MethodChannel? = null

    // Requête "Enregistrer sous" en attente (ACTION_SAVE_TO, ex. depuis PulseIt) —
    // distincte de _pendingShare pour éviter de renvoyer le mauvais évènement
    // au démarrage à froid.
    private var _pendingSave: Map<String, String>? = null

    // Requête de sélection en attente pour une app tierce (ACTION_PICK_FOLDER/
    // ACTION_PICK_FILE), et le canal utilisé par Flutter pour renvoyer le résultat.
    private var _pendingPickerRequest: Map<String, Any?>? = null
    private var _pickerChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> {
                val paths = collectSharedFiles(intent)
                if (paths.isNotEmpty()) {
                    _pendingShare = paths
                    _shareChannel?.invokeMethod("shareReceived", paths)
                }
            }
            "com.pulsefile.ACTION_SAVE_TO" -> {
                // PulseIt demande à PulseFile de choisir une destination
                val filePath = intent.getStringExtra("filePath")
                val fileName = intent.getStringExtra("fileName")
                if (filePath != null) {
                    _pendingSave = mapOf("path" to filePath, "name" to (fileName ?: File(filePath).name))
                    _shareChannel?.invokeMethod("saveRequested", _pendingSave)
                }
            }
            "com.pulsefile.ACTION_PICK_FOLDER" -> {
                _pendingPickerRequest = mapOf(
                    "type" to "folder",
                    "start" to intent.getStringExtra("start"),
                )
                _pickerChannel?.invokeMethod("pickerRequested", _pendingPickerRequest)
            }
            "com.pulsefile.ACTION_PICK_FILE" -> {
                _pendingPickerRequest = mapOf(
                    "type" to "file",
                    "start" to intent.getStringExtra("start"),
                    "multiple" to intent.getBooleanExtra("multiple", false),
                )
                _pickerChannel?.invokeMethod("pickerRequested", _pendingPickerRequest)
            }
        }
    }

    private fun collectSharedFiles(intent: Intent): List<String> {
        val uris = mutableListOf<android.net.Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                    ?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                    ?.let { uris.addAll(it) }
            }
        }
        return uris.mapNotNull { uri ->
            try {
                val name = contentResolver.query(uri, null, null, null, null)?.use { c ->
                    val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    c.moveToFirst(); if (idx >= 0) c.getString(idx) else null
                } ?: uri.lastPathSegment ?: "shared_file"
                val dest = File(cacheDir, name)
                contentResolver.openInputStream(uri)?.use { it.copyTo(dest.outputStream()) }
                dest.absolutePath
            } catch (_: Exception) { null }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Canal share : communication des fichiers entrants vers Flutter
        _shareChannel = MethodChannel(messenger, CH_SHARE).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingShare" -> {
                        result.success(_pendingShare)
                        _pendingShare = null
                    }
                    "getPendingSave" -> {
                        result.success(_pendingSave)
                        _pendingSave = null
                    }
                    "returnSaveResult" -> {
                        // PulseFile a fini de traiter la demande "Enregistrer sous"
                        // (succès ou annulation) : on renvoie le résultat à
                        // l'app appelante (ex. PulseIt) et on ferme.
                        val ok        = call.argument<Boolean>("ok") ?: false
                        val savedPath = call.argument<String>("savedPath")
                        if (ok) {
                            val data = Intent()
                            if (savedPath != null) data.putExtra("savedPath", savedPath)
                            setResult(RESULT_OK, data)
                        } else {
                            setResult(RESULT_CANCELED)
                        }
                        result.success(null)
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Canal fichiers locaux : permissions, partage, ouverture externe
        FileChannel(this).register(MethodChannel(messenger, "com.pulsefile/files"))

        // Canal sélecteur dédié : une app tierce a lancé PulseFile via
        // ACTION_PICK_FOLDER/ACTION_PICK_FILE et attend un résultat en retour
        // (startActivityForResult classique).
        _pickerChannel = MethodChannel(messenger, CH_PICKER).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingPicker" -> {
                        result.success(_pendingPickerRequest)
                        _pendingPickerRequest = null
                    }
                    "returnResult" -> {
                        val ok    = call.argument<Boolean>("ok") ?: false
                        val path  = call.argument<String>("path")
                        @Suppress("UNCHECKED_CAST")
                        val paths = call.argument<List<String>>("paths")
                        if (ok) {
                            val data = Intent()
                            if (path != null) data.putExtra("path", path)
                            if (paths != null) data.putStringArrayListExtra("paths", ArrayList(paths))
                            setResult(RESULT_OK, data)
                        } else {
                            setResult(RESULT_CANCELED)
                        }
                        result.success(null)
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Envoyer les fichiers partagés en attente à Flutter
        _pendingShare?.let { paths ->
            android.os.Handler(mainLooper).postDelayed({
                _shareChannel?.invokeMethod("shareReceived", paths)
                _pendingShare = null
            }, 800)
        }

        // Idem pour une demande "Enregistrer sous" en attente (démarrage à
        // froid via ACTION_SAVE_TO) — évènement distinct de shareReceived.
        _pendingSave?.let { save ->
            android.os.Handler(mainLooper).postDelayed({
                _shareChannel?.invokeMethod("saveRequested", save)
                _pendingSave = null
            }, 800)
        }

        // Idem pour une requête de sélection en attente (démarrage à froid
        // via ACTION_PICK_FOLDER/ACTION_PICK_FILE) : on la garde en mémoire
        // le temps que Flutter appelle getPendingPicker(), mais on la
        // renvoie aussi proactivement au cas où Flutter serait déjà prêt à
        // l'écouter (évite une course si getPendingPicker() a été appelé
        // avant que _pendingPickerRequest ne soit renseigné).
        _pendingPickerRequest?.let { req ->
            android.os.Handler(mainLooper).postDelayed({
                _pickerChannel?.invokeMethod("pickerRequested", req)
            }, 800)
        }
    }
}
