import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/auth/phone_screen.dart';
import 'package:driver_app/features/onboarding/driver_welcome_screen.dart';
import 'package:driver_app/features/splash/splash_screen.dart';
import 'package:driver_app/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:localization/localization.dart';
import 'package:repositories/repositories.dart';

class _FakeAuthRepo extends Fake implements AuthRepository {
  @override
  Future<Result<void>> requestOtp(String phone) async => success(null);
}

class _FakeSessionController extends SessionController {
  @override
  SessionState build() => const SessionState(
        status: SessionStatus.unauthenticated,
        stage: OnboardingStage.unauthenticated,
      );

  @override
  Future<void> bootstrap() async {}
}

Widget _wrap(Widget child) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => child),
      GoRoute(path: '/welcome', builder: (context, state) => const Scaffold()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold()),
      GoRoute(path: '/login', builder: (context, state) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
      sessionControllerProvider.overrideWith(_FakeSessionController.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: RaftarTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DriverWelcomeScreen renders branding, hero illustration, and green button', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(const DriverWelcomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Be a Raftar\nDriver Partner'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.byType(RaftarDriverHeroArt), findsOneWidget);
  });

  testWidgets('Driver SplashScreen renders dark background, logo, and loading spinner', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(const SplashScreen()));
    await tester.pump();

    expect(find.byType(RaftarLogo), findsOneWidget);
    expect(find.byType(RaftarHeroTruck), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading...'), findsOneWidget);

    // Drain bootstrap timer
    await tester.pump(const Duration(milliseconds: 1600));
  });

  testWidgets('Driver PhoneScreen renders mobile number input and Send OTP button', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(const PhoneScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
