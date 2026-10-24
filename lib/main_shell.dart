import 'package:flutter/material.dart';

import 'core/settings/app_settings_controller.dart';
import 'core/widgets/floating_nav_bar.dart';
import 'features/library/presentation/controllers/library_controller.dart';
import 'features/library/presentation/screens/library_screen.dart';
import 'features/live_lyrics/presentation/screens/live_lyrics_screen.dart';
import 'features/now_playing/presentation/controllers/now_playing_controller.dart';
import 'features/now_playing/presentation/screens/now_playing_screen.dart';
import 'features/now_playing/presentation/widgets/permissions_modal.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

class MainShell extends StatefulWidget {
  final NowPlayingController nowPlayingController;
  final LibraryController libraryController;
  final AppSettingsController settingsController;

  const MainShell({
    super.key,
    required this.nowPlayingController,
    required this.libraryController,
    required this.settingsController,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAndShowPermissionsModal();
  }

  Future<void> _initAndShowPermissionsModal() async {
    await widget.nowPlayingController.initialize();
    if (!mounted) return;

    if (!widget.nowPlayingController.hasShownInitialModal &&
        !widget.nowPlayingController.hasAllPermissions) {
      widget.nowPlayingController.markInitialModalShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          PermissionsModal.showIfNeeded(context, widget.nowPlayingController);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.nowPlayingController.checkPermissions();
      widget.libraryController.loadTracks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeIndex = _selectedIndex.clamp(0, 3);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: safeIndex,
        children: [
          NowPlayingScreen(
            controller: widget.nowPlayingController,
            settings: widget.settingsController,
          ),
          LiveLyricsScreen(
            controller: widget.nowPlayingController,
            settings: widget.settingsController,
          ),
          LibraryScreen(
            controller: widget.libraryController,
            settings: widget.settingsController,
            lyricsService: widget.nowPlayingController.lyricsService,
          ),
          SettingsScreen(
            settings: widget.settingsController,
            nowPlayingController: widget.nowPlayingController,
          ),
        ],
      ),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: safeIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}
