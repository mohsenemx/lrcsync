import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/library/presentation/controllers/library_controller.dart';
import 'features/now_playing/data/services/native_media_service.dart';
import 'features/now_playing/presentation/controllers/now_playing_controller.dart';
import 'main_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final mediaService = NativeMediaService();
  final nowPlayingController = NowPlayingController(mediaService);
  final libraryController = LibraryController(mediaService);
  final settingsController = AppSettingsController();

  runApp(
    LRCSyncApp(
      nowPlayingController: nowPlayingController,
      libraryController: libraryController,
      settingsController: settingsController,
    ),
  );
}

class LRCSyncApp extends StatelessWidget {
  final NowPlayingController nowPlayingController;
  final LibraryController libraryController;
  final AppSettingsController settingsController;

  const LRCSyncApp({
    super.key,
    required this.nowPlayingController,
    required this.libraryController,
    required this.settingsController,
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
              ),
            );
          },
        );
      },
    );
  }
}
