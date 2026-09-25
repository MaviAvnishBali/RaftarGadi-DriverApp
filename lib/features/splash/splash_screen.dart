import 'dart:async';

import 'package:driver_app/session/session_controller.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localization/localization.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(sessionControllerProvider.notifier).bootstrap());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaftarColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RaftarLogo(height: 120, onNavyPanel: false),
            const SizedBox(height: RaftarSpacing.xxxl),
            const SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(RaftarColors.white),
              ),
            ),
            const SizedBox(height: RaftarSpacing.xl),
            Text(
              context.l10n.tagline,
              style: RaftarTypography.textTheme.bodyMedium?.copyWith(
                color: RaftarColors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
