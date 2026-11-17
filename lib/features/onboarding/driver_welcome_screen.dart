import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Driver Partner onboarding welcome screen matching Image 1 Column 2 mockup.
class DriverWelcomeScreen extends StatelessWidget {
  const DriverWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaftarColors.navyDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RaftarSpacing.xl,
            vertical: RaftarSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: RaftarSpacing.md),
              // 1. Headline Title & Subtitle matching Mockup
              Text(
                'Be a Raftar\nDriver Partner',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: RaftarColors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.sm),
              Text(
                'Deliver more. Earn more\nwith Raftar Gaddi.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: RaftarColors.white.withValues(alpha: 0.75),
                      fontSize: 15,
                      height: 1.4,
                    ),
              ),
              const Spacer(),

              // 2. Hero Driver Illustration
              const Center(
                child: RaftarDriverHeroArt(height: 250),
              ),
              const Spacer(),

              // 3. Green Action Button: Get Started
              RaftarButton(
                label: 'Get Started',
                onPressed: () => context.push(Routes.login),
              ),
              const SizedBox(height: RaftarSpacing.sm),

              // 4. Secondary Login Text Link
              Center(
                child: TextButton(
                  onPressed: () => context.push(Routes.login),
                  child: const Text(
                    'Login',
                    style: TextStyle(
                      color: RaftarColors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: RaftarSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}
