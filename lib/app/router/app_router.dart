import 'package:driver_app/app/router/routes.dart';
import 'package:driver_app/features/auth/otp_screen.dart';
import 'package:driver_app/features/auth/phone_screen.dart';
import 'package:driver_app/features/onboarding/license_screen.dart';
import 'package:driver_app/features/onboarding/vehicle_screen.dart';
import 'package:driver_app/features/home/home_screen.dart';
import 'package:driver_app/features/splash/splash_screen.dart';
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
      final status = ref.read(sessionControllerProvider).status;
      final location = state.matchedLocation;

      if (status == SessionStatus.unknown) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final inAuthFlow =
          location.startsWith(Routes.login) || location == Routes.registerLicense || location == Routes.registerVehicle;
      final atSplash = location == Routes.splash;

      if (status == SessionStatus.unauthenticated) {
        return inAuthFlow ? null : Routes.login;
      }

      if (location.startsWith(Routes.login) || atSplash) {
        return Routes.registerLicense; // Redirect to license screen on successful login
      }
      return null;
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
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});
