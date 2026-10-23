package com.github.lrcsync

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "lrcsync/media_methods"
    private val EVENT_CHANNEL = "lrcsync/media_events"
    private val AUDIO_PERM_CODE = 1001

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
            sendMetadataToFlutter(metadata, activeController?.packageName)
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

                "saveLrcFile" -> {
                    val targetPath = call.argument<String>("targetPath")
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    handleSaveLrcFile(targetPath, title, artist, content, result)
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

    private fun handleSaveLrcFile(
        targetPath: String?,
        title: String,
        artist: String,
        content: String,
        result: MethodChannel.Result
    ) {
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

        // Resolve target .lrc path if it wasn't populated when track first loaded
        var resolvedLrcPath = targetPath
        if (resolvedLrcPath.isNullOrBlank()) {
            val audioPath = resolveLocalFilePath(title, artist)
            if (!audioPath.isNullOrBlank()) {
                val dotIndex = audioPath.lastIndexOf('.')
                resolvedLrcPath = if (dotIndex != -1) {
                    "${audioPath.substring(0, dotIndex)}.lrc"
                } else {
                    "$audioPath.lrc"
                }
            }
        }

        if (resolvedLrcPath.isNullOrBlank()) {
            result.success(
                mapOf(
                    "success" to false,
                    "error" to "Local audio file not found on device storage."
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
        sendMetadataToFlutter(activeController?.metadata, activeController?.packageName)
    }

    private fun sendMetadataToFlutter(metadata: MediaMetadata?, playerPackage: String?) {
        if (metadata == null) {
            eventSink?.success(null)
            return
        }

        val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
        val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
        val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)

        val filePath = if (hasReadAudioPermission()) resolveLocalFilePath(title, artist) else null

        val data = mapOf(
            "title" to title,
            "artist" to artist,
            "album" to album,
            "durationMs" to duration,
            "filePath" to filePath,
            "playerPackage" to playerPackage
        )
        eventSink?.success(data)
    }

    private fun resolveLocalFilePath(title: String, artist: String): String? {
        if (title.isBlank()) return null
        try {
            val projection = arrayOf(MediaStore.Audio.Media.DATA)

            // 1. Case-insensitive Title + Artist match
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "LOWER(${MediaStore.Audio.Media.TITLE}) = LOWER(?) AND LOWER(${MediaStore.Audio.Media.ARTIST}) = LOWER(?)",
                arrayOf(title.trim(), artist.trim()),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    return cursor.getString(dataIndex)
                }
            }

            // 2. Case-insensitive Title match
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "LOWER(${MediaStore.Audio.Media.TITLE}) = LOWER(?)",
                arrayOf(title.trim()),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    return cursor.getString(dataIndex)
                }
            }

            // 3. Fallback: Display Name (filename) contains Title
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "LOWER(${MediaStore.Audio.Media.DISPLAY_NAME}) LIKE LOWER(?)",
                arrayOf("%${title.trim()}%"),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    return cursor.getString(dataIndex)
                }
            }
        } catch (_: Exception) {
        }
        return null
    }
}
