package com.github.lrcsync

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "lrcsync/media_methods"
    private val EVENT_CHANNEL = "lrcsync/media_events"

    private var mediaSessionManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var eventSink: EventChannel.EventSink? = null

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
                "refreshTrack" -> {
                    startListening()
                    result.success(null)
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
        } catch (e: SecurityException) {
            // Permission revoked or unavailable
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
        val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION) // in ms

        val filePath = resolveLocalFilePath(title, artist)

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
            val selection = "${MediaStore.Audio.Media.TITLE} = ? AND ${MediaStore.Audio.Media.ARTIST} = ?"
            val selectionArgs = arrayOf(title, artist)

            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    return cursor.getString(dataIndex)
                }
            }

            // Fallback: search by title only if artist tag differs slightly
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "${MediaStore.Audio.Media.TITLE} = ?",
                arrayOf(title),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    return cursor.getString(dataIndex)
                }
            }
        } catch (e: Exception) {
            // Missing storage/audio permission or query failed
        }
        return null
    }
}
