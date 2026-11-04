import 'dart:async';
import 'dart:ui' show Color;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef OrderActionCallback = void Function(String bookingId, bool accepted);

class DriverAlertService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  AudioPlayer? _audioPlayer;

  DriverAlertService({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    AudioPlayer? audioPlayer,
  })  : _notificationsPlugin =
            notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _audioPlayer = audioPlayer;

  AudioPlayer get audioPlayer => _audioPlayer ??= AudioPlayer();

  bool _isInitialized = false;
  bool _isAlertActive = false;
  String? _activeBookingId;
  Timer? _alertExpiryTimer;
  OrderActionCallback? _onActionCallback;

  static const String _channelId = 'fleet_incoming_orders';
  static const String _channelName = 'Incoming Fleet Orders';
  static const String _channelDescription =
      'High-priority popups and ringtones for new delivery orders';
  static const int _notificationId = 8801;

  bool get isAlertActive => _isAlertActive;
  String? get activeBookingId => _activeBookingId;

  /// Set the global callback for when a driver interacts with the notification
  void setActionCallback(OrderActionCallback? callback) {
    _onActionCallback = callback;
  }

  /// Initialize notification channels, permissions, and audio resources
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Android notification settings
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            notificationTapBackground,
      );

      // 2. Create the Android notification channel with custom sound & maximum importance
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        // Request notification permissions for Android 13+
        await androidImplementation.requestNotificationsPermission();

        final channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('order_alert'),
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );

        await androidImplementation.createNotificationChannel(channel);
      }

      // 3. Configure AudioPlayer for loop playback
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.setVolume(1.0);

      _isInitialized = true;
      debugPrint('[DriverAlertService] Initialized with Rapido chime & Heads-Up channel');
    } catch (e) {
      debugPrint('[DriverAlertService] Initialization error: $e');
    }
  }

  /// Trigger the full alert: Loud audio chime loop + Android Heads-Up Popup Alert
  Future<void> triggerIncomingOrderAlert({
    required Map<String, dynamic> order,
    OrderActionCallback? onAction,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final bookingId = (order['bookingId'] ?? order['id'] ?? '').toString();
    if (bookingId.isEmpty) return;

    // If an alert is already sounding for this exact booking, avoid double triggering
    if (_isAlertActive && _activeBookingId == bookingId) {
      return;
    }

    // Clean up any prior stale alert
    await stopAlert();

    _isAlertActive = true;
    _activeBookingId = bookingId;
    if (onAction != null) {
      _onActionCallback = onAction;
    }

    final fare = order['estimatedFare'] ?? order['finalFare'] ?? 180;
    final pickupRaw = order['pickup'];
    final dropRaw = order['drop'];
    final pickup = (pickupRaw is Map ? pickupRaw['address'] : order['pickupAddress'])?.toString() ?? 'Pickup Address';
    final drop = (dropRaw is Map ? dropRaw['address'] : order['dropAddress'])?.toString() ?? 'Drop Address';
    final pkg = (order['packageType'] ?? 'Commercial Goods').toString();
    final dist = order['estimatedDistanceKm'] ?? 8.5;

    // 1. Play in-app audio chime loop
    try {
      await audioPlayer.stop();
      await audioPlayer.play(AssetSource('sounds/order_alert.wav'));
    } catch (e) {
      debugPrint('[DriverAlertService] Audio player error: $e');
    }

    // 2. Trigger high-priority Heads-Up Notification with sound, vibration, and full-screen intent
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      sound: const RawResourceAndroidNotificationSound('order_alert'),
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      timeoutAfter: 32000,
      color: const Color(0xFFFF6B00), // Raftar Brand Orange
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'accept_order',
          '✅ ACCEPT',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'decline_order',
          '❌ DECLINE',
          cancelNotification: true,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    try {
      await _notificationsPlugin.show(
        id: _notificationId,
        title: '🚨 NEW FLEET ORDER • ₹$fare',
        body: '📦 $pkg ($dist km)\n📍 $pickup\n🎯 $drop',
        notificationDetails: notificationDetails,
        payload: bookingId,
      );
    } catch (e) {
      debugPrint('[DriverAlertService] Notification trigger error: $e');
    }

    // 3. Auto-expire after 30 seconds
    _alertExpiryTimer?.cancel();
    _alertExpiryTimer = Timer(const Duration(seconds: 30), () {
      debugPrint('[DriverAlertService] Incoming order alert expired after 30s');
      stopAlert();
    });
  }

  /// Instantly silence sound, stop vibration, and dismiss the alert notification
  Future<void> stopAlert() async {
    _isAlertActive = false;
    _activeBookingId = null;
    _alertExpiryTimer?.cancel();
    _alertExpiryTimer = null;

    try {
      await _audioPlayer?.stop();
    } catch (_) {}

    try {
      await _notificationsPlugin.cancel(id: _notificationId);
    } catch (_) {}
  }

  /// Handle notification button taps or notification banner click
  void _handleNotificationResponse(NotificationResponse response) {
    final bookingId = response.payload ?? _activeBookingId;
    final actionId = response.actionId;

    debugPrint('[DriverAlertService] Notification clicked: action=$actionId, bookingId=$bookingId');

    if (actionId == 'accept_order') {
      stopAlert();
      if (bookingId != null && bookingId.isNotEmpty) {
        _onActionCallback?.call(bookingId, true);
      }
    } else if (actionId == 'decline_order') {
      stopAlert();
      if (bookingId != null && bookingId.isNotEmpty) {
        _onActionCallback?.call(bookingId, false);
      }
    } else {
      // Driver tapped notification body
    }
  }

  void dispose() {
    stopAlert();
    try {
      _audioPlayer?.dispose();
    } catch (_) {}
  }
}

/// Top-level background notification action handler required by flutter_local_notifications
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint('[DriverAlertService] Background notification tap: ${notificationResponse.actionId}');
}

final driverAlertServiceProvider = Provider<DriverAlertService>((ref) {
  final service = DriverAlertService();
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
});
