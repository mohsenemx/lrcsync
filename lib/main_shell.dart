import 'package:flutter/material.dart';

import 'core/services/update_service.dart';
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
  late final PageController _pageController;
  int _selectedIndex = 0;
  bool _isAnimatingFromNavBar = false;
  int _navAnimationId = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addObserver(this);
    _initAndShowPermissionsModal();
  }

  Future<void> _initAndShowPermissionsModal() async {
    await widget.nowPlayingController.initialize();
    if (!mounted) return;

    if (!widget.nowPlayingController.hasShownInitialModal &&
        !widget.nowPlayingController.hasAllPermissions) {
      widget.nowPlayingController.markInitialModalShown();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          await PermissionsModal.showIfNeeded(
            context,
            widget.nowPlayingController,
          );
        }
      });
    }

    if (mounted) {
      UpdateService.checkAndShowModalIfNeeded(
        context,
        widget.nowPlayingController.mediaService,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
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

  Future<void> _onNavBarTapped(int index) async {
    if (_selectedIndex == index) return;

    final previousIndex = _selectedIndex;
    final currentAnimId = ++_navAnimationId;

    setState(() {
      _selectedIndex = index;
      _isAnimatingFromNavBar = true;
    });

    // When jumping across multiple tabs (e.g. 0 -> 3), jump to the adjacent tab
    // first so intermediate pages don't flash across the viewport.
    if ((index - previousIndex).abs() > 1) {
      final neighbor = index > previousIndex ? index - 1 : index + 1;
      _pageController.jumpToPage(neighbor);
    }

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );

    if (mounted && currentAnimId == _navAnimationId) {
      _isAnimatingFromNavBar = false;
    }
  }

  Widget _buildAnimatedPage(int index, Widget child) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, pageChild) {
        double pageOffset = 0.0;
        if (_pageController.hasClients &&
            _pageController.position.hasContentDimensions) {
          pageOffset =
              (_pageController.page ?? _selectedIndex.toDouble()) - index;
        } else {
          pageOffset = (_selectedIndex - index).toDouble();
        }

        final distance = pageOffset.abs().clamp(0.0, 1.0);
        final scale = 1.0 - (distance * 0.07);
        final opacity = 1.0 - (distance * 0.55);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: pageChild),
        );
      },
      child: _KeepAlivePage(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeIndex = _selectedIndex.clamp(0, 3);

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          if (!_isAnimatingFromNavBar && _selectedIndex != index) {
            setState(() => _selectedIndex = index);
          }
        },
        children: [
          _buildAnimatedPage(
            0,
            NowPlayingScreen(
              controller: widget.nowPlayingController,
              settings: widget.settingsController,
            ),
          ),
          _buildAnimatedPage(
            1,
            LiveLyricsScreen(
              controller: widget.nowPlayingController,
              settings: widget.settingsController,
              isActive: safeIndex == 1,
            ),
          ),
          _buildAnimatedPage(
            2,
            LibraryScreen(
              controller: widget.libraryController,
              settings: widget.settingsController,
              lyricsService: widget.nowPlayingController.lyricsService,
            ),
          ),
          _buildAnimatedPage(
            3,
            SettingsScreen(
              settings: widget.settingsController,
              nowPlayingController: widget.nowPlayingController,
            ),
          ),
        ],
      ),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: safeIndex,
        onTap: _onNavBarTapped,
      ),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
