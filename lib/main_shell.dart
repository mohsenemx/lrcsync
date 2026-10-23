import 'package:flutter/material.dart';

import 'core/settings/app_settings_controller.dart';
import 'core/widgets/floating_nav_bar.dart';
import 'features/now_playing/presentation/controllers/now_playing_controller.dart';
import 'features/now_playing/presentation/screens/now_playing_screen.dart';
import 'features/now_playing/presentation/widgets/permissions_modal.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

class MainShell extends StatefulWidget {
  final NowPlayingController nowPlayingController;
  final AppSettingsController settingsController;

  const MainShell({
    super.key,
    required this.nowPlayingController,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Lets content scroll behind the floating navbar
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          NowPlayingScreen(
            controller: widget.nowPlayingController,
            settings: widget.settingsController,
          ),
          SettingsScreen(
            settings: widget.settingsController,
            nowPlayingController: widget.nowPlayingController,
          ),
        ],
      ),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}
