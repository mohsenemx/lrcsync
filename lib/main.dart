import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/now_playing/data/services/native_media_service.dart';
import 'features/now_playing/presentation/controllers/now_playing_controller.dart';
import 'features/now_playing/presentation/screens/now_playing_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final mediaService = NativeMediaService();
  final controller = NowPlayingController(mediaService);

  runApp(LRCSyncApp(controller: controller));
}

class LRCSyncApp extends StatelessWidget {
  final NowPlayingController controller;

  const LRCSyncApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'LRCSync',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildTheme(lightDynamic, Brightness.light),
          darkTheme: AppTheme.buildTheme(darkDynamic, Brightness.dark),
          themeMode: ThemeMode.system,
          home: NowPlayingScreen(controller: controller),
        );
      },
    );
  }
}
