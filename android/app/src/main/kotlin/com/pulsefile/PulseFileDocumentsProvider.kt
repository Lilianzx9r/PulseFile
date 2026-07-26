// android/app/src/main/kotlin/com/pulseit/PulseItDocumentsProvider.kt
//
// Storage Access Framework DocumentsProvider.
// Expose les connexions FTP et PHP/HTTP de PulseIt dans le sélecteur
// de fichiers Android natif (autres apps, gestionnaires de fichiers...).
//
package com.pulsefile

import android.content.Context
import android.database.MatrixCursor
import android.net.Uri
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.util.Base64
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.*
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL

class PulseFileDocumentsProvider : DocumentsProvider() {

    companion object {
        const val AUTHORITY = "com.pulsefile.documents"
        private const val TAG = "PulseItDocs"
        private val ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID, Root.COLUMN_MIME_TYPES, Root.COLUMN_FLAGS,
            Root.COLUMN_ICON, Root.COLUMN_TITLE, Root.COLUMN_DOCUMENT_ID)
        private val DOC_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME, Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS, Document.COLUMN_SIZE)
    }

    override fun onCreate() = true

    // ── Racines ────────────────────────────────────────────────────────────────

    override fun queryRoots(projection: Array<String>?): android.database.Cursor {
        val cursor = MatrixCursor(projection ?: ROOT_PROJECTION)
        val ctx = context ?: return cursor
        try {
            val db = ctx.getDatabasePath("pulseit.db")
            if (db.exists()) {
                val d = android.database.sqlite.SQLiteDatabase.openDatabase(
                    db.absolutePath, null,
                    android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
                val c = d.rawQuery("SELECT id,name,host FROM ftp_connections", null)
                while (c.moveToNext()) {
                    val id = c.getInt(0); val name = c.getString(1); val host = c.getString(2)
                    cursor.newRow()
                        .add(Root.COLUMN_ROOT_ID,    "ftp:$id")
                        .add(Root.COLUMN_TITLE,       "$name (FTP $host)")
                        .add(Root.COLUMN_DOCUMENT_ID, "ftp:$id:/")
                        .add(Root.COLUMN_MIME_TYPES,  "*/*")
                        .add(Root.COLUMN_ICON,        android.R.drawable.ic_menu_upload)
                        .add(Root.COLUMN_FLAGS,
                            Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_RECENTS)
                }
                c.close(); d.close()
            }
        } catch (e: Exception) { Log.e(TAG, "FTP roots: ${e.message}") }

        try {
            val arr = readHttpMirror()
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val o    = arr.getJSONObject(i)
                    val id   = o.optInt("id", -1); if (id < 0) continue
                    val name = o.optString("name"); if (name.isEmpty()) continue
                    cursor.newRow()
                        .add(Root.COLUMN_ROOT_ID,    "http:$id")
                        .add(Root.COLUMN_TITLE,       "$name (HTTP)")
                        .add(Root.COLUMN_DOCUMENT_ID, "http:$id:.")
                        .add(Root.COLUMN_MIME_TYPES,  "*/*")
                        .add(Root.COLUMN_ICON,        android.R.drawable.ic_menu_upload)
                        .add(Root.COLUMN_FLAGS,
                            Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_RECENTS)
                }
            }
        } catch (e: Exception) { Log.e(TAG, "HTTP roots: ${e.message}") }

        return cursor
    }

    // ── Contenu d'un dossier ───────────────────────────────────────────────────

    override fun queryChildDocuments(parentDocumentId: String,
            projection: Array<String>?, sortOrder: String?): android.database.Cursor {
        val cursor = MatrixCursor(projection ?: DOC_PROJECTION)
        val (type, id, path) = parseDocId(parentDocumentId) ?: return cursor
        try {
            when (type) {
                "ftp"  -> listFtp(id, path, cursor)
                "http" -> listHttp(id, path, cursor)
            }
        } catch (e: Exception) { Log.e(TAG, "list error: ${e.message}") }
        return cursor
    }

    override fun queryDocument(documentId: String,
            projection: Array<String>?): android.database.Cursor {
        val cursor = MatrixCursor(projection ?: DOC_PROJECTION)
        val name = documentId.substringAfterLast('/').ifEmpty { "Racine" }
        cursor.newRow()
            .add(Document.COLUMN_DOCUMENT_ID, documentId)
            .add(Document.COLUMN_DISPLAY_NAME, name)
            .add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
            .add(Document.COLUMN_FLAGS, Document.FLAG_DIR_SUPPORTS_CREATE)
            .add(Document.COLUMN_SIZE, 0)
        return cursor
    }

    override fun createDocument(parentDocumentId: String,
            mimeType: String, displayName: String): String {
        val (type, id, parentPath) = parseDocId(parentDocumentId)!!
        val base = parentPath.trimEnd('/')
        return "$type:$id:$base/$displayName"
    }

    // ── Lire / écrire ──────────────────────────────────────────────────────────

    override fun openDocument(documentId: String, mode: String,
            signal: CancellationSignal?): ParcelFileDescriptor {
        val (type, id, path) = parseDocId(documentId)!!
        val isWrite = mode.contains("w")
        val (readFd, writeFd) = ParcelFileDescriptor.createPipe()
        if (isWrite) {
            Thread {
                try {
                    val tmp = File.createTempFile("pulseit_up", null, context?.cacheDir)
                    ParcelFileDescriptor.AutoCloseInputStream(readFd).use { tmp.outputStream().use { o -> it.copyTo(o) } }
                    when (type) { "ftp" -> uploadFtp(id, tmp, path); "http" -> uploadHttp(id, tmp, path) }
                    tmp.delete()
                } catch (e: Exception) { Log.e(TAG, "upload: ${e.message}") }
            }.start()
            return writeFd
        } else {
            Thread {
                try {
                    ParcelFileDescriptor.AutoCloseOutputStream(writeFd).use { out ->
                        when (type) { "ftp" -> downloadFtp(id, path, out); "http" -> downloadHttp(id, path, out) }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "download: ${e.message}")
                    try { writeFd.closeWithError(e.message) } catch (_: Exception) {}
                }
            }.start()
            return readFd
        }
    }

    // ── FTP via Socket ─────────────────────────────────────────────────────────

    private data class FtpConfig(val host: String, val port: Int, val user: String, val pass: String)

    private fun getFtpConfig(id: Int): FtpConfig? {
        val ctx = context ?: return null
        return try {
            val db = ctx.getDatabasePath("pulseit.db")
            if (!db.exists()) return null
            val d = android.database.sqlite.SQLiteDatabase.openDatabase(
                db.absolutePath, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
            val c = d.rawQuery("SELECT host,port,user FROM ftp_connections WHERE id=?", arrayOf(id.toString()))
            if (!c.moveToFirst()) { c.close(); d.close(); return null }
            val host = c.getString(0); val port = c.getInt(1); val user = c.getString(2)
            c.close(); d.close()
            val pass = readFtpMirror()?.optString(id.toString(), "") ?: ""
            FtpConfig(host, port, user, pass)
        } catch (_: Exception) { null }
    }

    private fun readFtpMirror(): org.json.JSONObject? {
        val ctx = context ?: return null
        return try {
            val file = File(ctx.filesDir, "pulsefile_ftp_mirror.json")
            if (!file.exists()) return null
            val decrypted = SecureMirror.decrypt(file.readBytes()) ?: return null
            org.json.JSONObject(decrypted)
        } catch (e: Exception) { Log.e(TAG, "FTP mirror read: ${e.message}"); null }
    }

    private inner class FtpSession(cfg: FtpConfig) {
        private val ctrl   = Socket().apply { connect(InetSocketAddress(cfg.host, cfg.port), 10_000); soTimeout = 15_000 }
        private val reader = ctrl.getInputStream().bufferedReader(Charsets.UTF_8)
        private val writer = PrintWriter(ctrl.getOutputStream().writer(Charsets.UTF_8), true)

        init {
            expect(220); cmd("USER ${cfg.user}")
            val r = read(); if (r.first == 331) { cmd("PASS ${cfg.pass}"); expect(230) }
            cmd("TYPE I"); read()
        }

        fun close() { try { cmd("QUIT"); ctrl.close() } catch (_: Exception) {} }
        fun cmd(s: String) = writer.println(s)

        fun read(): Pair<Int, String> {
            val sb = StringBuilder(); var code = -1
            while (true) {
                val line = reader.readLine() ?: break
                if (code < 0) code = line.take(3).toIntOrNull() ?: -1
                sb.appendLine(line)
                if (line.length >= 4 && line[3] == ' ') break
            }
            return Pair(code, sb.toString())
        }

        fun expect(vararg ok: Int): String {
            val (c, m) = read(); if (c !in ok) throw IOException("FTP $c: $m"); return m
        }

        fun pasvSocket(): Socket {
            cmd("PASV"); val msg = expect(227)
            val n = Regex("\\((\\d+),(\\d+),(\\d+),(\\d+),(\\d+),(\\d+)\\)")
                .find(msg)?.groupValues ?: throw IOException("PASV error")
            val h = "${n[1]}.${n[2]}.${n[3]}.${n[4]}"
            val p = n[5].toInt() * 256 + n[6].toInt()
            return Socket(h, p).also { it.soTimeout = 60_000 }
        }

        fun list(path: String): List<String> {
            val ds = pasvSocket(); cmd("LIST $path"); expect(125, 150)
            val lines = ds.getInputStream().bufferedReader(Charsets.UTF_8).readLines()
            ds.close(); expect(226); return lines
        }

        fun download(path: String, out: OutputStream) {
            val ds = pasvSocket(); cmd("RETR $path"); expect(125, 150)
            ds.getInputStream().use { it.copyTo(out) }; ds.close(); expect(226)
        }

        fun upload(path: String, inp: InputStream) {
            val ds = pasvSocket(); cmd("STOR $path"); expect(125, 150)
            inp.use { it.copyTo(ds.getOutputStream()) }; ds.close(); expect(226)
        }
    }

    private fun listFtp(id: Int, path: String, cursor: MatrixCursor) {
        val cfg = getFtpConfig(id) ?: return
        val ftp = FtpSession(cfg)
        try {
            for (line in ftp.list(path)) {
                val parts = line.trim().split(Regex("\\s+"), 9)
                if (parts.size < 9) continue
                val isDir = parts[0].startsWith("d")
                val name  = parts[8].trim()
                if (name == "." || name == "..") continue
                val docId = "ftp:$id:${path.trimEnd('/')}/$name"
                cursor.newRow()
                    .add(Document.COLUMN_DOCUMENT_ID, docId)
                    .add(Document.COLUMN_DISPLAY_NAME, name)
                    .add(Document.COLUMN_MIME_TYPE, if (isDir) Document.MIME_TYPE_DIR else mime(name))
                    .add(Document.COLUMN_SIZE, parts[4].toLongOrNull() ?: 0L)
                    .add(Document.COLUMN_FLAGS,
                        if (isDir) Document.FLAG_DIR_SUPPORTS_CREATE
                        else Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE)
            }
        } finally { ftp.close() }
    }

    private fun downloadFtp(id: Int, path: String, out: OutputStream) {
        val cfg = getFtpConfig(id) ?: throw IOException("Config FTP introuvable")
        val ftp = FtpSession(cfg)
        try { ftp.download(path, out) } finally { ftp.close() }
    }

    private fun uploadFtp(id: Int, file: File, path: String) {
        val cfg = getFtpConfig(id) ?: throw IOException("Config FTP introuvable")
        val ftp = FtpSession(cfg)
        try { ftp.upload(path, FileInputStream(file)) } finally { ftp.close() }
    }

    // ── HTTP ───────────────────────────────────────────────────────────────────

    // ── Miroir chiffré des connexions HTTP (voir SafMirrorService + SecureMirror) ──
    // flutter_secure_storage chiffre les valeurs sur Android avec un format
    // interne propre à la librairie (non documenté, sujet à changement) : on
    // évite de le reproduire ici. On lit à la place ce fichier JSON, chiffré
    // avec une clé Android Keystore liée à l'état "appareil déverrouillé"
    // (SecureMirror.kt), régénéré par Dart à chaque création/modification/
    // suppression d'une connexion HTTP.
    private fun readHttpMirror(): org.json.JSONArray? {
        val ctx = context ?: return null
        return try {
            val file = File(ctx.filesDir, "pulsefile_http_mirror.json")
            if (!file.exists()) return null
            val decrypted = SecureMirror.decrypt(file.readBytes()) ?: return null
            org.json.JSONArray(decrypted)
        } catch (e: Exception) { Log.e(TAG, "HTTP mirror read: ${e.message}"); null }
    }

    private fun getHttpConfig(id: Int): Map<String,String>? {
        return try {
            val arr = readHttpMirror() ?: return null
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optInt("id", -1) == id) {
                    val url = o.optString("url"); if (url.isEmpty()) return null
                    return mapOf(
                        "url" to url,
                        "token" to o.optString("token", ""),
                        "user" to o.optString("basicUser", ""),
                        "pass" to o.optString("basicPassword", ""))
                }
            }
            null
        } catch (_: Exception) { null }
    }

    private fun httpUrl(cfg: Map<String,String>, action: String, subdir: String, file: String? = null): String {
        var url = "${cfg["url"]}?action=$action&dir=$subdir"
        if (file != null) url += "&file=$file"
        val token = cfg["token"] ?: ""
        if (token.isNotEmpty()) {
            val ts  = (System.currentTimeMillis() / 1000).toString()
            val mac = javax.crypto.Mac.getInstance("HmacSHA256").apply {
                init(javax.crypto.spec.SecretKeySpec(token.toByteArray(), "HmacSHA256")) }
            val sig = mac.doFinal(ts.toByteArray()).joinToString("") { "%02x".format(it) }
            url += "&_ts=$ts&_sig=$sig"
        }
        return url
    }

    private fun openHttp(url: String, cfg: Map<String,String>): HttpURLConnection {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 30_000; conn.readTimeout = 60_000
        val u = cfg["user"] ?: ""; val p = cfg["pass"] ?: ""
        if (u.isNotEmpty()) conn.setRequestProperty("Authorization",
            "Basic ${Base64.encodeToString("$u:$p".toByteArray(), Base64.NO_WRAP)}")
        return conn
    }

    private fun listHttp(id: Int, subdir: String, cursor: MatrixCursor) {
        val cfg = getHttpConfig(id) ?: return
        val conn = openHttp(httpUrl(cfg, "list", subdir), cfg)
        try {
            val body = conn.inputStream.bufferedReader().readText()
            val json = org.json.JSONObject(body)
            val files = json.optJSONArray("files") ?: return
            for (i in 0 until files.length()) {
                val f     = files.getJSONObject(i)
                val name  = f.optString("name"); if (name.isEmpty()) continue
                val size  = f.optLong("size", 0L)
                val isDir = f.optBoolean("isDir") || f.optString("type") == "dir"
                val sub   = if (subdir == ".") "" else subdir.trimEnd('/')
                val docId = "http:$id:$sub/$name"
                cursor.newRow()
                    .add(Document.COLUMN_DOCUMENT_ID, docId)
                    .add(Document.COLUMN_DISPLAY_NAME, name)
                    .add(Document.COLUMN_MIME_TYPE, if (isDir) Document.MIME_TYPE_DIR else mime(name))
                    .add(Document.COLUMN_SIZE, size)
                    .add(Document.COLUMN_FLAGS,
                        if (isDir) Document.FLAG_DIR_SUPPORTS_CREATE
                        else Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE)
            }
        } finally { conn.disconnect() }
    }

    private fun downloadHttp(id: Int, path: String, out: OutputStream) {
        val cfg  = getHttpConfig(id) ?: throw IOException("Config HTTP introuvable")
        val name = path.substringAfterLast('/')
        val sub  = path.substringBeforeLast('/').trimStart('/', '.')
        val conn = openHttp(httpUrl(cfg, "download", sub.ifEmpty { "." }, name), cfg)
        try { conn.inputStream.use { it.copyTo(out) } } finally { conn.disconnect() }
    }

    private fun uploadHttp(id: Int, file: File, path: String) {
        val cfg  = getHttpConfig(id) ?: throw IOException("Config HTTP introuvable")
        val name = path.substringAfterLast('/')
        val sub  = path.substringBeforeLast('/').trimStart('/', '.')
        val url  = httpUrl(cfg, "upload", sub.ifEmpty { "." }, name)
        val boundary = "---PulseIt${System.currentTimeMillis()}"
        val conn = URL(url).openConnection() as HttpURLConnection
        openHttp(url, cfg)
        conn.requestMethod = "POST"; conn.doOutput = true
        conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        conn.outputStream.use { os ->
            val pw = PrintWriter(OutputStreamWriter(os, Charsets.UTF_8), true)
            pw.append("--$boundary\r\n")
            pw.append("Content-Disposition: form-data; name=\"file\"; filename=\"$name\"\r\n")
            pw.append("Content-Type: application/octet-stream\r\n\r\n"); pw.flush()
            file.inputStream().use { it.copyTo(os) }
            pw.append("\r\n--$boundary--\r\n"); pw.flush()
        }
        if (conn.responseCode != 200) throw IOException("HTTP ${conn.responseCode}")
        conn.disconnect()
    }

    // ── Utils ──────────────────────────────────────────────────────────────────

    private fun parseDocId(id: String): Triple<String,Int,String>? {
        val a = id.indexOf(':'); val b = id.indexOf(':', a + 1)
        if (a < 0 || b < 0) return null
        val type = id.substring(0, a)
        val num  = id.substring(a + 1, b).toIntOrNull() ?: return null
        return Triple(type, num, id.substring(b + 1))
    }

    private fun mime(name: String) =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(
            name.substringAfterLast('.').lowercase()) ?: "application/octet-stream"
}
