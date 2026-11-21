import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/library/presentation/controllers/library_controller.dart';
import 'features/now_playing/data/services/native_media_service.dart';
import 'features/now_playing/presentation/controllers/now_playing_controller.dart';
import 'features/live_lyrics/data/services/lyrics_overlay_bridge.dart';
import 'features/live_lyrics/presentation/widgets/lyrics_overlay_widget.dart';
import 'main_shell.dart';

late String appVersion;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  appVersion = packageInfo.version;
  final mediaService = NativeMediaService();
  final nowPlayingController = NowPlayingController(mediaService);
  final libraryController = LibraryController(mediaService);
  final settingsController = AppSettingsController();

  await settingsController.loadSettings();
  final overlayBridge = LyricsOverlayBridge(
    nowPlayingController: nowPlayingController,
    settingsController: settingsController,
  );
  runApp(
    LRCSyncApp(
      nowPlayingController: nowPlayingController,
      libraryController: libraryController,
      settingsController: settingsController,
      overlayBridge: overlayBridge,
    ),
  );
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LyricsOverlayApp());
}

class LRCSyncApp extends StatelessWidget {
  final NowPlayingController nowPlayingController;
  final LibraryController libraryController;
  final AppSettingsController settingsController;
  final LyricsOverlayBridge overlayBridge;
  const LRCSyncApp({
    super.key,
    required this.nowPlayingController,
    required this.libraryController,
    required this.settingsController,
    required this.overlayBridge,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settingsController,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            return MaterialApp(
              title: 'LRCSync',
              debugShowCheckedModeBanner: false,
              themeMode: settingsController.themeMode,
              theme: AppTheme.buildTheme(
                dynamicScheme: lightDynamic,
                brightness: Brightness.light,
                settings: settingsController,
              ),
              darkTheme: AppTheme.buildTheme(
                dynamicScheme: darkDynamic,
                brightness: Brightness.dark,
                settings: settingsController,
              ),
              home: MainShell(
                nowPlayingController: nowPlayingController,
                libraryController: libraryController,
                settingsController: settingsController,
                overlayBridge: overlayBridge,
              ),
            );
          },
        );
      },
    );
  }
}
