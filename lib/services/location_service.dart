import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LocationStatus {
  const LocationStatus({
    required this.isServiceEnabled,
    required this.permission,
  });

  final bool isServiceEnabled;
  final LocationPermission permission;

  bool get isPermissionGranted =>
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;

  bool get isGranted => isServiceEnabled && isPermissionGranted;

  bool get isPermanentlyDenied =>
      permission == LocationPermission.deniedForever;
}

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  /// Stream of location service enable/disable status changes (e.g. user toggles GPS in quick settings).
  Stream<ServiceStatus> getServiceStatusStream() =>
      Geolocator.getServiceStatusStream();

  /// Check current status of location service and permissions.
  Future<LocationStatus> checkStatus() async {
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    return LocationStatus(
      isServiceEnabled: isEnabled,
      permission: permission,
    );
  }

  /// Request permissions and check service.
  Future<LocationStatus> requestPermission() async {
    bool isEnabled = await Geolocator.isLocationServiceEnabled();
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return LocationStatus(
      isServiceEnabled: isEnabled,
      permission: permission,
    );
  }

  /// Try to fetch current GPS coordinates safely. Returns null if GPS is off or fails.
  Future<Position?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 10),
  }) async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
    } catch (e) {
      debugPrint('Error getting current GPS position: $e');
      return null;
    }
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Start streaming position updates.
  Future<void> startTracking({
    required void Function(Position position) onLocationUpdate,
    void Function(Object error)? onError,
  }) async {
    stopTracking();

    // Send immediate position upon starting tracking
    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      onLocationUpdate(initialPosition);
    } catch (e) {
      onError?.call(e);
    }

    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Raftar Gaddi is active in the background to receive orders',
          notificationTitle: 'You are Online & Ready',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      onLocationUpdate,
      onError: onError ?? (e) => debugPrint('Location stream error: $e'),
    );
  }

  /// Stop streaming position updates.
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(service.stopTracking);
  return service;
});
