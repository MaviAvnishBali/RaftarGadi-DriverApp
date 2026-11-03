import 'package:driver_app/app/router/routes.dart';
import 'package:driver_app/features/auth/otp_screen.dart';
import 'package:driver_app/features/auth/phone_screen.dart';
import 'package:driver_app/features/documents/driver_documents_screen.dart';
import 'package:driver_app/features/home/home_screen.dart';
import 'package:driver_app/features/onboarding/license_screen.dart';
import 'package:driver_app/features/onboarding/vehicle_screen.dart';
import 'package:driver_app/features/profile/driver_profile_screen.dart';
import 'package:driver_app/features/shell/driver_shell.dart';
import 'package:driver_app/features/splash/splash_screen.dart';
import 'package:driver_app/features/support/driver_chat_screen.dart';
import 'package:driver_app/features/support/driver_helpline_screen.dart';
import 'package:driver_app/features/trips/driver_trips_screen.dart';
import 'package:driver_app/features/wallet/driver_wallet_screen.dart';
import 'package:driver_app/session/session_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _rootKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..onDispose(refresh.dispose)
    ..listen(sessionControllerProvider, (_, _) => refresh.value++);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final location = state.matchedLocation;

      // 1. Still resolving storage/backend? Stay on splash.
      if (session.status == SessionStatus.unknown) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final atSplash = location == Routes.splash;
      final inLogin = location.startsWith(Routes.login);
      final inOnboarding = location == Routes.registerLicense || location == Routes.registerVehicle;

      // 2. Unauthenticated: send to login if not already in login flow
      if (session.status == SessionStatus.unauthenticated) {
        return inLogin ? null : Routes.login;
      }

      // 3. Authenticated: Route based on OnboardingStage
      switch (session.stage) {
        case OnboardingStage.needsLicense:
          return location == Routes.registerLicense ? null : Routes.registerLicense;
        case OnboardingStage.needsVehicle:
          return location == Routes.registerVehicle ? null : Routes.registerVehicle;
        case OnboardingStage.completed:
          if (atSplash || inLogin || inOnboarding) {
            return Routes.home;
          }
          return null;
        case OnboardingStage.unknown:
        case OnboardingStage.unauthenticated:
          return inLogin ? null : Routes.login;
      }
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const PhoneScreen(),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (context, state) => OtpScreen(
          phone: state.uri.queryParameters['phone'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.registerLicense,
        builder: (context, state) => const LicenseScreen(),
      ),
      GoRoute(
        path: Routes.registerVehicle,
        builder: (context, state) => const VehicleScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            DriverShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.trips,
                builder: (context, state) => const DriverTripsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.wallet,
                builder: (context, state) => const DriverWalletScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const DriverProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.documents,
        builder: (context, state) => const DriverDocumentsScreen(),
      ),
      GoRoute(
        path: Routes.helpline,
        builder: (context, state) => const DriverHelplineScreen(),
      ),
      GoRoute(
        path: Routes.supportChat,
        builder: (context, state) => DriverChatScreen(
          bookingId: state.uri.queryParameters['bookingId'],
        ),
      ),
    ],
  );
});
