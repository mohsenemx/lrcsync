import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../../now_playing/presentation/controllers/now_playing_controller.dart';

const String kLrcSyncOverlayCmdPort = 'lrcsync_overlay_cmd_port';
const String kLrcSyncOverlayStatePort = 'lrcsync_overlay_state_port';

class LyricsOverlayBridge extends ChangeNotifier {
  static const _methodChannel = MethodChannel('lrcsync/media_methods');

  final NowPlayingController nowPlayingController;
  final AppSettingsController settingsController;

  ReceivePort? _cmdReceivePort;
  StreamSubscription<dynamic>? _cmdSub;
  StreamSubscription<dynamic>? _overlaySub;
  bool _isOverlayActive = false;
  String? _lastAutoFetchedTrackKey;
  int _lastHandledReqId = -1;

  LyricsOverlayBridge({
    required this.nowPlayingController,
    required this.settingsController,
  }) {
    nowPlayingController.addListener(_onAppStateChanged);
    settingsController.addListener(_onAppStateChanged);
    _listenToOverlayCommands();
    _syncInitialActiveState();
  }

  bool get isOverlayActive => _isOverlayActive;

  Future<void> _syncInitialActiveState() async {
    try {
      final active = await FlutterOverlayWindow.isActive();
      final hasLivePort =
          ui.IsolateNameServer.lookupPortByName(kLrcSyncOverlayStatePort) !=
          null;

      if (active && !hasLivePort) {
        await _forceCleanOverlayService();
        _isOverlayActive = false;
      } else {
        _isOverlayActive = active;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> toggleOverlay() async {
    final hasLivePort =
        ui.IsolateNameServer.lookupPortByName(kLrcSyncOverlayStatePort) != null;
    if (_isOverlayActive && hasLivePort) {
      await closeOverlay();
      return false;
    }
    return await openOverlay();
  }

  Future<void> _forceCleanOverlayService() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
    try {
      await _methodChannel.invokeMethod('forceStopOverlayService');
    } catch (_) {}
    ui.IsolateNameServer.removePortNameMapping(kLrcSyncOverlayStatePort);
  }

  Future<void> _attachNativeOverlayEngine() async {
    try {
      await _methodChannel.invokeMethod('attachOverlayEngine');
    } catch (_) {}
  }

  void _listenToOverlayCommands() {
    _cmdSub?.cancel();
    _overlaySub?.cancel();
    _cmdReceivePort?.close();
    ui.IsolateNameServer.removePortNameMapping(kLrcSyncOverlayCmdPort);

    _cmdReceivePort = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _cmdReceivePort!.sendPort,
      kLrcSyncOverlayCmdPort,
    );

    _cmdSub = _cmdReceivePort!.listen(_handleIncomingCommand);
    _overlaySub = FlutterOverlayWindow.overlayListener.listen(
      _handleIncomingCommand,
    );
  }

  Future<void> _handleIncomingCommand(dynamic event) async {
    if (event is! String) return;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'cmd') {
        return;
      }

      final reqId = decoded['reqId'] as int?;
      if (reqId != null) {
        if (reqId == _lastHandledReqId) return;
        _lastHandledReqId = reqId;
      }

      switch (decoded['action']) {
        case 'ready':
          _isOverlayActive = true;
          notifyListeners();
          await _attachNativeOverlayEngine();
          _pushStateToOverlay();
          break;
        case 'toggle_play_pause':
          await nowPlayingController.togglePlayPause();
          break;
        case 'save_overlay_size':
          final fullWidth =
              (decoded['fullWidth'] as bool?) ??
              settingsController.overlayFullWidth;
          final widthDp =
              (decoded['widthDp'] as num?)?.toDouble() ??
              settingsController.overlayWidthDp;
          final heightDp =
              (decoded['heightDp'] as num?)?.toDouble() ??
              settingsController.overlayHeightDp;
          settingsController.persistOverlaySizeFromWindow(
            fullWidth: fullWidth,
            widthDp: widthDp,
            heightDp: heightDp,
          );
          break;
        case 'ping':
          final pong = jsonEncode({'type': 'pong'});
          final statePort = ui.IsolateNameServer.lookupPortByName(
            kLrcSyncOverlayStatePort,
          );
          if (statePort != null) {
            statePort.send(pong);
          } else {
            FlutterOverlayWindow.shareData(pong);
          }
          break;
        case 'close':
          await closeOverlay();
          break;
      }
    } catch (_) {}
  }

  Future<bool> openOverlay() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      final result = await FlutterOverlayWindow.requestPermission();
      if (result != true) return false;
    }
    if (await FlutterOverlayWindow.isActive()) {
      await _forceCleanOverlayService();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final widthPx = settingsController.overlayFullWidth
        ? WindowSize.matchParent
        : (settingsController.overlayWidthDp * dpr).round();
    final heightPx = (settingsController.overlayHeightDp * dpr).round();

    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      dismissConfig: const OverlayDismissConfig(),
      overlayTitle: 'LRCSync Live Lyrics',
      overlayContent: nowPlayingController.currentTrack != null
          ? '${nowPlayingController.currentTrack!.title} • ${nowPlayingController.currentTrack!.artist}'
          : 'Floating lyrics active',
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
      positionGravity: PositionGravity.none,
      width: widthPx,
      height: heightPx,
      alignment: OverlayAlignment.topCenter,
    );

    _isOverlayActive = true;
    notifyListeners();

    // Attach MediaSessionHub to the overlay engine once it initializes
    Future.delayed(const Duration(milliseconds: 180), () async {
      if (_isOverlayActive) {
        await _attachNativeOverlayEngine();
        _pushStateToOverlay();
      }
    });
    Future.delayed(const Duration(milliseconds: 550), () async {
      if (_isOverlayActive) {
        await _attachNativeOverlayEngine();
        _pushStateToOverlay();
      }
    });

    return true;
  }

  Future<void> closeOverlay() async {
    await _forceCleanOverlayService();
    _isOverlayActive = false;
    notifyListeners();
  }

  void _onAppStateChanged() {
    final overlayPort = ui.IsolateNameServer.lookupPortByName(
      kLrcSyncOverlayStatePort,
    );
    if (!_isOverlayActive && overlayPort == null) return;

    final track = nowPlayingController.currentTrack;
    if (track != null) {
      final trackKey = '${track.title}_${track.artist}';
      if (_lastAutoFetchedTrackKey != trackKey &&
          nowPlayingController.lyricsResult == null &&
          !nowPlayingController.isFetchingLyrics) {
        _lastAutoFetchedTrackKey = trackKey;
        nowPlayingController.fetchLyrics(settingsController);
      }
    }

    _pushStateToOverlay();
  }

  void _pushStateToOverlay() {
    try {
      final track = nowPlayingController.currentTrack;
      final lyrics = nowPlayingController.lyricsResult;

      final encoded = jsonEncode({
        'type': 'state',
        'isFetching': nowPlayingController.isFetchingLyrics,
        'track': track == null
            ? null
            : {
                'title': track.title,
                'artist': track.artist,
                'sourceAppName': track.sourceAppName,
                'durationMs': track.duration.inMilliseconds,
                'positionMs': track.positionMs,
                'isPlaying': track.isPlaying,
                'playbackSpeed': track.playbackSpeed,
                'timestampEpochMs': track.timestampEpochMs,
              },
        'rawLrc': lyrics?.content,
        'settings': {
          'themeMode': settingsController.themeMode.name,
          'useDynamicColor': settingsController.useDynamicColor,
          'amoledDark': settingsController.amoledDark,
          'seedColor': settingsController.seedColor.toARGB32(),
          'appFont': settingsController.appFont.name,
          'lyricsFontSize': settingsController.lyricsFontSize,
          'blurInactiveLyrics': settingsController.blurInactiveLyrics,
          'overlayShape': settingsController.overlayShape.name,
          'overlayBackgroundStyle':
              settingsController.overlayBackgroundStyle.name,
          'overlayCustomColor': settingsController.overlayCustomColor
              .toARGB32(),
          'overlayOpacity': settingsController.overlayOpacity,
          'overlayShowBorder': settingsController.overlayShowBorder,
          'overlayFullWidth': settingsController.overlayFullWidth,
          'overlayWidthDp': settingsController.overlayWidthDp,
          'overlayHeightDp': settingsController.overlayHeightDp,
          'overlaySizeRevision': settingsController.overlaySizeRevision,
        },
      });

      final statePort = ui.IsolateNameServer.lookupPortByName(
        kLrcSyncOverlayStatePort,
      );
      if (statePort != null) {
        statePort.send(encoded);
      } else {
        FlutterOverlayWindow.shareData(encoded);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    nowPlayingController.removeListener(_onAppStateChanged);
    settingsController.removeListener(_onAppStateChanged);
    _cmdSub?.cancel();
    _overlaySub?.cancel();
    _cmdReceivePort?.close();
    ui.IsolateNameServer.removePortNameMapping(kLrcSyncOverlayCmdPort);
    super.dispose();
  }
}
