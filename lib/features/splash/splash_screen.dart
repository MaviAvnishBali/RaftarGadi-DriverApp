import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:driver_app/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Brand splash shown while the session is restored from storage. Once
/// [SessionController.bootstrap] resolves the status, the router redirects
/// away automatically.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startBootstrap();
  }

  Future<void> _startBootstrap() async {
    try {
      await Future.wait([
        ref
            .read(sessionControllerProvider.notifier)
            .bootstrap()
            .timeout(const Duration(seconds: 2), onTimeout: () {
              ref.read(sessionControllerProvider.notifier).setUnauthenticated();
            }),
        Future<void>.delayed(const Duration(milliseconds: 1500)),
      ]);
    } catch (_) {
      ref.read(sessionControllerProvider.notifier).setUnauthenticated();
    }

    if (!mounted) return;
    final session = ref.read(sessionControllerProvider);
    if (session.isAuthenticated && session.stage == OnboardingStage.completed) {
      context.go(Routes.home);
    } else {
      context.go(Routes.welcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaftarColors.navyDark,
      body: SafeArea(
        child: SizedBox.expand(
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Centered Brand Logo & Tagline
              const RaftarLogo(
                height: 110,
                onNavyPanel: true,
                showTagline: true,
              ),
              const Spacer(flex: 2),
              // Modern Logistics Fleet Truck & Skyline Silhouette
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: RaftarSpacing.xl),
                child: RaftarHeroTruck(height: 160, isDark: true),
              ),
              const Spacer(flex: 3),
              // Green Circular Spinner matching design
              const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3.0,
                  valueColor: AlwaysStoppedAnimation(RaftarColors.green),
                ),
              ),
              const SizedBox(height: RaftarSpacing.md),
              Text(
                'Loading...',
                style: RaftarTypography.textTheme.bodySmall?.copyWith(
                  color: RaftarColors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: RaftarSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
