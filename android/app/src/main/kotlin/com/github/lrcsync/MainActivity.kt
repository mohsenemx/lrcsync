package com.github.lrcsync

import android.Manifest
import android.content.ComponentName
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.MediaMetadataRetriever
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "lrcsync/media_methods"
    private val EVENT_CHANNEL = "lrcsync/media_events"
    private val AUDIO_PERM_CODE = 1001

    private val ioExecutor = Executors.newFixedThreadPool(4)

    private var mediaSessionManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermResult: MethodChannel.Result? = null

    private val requiredAudioPermission: String
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private val sessionListener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
        attachToController(controllers?.firstOrNull())
    }

    private val controllerCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            sendSessionStateToFlutter()
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            sendSessionStateToFlutter()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasNotificationPermission" -> result.success(isNotificationServiceEnabled())
                "openNotificationSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }

                "hasAudioPermission" -> result.success(hasAudioAndWritePermission())
                "requestAudioPermission" -> {
                    if (!hasReadAudioPermission()) {
                        pendingPermResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(requiredAudioPermission),
                            AUDIO_PERM_CODE
                        )
                    } else if (!hasAllFilesWriteAccess()) {
                        openAllFilesAccessSettings()
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }

                "refreshTrack" -> {
                    startListening()
                    result.success(null)
                }

                "getDeviceTracks" -> {
                    ioExecutor.execute {
                        val tracks = queryAllDeviceTracks()
                        runOnUiThread { result.success(tracks) }
                    }
                }

                "getAlbumArt" -> {
                    val albumId = (call.argument<Number>("albumId"))?.toLong()
                    val filePath = call.argument<String>("filePath")
                    ioExecutor.execute {
                        val bytes = loadAlbumArtBytes(albumId, filePath)
                        runOnUiThread { result.success(bytes) }
                    }
                }

                "saveLrcFile" -> {
                    val targetPath = call.argument<String>("targetPath")
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val playerPackage = call.argument<String>("playerPackage")
                    val content = call.argument<String>("content") ?: ""
                    handleSaveLrcFile(targetPath, title, artist, playerPackage, content, result)
                }

                "readInternalLrc" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val playerPackage = call.argument<String>("playerPackage")
                    val content = readInternalCachedLrc(title, artist, playerPackage)
                    result.success(content)
                }

                "saveLyricsScreenshot" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName") ?: "LRCSync_${System.currentTimeMillis()}.png"
                    val share = call.argument<Boolean>("share") ?: false
                    if (bytes == null) {
                        result.success(mapOf("success" to false, "error" to "Empty image bytes"))
                    } else {
                        ioExecutor.execute {
                            val res = saveAndOptionallyShareScreenshot(bytes, fileName, share)
                            runOnUiThread { result.success(res) }
                        }
                    }
                }

                "seekTo" -> {
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    val controller = getActiveOrCurrentController()
                    controller?.transportControls?.seekTo(positionMs)
                    result.success(controller != null)
                }

                "togglePlayPause" -> {
                    val controller = getActiveOrCurrentController()
                    val state = controller?.playbackState?.state
                    if (state == PlaybackState.STATE_PLAYING) {
                        controller?.transportControls?.pause()
                    } else {
                        controller?.transportControls?.play()
                    }
                    result.success(controller != null)
                }

                "clearInternalLyricsCache" -> {
                    val dir = getInternalLyricsDir()
                    val files = dir.listFiles() ?: emptyArray()
                    var deletedCount = 0
                    for (file in files) {
                        if (file.isFile && file.delete()) {
                            deletedCount++
                        }
                    }
                    result.success(deletedCount)
                }

                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (!url.isNullOrBlank()) {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "loadSettings" -> {
                                    val prefs = getSharedPreferences("lrcsync_settings", Context.MODE_PRIVATE)
                                    result.success(prefs.getString("settings_json", null))
                                }
                                "saveSettings" -> {
                                    val json = call.argument<String>("json") ?: "{}"
                                    getSharedPreferences("lrcsync_settings", Context.MODE_PRIVATE)
                                        .edit()
                                        .putString("settings_json", json)
                                        .apply()
                                    result.success(true)
                                }

                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startListening()
                }

                override fun onCancel(arguments: Any?) {
                    stopListening()
                    eventSink = null
                }
            }
        )
    }

    // --- INTERNAL STREAMING LYRICS CACHE (Spotify, YT Music, Telegram, etc.) ---

    private fun getInternalLyricsDir(): File {
        val dir = File(filesDir, "cached_lyrics")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun sanitizeKeyPart(input: String): String {
        return input.trim().lowercase()
            .replace(Regex("[^a-z0-9\\u00a0-\\uffff]+"), "_")
            .trim('_')
            .take(64)
            .ifEmpty { "unknown" }
    }

    private fun getScopedCacheFile(title: String, artist: String, playerPackage: String?): File {
        val pkg = sanitizeKeyPart(playerPackage ?: "any")
        val art = sanitizeKeyPart(artist)
        val tit = sanitizeKeyPart(title)
        return File(getInternalLyricsDir(), "${pkg}__${art}__${tit}.lrc")
    }

    private fun getFallbackCacheFile(title: String, artist: String): File {
        val art = sanitizeKeyPart(artist)
        val tit = sanitizeKeyPart(title)
        return File(getInternalLyricsDir(), "any__${art}__${tit}.lrc")
    }

    private fun readInternalCachedLrc(title: String, artist: String, playerPackage: String?): String? {
        if (title.isBlank()) return null
        try {
            // 1. Check exact playerPackage + artist + title match first
            if (!playerPackage.isNullOrBlank()) {
                val scopedFile = getScopedCacheFile(title, artist, playerPackage)
                if (scopedFile.exists()) {
                    val text = scopedFile.readText(Charsets.UTF_8).trim()
                    if (text.isNotEmpty()) return text
                }
            }
            // 2. Check fallback artist + title match across any streaming player
            val fallbackFile = getFallbackCacheFile(title, artist)
            if (fallbackFile.exists()) {
                val text = fallbackFile.readText(Charsets.UTF_8).trim()
                if (text.isNotEmpty()) return text
            }
        } catch (_: Exception) {
        }
        return null
    }

    private fun getActiveOrCurrentController(): MediaController? {
        if (activeController != null) return activeController
        if (!isNotificationServiceEnabled()) return null
        return try {
            val componentName = ComponentName(this, MediaListenerService::class.java)
            val manager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            activeController = manager.getActiveSessions(componentName).firstOrNull()
            activeController
        } catch (_: Exception) {
            null
        }
    }

    private val wordSyncRegex = Regex("<\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?>")
    private val lineSyncRegex = Regex("\\[\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?\\]")

    private fun detectLocalLrcType(lrcFile: File): String? {
        if (!lrcFile.exists() || !lrcFile.isFile) return null
        return try {
            val content = lrcFile.readText(Charsets.UTF_8).trim()
            if (content.isEmpty()) return null
            when {
                wordSyncRegex.containsMatchIn(content) -> "eLRC"
                lineSyncRegex.containsMatchIn(content) -> "LRC"
                else -> "Plain"
            }
        } catch (_: Exception) {
            "LRC"
        }
    }

    private fun saveInternalCachedLrc(
        title: String,
        artist: String,
        playerPackage: String?,
        content: String
    ): File {
        val scopedFile = getScopedCacheFile(title, artist, playerPackage)
        scopedFile.writeText(content, Charsets.UTF_8)

        // Also write to the app-agnostic fallback key so it's available if played elsewhere
        val fallbackFile = getFallbackCacheFile(title, artist)
        if (fallbackFile.absolutePath != scopedFile.absolutePath) {
            fallbackFile.writeText(content, Charsets.UTF_8)
        }
        return scopedFile
    }

    // --- SAVE LRC (External beside audio file OR Internal app storage for Streaming/Telegram) ---

    private fun handleSaveLrcFile(
        targetPath: String?,
        title: String,
        artist: String,
        playerPackage: String?,
        content: String,
        result: MethodChannel.Result
    ) {
        var resolvedLrcPath: String? = targetPath
        if (resolvedLrcPath.isNullOrBlank() && hasReadAudioPermission()) {
            val match: Pair<String, Long>? = resolveLocalTrackMatch(title, artist)
            val audioPath: String? = match?.first
            if (!audioPath.isNullOrBlank()) {
                val dotIndex = audioPath.lastIndexOf('.')
                resolvedLrcPath = if (dotIndex != -1) {
                    "${audioPath.substring(0, dotIndex)}.lrc"
                } else {
                    "$audioPath.lrc"
                }
            }
        }

        // Case A: Song is from a streaming app (Spotify, YT Music) or Telegram internal storage
        if (resolvedLrcPath.isNullOrBlank()) {
            try {
                val savedFile = saveInternalCachedLrc(title, artist, playerPackage, content)
                result.success(
                    mapOf(
                        "success" to true,
                        "isInternal" to true,
                        "path" to savedFile.absolutePath
                    )
                )
            } catch (e: Exception) {
                result.success(
                    mapOf(
                        "success" to false,
                        "error" to "Internal storage write failed: ${e.message}"
                    )
                )
            }
            return
        }

        // Case B: Song is a local audio file on device storage
        if (!hasAllFilesWriteAccess()) {
            openAllFilesAccessSettings()
            result.success(
                mapOf(
                    "success" to false,
                    "error" to "Please enable 'All files access' so LRCSync can write .lrc files directly."
                )
            )
            return
        }

        try {
            val file = File(resolvedLrcPath)
            file.parentFile?.mkdirs()
            file.writeText(content, Charsets.UTF_8)
            result.success(
                mapOf(
                    "success" to true,
                    "isInternal" to false,
                    "path" to resolvedLrcPath
                )
            )
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "success" to false,
                    "error" to "Write failed: ${e.message}"
                )
            )
        }
    }

    // --- SAVE & SHARE SPOTIFY-STYLE LYRICS SCREENSHOT ---

    private fun saveAndOptionallyShareScreenshot(
        bytes: ByteArray,
        fileName: String,
        share: Boolean
    ): Map<String, Any?> {
        return try {
            val resolver = applicationContext.contentResolver
            val contentValues = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/LRCSync")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }

            val imageUri: Uri = resolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                contentValues
            ) ?: return mapOf("success" to false, "error" to "Could not create MediaStore entry")

            resolver.openOutputStream(imageUri)?.use { out ->
                out.write(bytes)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear()
                contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(imageUri, contentValues, null, null)
            }

            if (share) {
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, imageUri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val chooser = Intent.createChooser(shareIntent, "Share Lyrics Card").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(chooser)
            }

            mapOf(
                "success" to true,
                "path" to "Pictures/LRCSync/$fileName"
            )
        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "error" to "Failed to save screenshot: ${e.message}"
            )
        }
    }

    private fun queryAllDeviceTracks(): List<Map<String, Any?>> {
        if (!hasReadAudioPermission()) return emptyList()
        val list = mutableListOf<Map<String, Any?>>()

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

        try {
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                sortOrder
            )?.use { cursor ->
                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)

                while (cursor.moveToNext()) {
                    val filePath = cursor.getString(dataCol) ?: continue
                    val title = cursor.getString(titleCol) ?: ""
                    val artist = cursor.getString(artistCol) ?: ""
                    val album = cursor.getString(albumCol) ?: ""
                    val albumId = cursor.getLong(albumIdCol)
                    val duration = cursor.getLong(durationCol)

                    val dotIndex = filePath.lastIndexOf('.')
                    val lrcPath = if (dotIndex != -1) {
                        "${filePath.substring(0, dotIndex)}.lrc"
                    } else {
                        "$filePath.lrc"
                    }
                    val lrcFile = File(lrcPath)
                    val localLrcType = detectLocalLrcType(lrcFile)

                    list.add(
                        mapOf(
                            "title" to title,
                            "artist" to artist,
                            "album" to album,
                            "albumId" to albumId,
                            "durationMs" to duration,
                            "filePath" to filePath,
                            "hasLocalLrc" to (localLrcType != null),
                            "localLrcType" to localLrcType
                        )
                    )
                }
            }
        } catch (_: Exception) {
        }

        return list
    }

    private fun loadAlbumArtBytes(albumId: Long?, filePath: String?): ByteArray? {
        if (albumId != null && albumId > 0) {
            try {
                val uri = ContentUris.withAppendedId(
                    Uri.parse("content://media/external/audio/albumart"),
                    albumId
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val bitmap = contentResolver.loadThumbnail(uri, Size(256, 256), null)
                    return bitmapToBytes(bitmap)
                }
            } catch (_: Exception) {
            }
        }

        if (!filePath.isNullOrBlank()) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(filePath)
                val embedded = retriever.embeddedPicture
                if (embedded != null) return embedded
            } catch (_: Exception) {
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {
                }
            }
        }
        return null
    }

    private fun extractMetadataBitmapBytes(metadata: MediaMetadata): ByteArray? {
        val bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
            ?: return null
        return bitmapToBytes(bitmap)
    }

    private fun bitmapToBytes(bitmap: Bitmap): ByteArray {
        val maxSide = 256
        val ratio = minOf(
            maxSide.toFloat() / bitmap.width,
            maxSide.toFloat() / bitmap.height,
            1.0f
        )
        val width = (bitmap.width * ratio).toInt().coerceAtLeast(1)
        val height = (bitmap.height * ratio).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(bitmap, width, height, true)

        val stream = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
        return stream.toByteArray()
    }

    private fun hasReadAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            requiredAudioPermission
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasAllFilesWriteAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasAudioAndWritePermission(): Boolean {
        return hasReadAudioPermission() && hasAllFilesWriteAccess()
    }

    private fun openAllFilesAccessSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == AUDIO_PERM_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted && !hasAllFilesWriteAccess()) {
                openAllFilesAccessSettings()
            }
            pendingPermResult?.success(granted && hasAllFilesWriteAccess())
            pendingPermResult = null
            if (granted) startListening()
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(packageName)
    }

    private fun startListening() {
        if (!isNotificationServiceEnabled()) return
        try {
            val componentName = ComponentName(this, MediaListenerService::class.java)
            mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            mediaSessionManager?.removeOnActiveSessionsChangedListener(sessionListener)
            mediaSessionManager?.addOnActiveSessionsChangedListener(sessionListener, componentName)

            val controllers = mediaSessionManager?.getActiveSessions(componentName)
            attachToController(controllers?.firstOrNull())
        } catch (_: SecurityException) {
        }
    }

    private fun stopListening() {
        activeController?.unregisterCallback(controllerCallback)
        mediaSessionManager?.removeOnActiveSessionsChangedListener(sessionListener)
    }

    private fun attachToController(controller: MediaController?) {
        activeController?.unregisterCallback(controllerCallback)
        activeController = controller
        activeController?.registerCallback(controllerCallback)
        sendSessionStateToFlutter()
    }

    private fun sendSessionStateToFlutter() {
        val controller = activeController
        val metadata = controller?.metadata
        if (controller == null || metadata == null) {
            eventSink?.success(null)
            return
        }

        val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
        val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
        val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)

        val playbackState = controller.playbackState
        val isPlaying = playbackState?.state == PlaybackState.STATE_PLAYING
        val speed = if (playbackState != null && playbackState.playbackSpeed > 0f) {
            playbackState.playbackSpeed.toDouble()
        } else {
            1.0
        }

        var currentPositionMs = playbackState?.position ?: 0L
        if (isPlaying && playbackState != null && playbackState.lastPositionUpdateTime > 0L) {
            val elapsed = SystemClock.elapsedRealtime() - playbackState.lastPositionUpdateTime
            if (elapsed > 0) {
                currentPositionMs += (elapsed * speed).toLong()
            }
        }

        val localMatch: Pair<String, Long>? = if (hasReadAudioPermission()) {
            resolveLocalTrackMatch(title, artist)
        } else {
            null
        }
        val filePath = localMatch?.first
        val albumId = localMatch?.second
        val artBytes = extractMetadataBitmapBytes(metadata) ?: loadAlbumArtBytes(albumId, filePath)

        val data = mapOf(
            "title" to title,
            "artist" to artist,
            "album" to album,
            "albumId" to albumId,
            "durationMs" to duration,
            "positionMs" to currentPositionMs,
            "isPlaying" to isPlaying,
            "playbackSpeed" to speed,
            "timestampEpochMs" to System.currentTimeMillis(),
            "filePath" to filePath,
            "playerPackage" to controller.packageName,
            "artBytes" to artBytes
        )
        eventSink?.success(data)
    }

    private fun resolveLocalTrackMatch(title: String, artist: String): Pair<String, Long>? {
        if (title.isBlank()) return null
        try {
            val projection = arrayOf(
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.ALBUM_ID
            )

            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "LOWER(${MediaStore.Audio.Media.TITLE}) = LOWER(?) AND LOWER(${MediaStore.Audio.Media.ARTIST}) = LOWER(?)",
                arrayOf(title.trim(), artist.trim()),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val path = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA))
                    val albumId = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID))
                    return Pair(path, albumId)
                }
            }

            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "LOWER(${MediaStore.Audio.Media.TITLE}) = LOWER(?)",
                arrayOf(title.trim()),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val path = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA))
                    val albumId = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID))
                    return Pair(path, albumId)
                }
            }

            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "LOWER(${MediaStore.Audio.Media.DISPLAY_NAME}) LIKE LOWER(?)",
                arrayOf("%${title.trim()}%"),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val path = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA))
                    val albumId = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID))
                    return Pair(path, albumId)
                }
            }
        } catch (_: Exception) {
        }
        return null
    }
}
