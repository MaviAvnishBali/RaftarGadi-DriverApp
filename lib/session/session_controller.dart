import 'dart:convert';

import 'package:core/core.dart';
import 'package:driver_app/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repositories/repositories.dart';
import 'package:shared_models/shared_models.dart';
import 'package:storage/storage.dart';

/// Where the driver is in the onboarding / authorization lifecycle.
enum OnboardingStage {
  unknown,
  unauthenticated,
  needsLicense,
  needsVehicle,
  completed,
}

/// Where the app is in the auth lifecycle.
enum SessionStatus { unknown, authenticated, unauthenticated }

/// Immutable snapshot of the current session.
class SessionState {
  const SessionState({
    required this.status,
    this.user,
    this.stage = OnboardingStage.unknown,
    this.driverProfile,
  });

  const SessionState.unknown()
      : status = SessionStatus.unknown,
        user = null,
        stage = OnboardingStage.unknown,
        driverProfile = null;

  final SessionStatus status;
  final AppUser? user;
  final OnboardingStage stage;
  final Map<String, dynamic>? driverProfile;

  bool get isAuthenticated => status == SessionStatus.authenticated;
  bool get isOnboardingCompleted => stage == OnboardingStage.completed;

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
    OnboardingStage? stage,
    Map<String, dynamic>? driverProfile,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      stage: stage ?? this.stage,
      driverProfile: driverProfile ?? this.driverProfile,
    );
  }
}

/// Owns the session: restores it from local storage at startup, verifies with backend,
/// determines onboarding stage, and manages token persistence.
class SessionController extends Notifier<SessionState> {
  static const _userKey = 'session_user';
  static const _tokenKey = 'session_token';
  static const _refreshKey = 'session_refresh_token';

  KeyValueStore get _store => ref.read(cacheStoreProvider);

  @override
  SessionState build() {
    // Listen for 401 errors from the API client to auto-sign-out
    final api = ref.read(apiClientProvider);
    api.setOnUnauthorized(() {
      signOut();
    });
    api.setOnTokensRefreshed((accessToken, refreshToken) async {
      await _store.write(_tokenKey, accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _store.write(_refreshKey, refreshToken);
      }
    });
    return const SessionState.unknown();
  }

  /// Restores a persisted session, if any, and queries the backend to determine onboarding progress.
  Future<void> bootstrap() async {
    final raw = _store.read<String>(_userKey);
    final token = _store.read<String>(_tokenKey);
    final refreshToken = _store.read<String>(_refreshKey);

    if (token != null && token.isNotEmpty) {
      ref.read(apiClientProvider).setAuthToken(token);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      ref.read(apiClientProvider).setRefreshToken(refreshToken);
    }

    if (raw == null || token == null || token.isEmpty) {
      state = const SessionState(
        status: SessionStatus.unauthenticated,
        stage: OnboardingStage.unauthenticated,
      );
      return;
    }

    AppUser user;
    try {
      user = AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await signOut();
      return;
    }

    // Verify session and fetch driver profile to check onboarding completion
    final profileResult = await ref.read(driverRepositoryProvider).getProfile();

    await profileResult.match(
      (failure) async {
        // If 401 / unauthorized and we have a refresh token, try refreshing
        if (failure.message.contains('401') || failure.message.contains('Unauthorized')) {
          if (refreshToken != null && refreshToken.isNotEmpty) {
            final refreshed = await ref.read(authRepositoryProvider).refreshSession(refreshToken);
            final refreshSuccess = await refreshed.match(
              (refreshFail) async => false,
              (newToken) async {
                await _store.write(_tokenKey, newToken);
                final newRefreshToken = ref.read(apiClientProvider).refreshToken;
                if (newRefreshToken != null) {
                  await _store.write(_refreshKey, newRefreshToken);
                }
                return true;
              },
            );

            if (refreshSuccess) {
              // Retry getting profile with the refreshed token
              final retryProfile = await ref.read(driverRepositoryProvider).getProfile();
              retryProfile.match(
                (_) => signOut(),
                (driverData) {
                  _applyDriverProfile(user, driverData);
                },
              );
              return;
            }
          }
          await signOut();
          return;
        }

        // On network/server failure during offline, assume completed if previously onboarded
        state = SessionState(
          status: SessionStatus.authenticated,
          user: user,
          stage: OnboardingStage.completed,
        );
      },
      (driverData) {
        _applyDriverProfile(user, driverData);
      },
    );
  }

  void _applyDriverProfile(AppUser user, Map<String, dynamic> driverData) {
    final license = driverData['licenseNumber'] as String?;
    final vehicle = driverData['vehicle'];

    OnboardingStage stage;
    if (license == null || license.trim().isEmpty) {
      stage = OnboardingStage.needsLicense;
    } else if (vehicle == null) {
      stage = OnboardingStage.needsVehicle;
    } else {
      stage = OnboardingStage.completed;
    }

    state = SessionState(
      status: SessionStatus.authenticated,
      user: user,
      stage: stage,
      driverProfile: driverData,
    );
  }

  Future<void> signIn(AppUser user) async {
    await _store.write(_userKey, jsonEncode(user.toJson()));
    final token = ref.read(apiClientProvider).authToken;
    final refreshToken = ref.read(apiClientProvider).refreshToken;

    if (token != null && token.isNotEmpty) {
      await _store.write(_tokenKey, token);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _store.write(_refreshKey, refreshToken);
    }

    // Determine onboarding stage right after sign-in
    final profileResult = await ref.read(driverRepositoryProvider).getProfile();
    profileResult.match(
      (failure) {
        state = SessionState(
          status: SessionStatus.authenticated,
          user: user,
          stage: OnboardingStage.needsLicense,
        );
      },
      (driverData) {
        _applyDriverProfile(user, driverData);
      },
    );
  }

  void onLicenseCompleted() {
    state = state.copyWith(stage: OnboardingStage.needsVehicle);
  }

  void onVehicleCompleted() {
    state = state.copyWith(stage: OnboardingStage.completed);
  }

  Future<void> syncProfile() async {
    final result = await ref.read(driverRepositoryProvider).getProfile();
    result.match(
      (failure) => null,
      (driverData) {
        if (state.user != null) {
          _applyDriverProfile(state.user!, driverData);
        }
      },
    );
  }

  Future<void> signOut() async {
    // 1. Notify backend driver is going offline before wiping auth token
    try {
      await ref.read(driverRepositoryProvider).goOffline();
    } catch (_) {}

    // 2. Shut down socket and stop location tracking
    try {
      ref.read(socketServiceProvider).setDriverOffline();
      ref.read(socketServiceProvider).disconnect();
    } catch (_) {}
    try {
      ref.read(locationServiceProvider).stopTracking();
    } catch (_) {}

    // 3. Clear stored session and auth tokens
    await _store.delete(_userKey);
    await _store.delete(_tokenKey);
    await _store.delete(_refreshKey);
    ref.read(apiClientProvider).setAuthToken(null);
    ref.read(apiClientProvider).setRefreshToken(null);
    state = const SessionState(
      status: SessionStatus.unauthenticated,
      stage: OnboardingStage.unauthenticated,
    );
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
