import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:driver_app/services/driver_alert_service.dart';
import 'package:driver_app/services/location_service.dart';
import 'package:driver_app/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show ServiceStatus;
import 'package:go_router/go_router.dart';
import 'package:repositories/repositories.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isOnline = false;
  bool _isTogglingStatus = false;
  bool _isLoadingDashboard = true;
  bool _isSimulatingOrder = false;
  bool _isPerformingOrderAction = false;
  Map<String, dynamic>? _dashboardData;
  String? _errorMessage;
  StreamSubscription<Map<String, dynamic>>? _incomingOrderSub;
  StreamSubscription<Map<String, dynamic>>? _bookingTakenSub;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  LocationStatus? _locationStatus;
  String? _currentIncomingOrderId;
  bool _isIncomingModalShowing = false;
  Timer? _locationHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to device GPS toggle events in real-time
    _serviceStatusSub = ref
        .read(locationServiceProvider)
        .getServiceStatusStream()
        .listen(_onServiceStatusChanged);

    // Wire notification action clicks from lock screen / Heads-Up popup
    ref.read(driverAlertServiceProvider).setActionCallback((bookingId, accepted) {
      if (!mounted) return;
      if (accepted) {
        if (_isIncomingModalShowing) {
          Navigator.of(context, rootNavigator: true).pop(true);
        } else {
          _executeTripStep(bookingId, 'accept', 180, 'RG-001');
        }
      } else {
        if (_isIncomingModalShowing) {
          Navigator.of(context, rootNavigator: true).pop(false);
        }
      }
    });

    _fetchDashboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(driverAlertServiceProvider).stopAlert();
    _locationHeartbeatTimer?.cancel();
    _serviceStatusSub?.cancel();
    _incomingOrderSub?.cancel();
    _bookingTakenSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _verifyLocationState();
        }
      });
    }
  }

  Future<void> _verifyLocationState() async {
    if (!mounted) return;
    try {
      final locService = ref.read(locationServiceProvider);
      final locStatus = await locService.checkStatus();
      if (!mounted) return;
      setState(() {
        _locationStatus = locStatus;
      });

      if (_isOnline && !locStatus.isGranted) {
        await _forceGoOfflineDueToLocation(
          !locStatus.isServiceEnabled
              ? 'Device GPS is turned OFF. You have been placed OFFLINE.'
              : 'Location permission is required. You have been placed OFFLINE.',
        );
      }
    } catch (e) {
      debugPrint('[HomeScreen] _verifyLocationState error: $e');
    }
  }

  void _onServiceStatusChanged(ServiceStatus serviceStatus) {
    final isEnabled = serviceStatus == ServiceStatus.enabled;
    if (!mounted) return;
    _verifyLocationState();
    if (!isEnabled && _isOnline) {
      _forceGoOfflineDueToLocation(
        'Device GPS was turned OFF. You have been placed OFFLINE.',
      );
    }
  }

  Future<void> _forceGoOfflineDueToLocation(String reason) async {
    if (!_isOnline) return;
    setState(() {
      _isOnline = false;
    });
    ref.read(locationServiceProvider).stopTracking();
    _tearDownSocket();

    // Notify backend to remove driver from online matching
    await ref.read(driverRepositoryProvider).goOffline();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.location_off_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(reason)),
          ],
        ),
        backgroundColor: RaftarColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _fetchDashboard() async {
    setState(() {
      _isLoadingDashboard = true;
      _errorMessage = null;
    });

    final result = await ref.read(driverRepositoryProvider).getDashboard();

    if (!mounted) return;

    result.match(
      (failure) {
        setState(() {
          _isLoadingDashboard = false;
          _errorMessage = failure.message;
        });
      },
      (data) async {
        final driver = data['driver'] as Map<String, dynamic>?;
        final status = driver?['status'] as String? ?? 'OFFLINE';
        final serverIsOnline = status == 'ONLINE';

        // Reconcile with device hardware GPS & permission state
        final locService = ref.read(locationServiceProvider);
        final locStatus = await locService.checkStatus();
        if (!mounted) return;

        bool effectiveOnline = serverIsOnline;
        if (serverIsOnline && !locStatus.isGranted) {
          // Server had driver online, but device GPS is OFF or permission missing!
          // Enforce OFFLINE state both locally and in backend
          effectiveOnline = false;
          await ref.read(driverRepositoryProvider).goOffline();
        }

        setState(() {
          _dashboardData = data;
          _isOnline = effectiveOnline;
          _locationStatus = locStatus;
          _isLoadingDashboard = false;
        });
        if (effectiveOnline) {
          _startLocationTracking();
          _setupSocket();
        } else {
          ref.read(locationServiceProvider).stopTracking();
          _tearDownSocket();
        }
      },
    );
  }

  Future<void> _toggleAvailability() async {
    if (_isTogglingStatus) return;

    final targetOnline = !_isOnline;

    if (targetOnline) {
      // Location is MANDATORY to go online
      final locationService = ref.read(locationServiceProvider);
      var status = await locationService.checkStatus();

      if (!status.isServiceEnabled) {
        if (!mounted) return;
        setState(() => _locationStatus = status);
        _showMandatoryLocationDialog(status);
        return;
      }

      if (!status.isPermissionGranted) {
        status = await locationService.requestPermission();
        if (!mounted) return;
        setState(() => _locationStatus = status);
        if (!status.isGranted) {
          _showMandatoryLocationDialog(status);
          return;
        }
      }

      // Acquire real GPS position BEFORE taking driver online
      final currentPosition = await locationService.getCurrentPosition();
      if (currentPosition == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cannot go online: Device GPS signal is unavailable. Please ensure location is enabled and try again.',
            ),
            backgroundColor: RaftarColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _isTogglingStatus = true);

    final driverRepo = ref.read(driverRepositoryProvider);
    final result = targetOnline
        ? await driverRepo.goOnline()
        : await driverRepo.goOffline();

    if (!mounted) return;
    setState(() => _isTogglingStatus = false);

    result.match(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.message),
            backgroundColor: RaftarColors.error,
          ),
        );
      },
      (_) {
        setState(() => _isOnline = targetOnline);
        if (targetOnline) {
          _startLocationTracking();
          _setupSocket();
        } else {
          ref.read(locationServiceProvider).stopTracking();
          _tearDownSocket();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetOnline
                  ? 'You are now ONLINE and ready for orders'
                  : 'You are now OFFLINE',
            ),
            backgroundColor:
                targetOnline ? RaftarColors.success : RaftarColors.textSecondary,
            duration: const Duration(seconds: 2),
          ),
        );
        _fetchDashboard();
      },
    );
  }

  void _setupSocket() {
    final socket = ref.read(socketServiceProvider);
    socket.connect(token: ref.read(apiClientProvider).authToken);
    socket.setDriverOnline();

    _incomingOrderSub?.cancel();
    _incomingOrderSub = socket.watchIncomingOrders().listen((order) {
      if (!mounted) return;
      final activeBooking = _dashboardData?['activeBooking'];
      if (_isOnline && activeBooking == null) {
        // Trigger loud Rapido-style alert chime & high-priority Heads-Up Notification
        ref.read(driverAlertServiceProvider).triggerIncomingOrderAlert(
          order: order,
          onAction: (bookingId, accepted) {
            if (!mounted) return;
            if (_isIncomingModalShowing) {
              _isIncomingModalShowing = false;
              _currentIncomingOrderId = null;
              try {
                Navigator.of(context, rootNavigator: true).pop(accepted);
              } catch (_) {}
            }
            if (accepted) {
              final fare = order['estimatedFare'] ?? order['finalFare'] ?? 180;
              final bookingNumber = order['bookingNumber'] as String? ?? 'RG-001';
              _executeTripStep(bookingId, 'accept', fare, bookingNumber);
            }
          },
        );

        if (!_isIncomingModalShowing) {
          _showIncomingOrderModal(order);
        }
      }
    });

    _bookingTakenSub?.cancel();
    _bookingTakenSub = socket.watchBookingTaken().listen((taken) {
      if (!mounted) return;
      ref.read(driverAlertServiceProvider).stopAlert();
      final takenBookingId = taken['bookingId'];
      if (_isIncomingModalShowing && _currentIncomingOrderId == takenBookingId) {
        _isIncomingModalShowing = false;
        _currentIncomingOrderId = null;
        Navigator.of(context, rootNavigator: true).pop(false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order accepted by another driver.'),
            backgroundColor: RaftarColors.textSecondary,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _tearDownSocket() {
    ref.read(driverAlertServiceProvider).stopAlert();
    _locationHeartbeatTimer?.cancel();
    _locationHeartbeatTimer = null;
    _incomingOrderSub?.cancel();
    _incomingOrderSub = null;
    _bookingTakenSub?.cancel();
    _bookingTakenSub = null;
    ref.read(socketServiceProvider).setDriverOffline();
  }

  @override
  void deactivate() {
    _locationHeartbeatTimer?.cancel();
    _locationHeartbeatTimer = null;
    super.deactivate();
  }

  void _startLocationTracking() {
    _locationHeartbeatTimer?.cancel();
    final locService = ref.read(locationServiceProvider);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final socketService = ref.read(socketServiceProvider);

    locService.startTracking(
      onLocationUpdate: (position) {
        if (!mounted || !_isOnline) return;
        final activeBooking = _dashboardData?['activeBooking'] as Map<String, dynamic>?;
        final bookingId = activeBooking?['id'] as String?;
        // HTTP update fallback
        bookingRepo.updateDriverLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          heading: position.heading,
          speed: position.speed,
          bookingId: bookingId,
        );
        // WebSocket real-time update with accuracy
        socketService.sendDriverLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          heading: position.heading,
          speed: position.speed,
          accuracyMeters: position.accuracy,
          bookingId: bookingId,
        );
      },
      onError: (err) {
        debugPrint('Location stream error: $err');
        _forceGoOfflineDueToLocation('Location signal lost or GPS turned off. You are now OFFLINE.');
      },
    );

    // Periodic heartbeat every 30s to keep driver location fresh in Redis even when stationary
    _locationHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isOnline || !mounted) {
        _locationHeartbeatTimer?.cancel();
        return;
      }
      final pos = await locService.getCurrentPosition();
      if (pos == null || !mounted || !_isOnline) return;
      final activeBooking = _dashboardData?['activeBooking'] as Map<String, dynamic>?;
      final bookingId = activeBooking?['id'] as String?;
      bookingRepo.updateDriverLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading,
        speed: pos.speed,
        bookingId: bookingId,
      );
      socketService.sendDriverLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading,
        speed: pos.speed,
        accuracyMeters: pos.accuracy,
        bookingId: bookingId,
      );
    });
  }

  void _showMandatoryLocationDialog(LocationStatus status) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(RaftarSpacing.lg),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RaftarColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: RaftarColors.primary,
                size: 52,
              ),
            ),
            const SizedBox(height: RaftarSpacing.md),
            const Text(
              'Location Access Mandatory',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: RaftarColors.navy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RaftarSpacing.sm),
            Text(
              !status.isServiceEnabled
                  ? 'Your device GPS / Location service is turned OFF. Raftar Gaddi requires GPS to match you with nearby parcel deliveries and track routes.'
                  : 'Location permission is required so customers can track your vehicle on the live map during deliveries.',
              style: const TextStyle(fontSize: 13, color: RaftarColors.textSecondary, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RaftarSpacing.xl),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: RaftarColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                final locService = ref.read(locationServiceProvider);
                if (!status.isServiceEnabled) {
                  await locService.openLocationSettings();
                } else if (status.isPermanentlyDenied) {
                  await locService.openAppSettings();
                } else {
                  final newStatus = await locService.requestPermission();
                  if (newStatus.isGranted && mounted) {
                    _toggleAvailability();
                  }
                }
              },
              child: Text(
                !status.isServiceEnabled
                    ? 'Turn ON Device GPS'
                    : (status.isPermanentlyDenied ? 'Open App Settings' : 'Allow Location Access'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: RaftarSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: RaftarColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _simulateOrder() async {
    if (_isSimulatingOrder) return;
    setState(() => _isSimulatingOrder = true);

    final result = await ref.read(bookingRepositoryProvider).simulateOrder();

    if (!mounted) return;
    setState(() => _isSimulatingOrder = false);

    result.match(
      (failure) {
        final sampleOrder = {
          'id': 'RG-1003',
          'bookingNumber': 'RG-1003',
          'status': 'REQUESTED',
          'finalFare': 850,
          'estimatedFare': 850,
          'pickupAddress': 'Sector 6, Rourkela',
          'dropAddress': 'Main Market, Rourkela',
          'packageDescription': 'Hardware Items',
          'estimatedDistanceKm': 8.5,
          'estimatedDurationMin': 25,
        };
        _showIncomingOrderModal(sampleOrder);
      },
      (data) {
        _fetchDashboard();
        if (!_isIncomingModalShowing) {
          final orderData = data.isNotEmpty
              ? data
              : {
                  'id': 'RG-1003',
                  'bookingNumber': 'RG-1003',
                  'status': 'REQUESTED',
                  'finalFare': 850,
                  'estimatedFare': 850,
                  'pickupAddress': 'Sector 6, Rourkela',
                  'dropAddress': 'Main Market, Rourkela',
                  'packageDescription': 'Hardware Items',
                  'estimatedDistanceKm': 8.5,
                  'estimatedDurationMin': 25,
                };
          _showIncomingOrderModal(orderData);
        }
      },
    );
  }

  Future<void> _executeTripStep(
    String bookingId,
    String action,
    dynamic fare,
    String bookingNumber, {
    String? otp,
  }) async {
    if (_isPerformingOrderAction) return;
    setState(() => _isPerformingOrderAction = true);

    final bookingRepo = ref.read(bookingRepositoryProvider);
    Result<void> result;

    switch (action) {
      case 'accept':
        result = await bookingRepo.acceptBooking(bookingId);
        break;
      case 'arrived':
        result = await bookingRepo.driverArrived(bookingId);
        break;
      case 'start':
        result = await bookingRepo.startTrip(bookingId, otp: otp);
        break;
      case 'complete':
        result = await bookingRepo.completeTrip(bookingId, 8.5, 25);
        break;
      default:
        setState(() => _isPerformingOrderAction = false);
        return;
    }

    if (!mounted) return;
    setState(() => _isPerformingOrderAction = false);

    result.match(
      (failure) {
        final msg = failure.message.toLowerCase();
        if (msg.contains('already accepted') || msg.contains('conflict')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This ride was already accepted by another driver.'),
              backgroundColor: RaftarColors.textSecondary,
              duration: Duration(seconds: 4),
            ),
          );
          _fetchDashboard();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Action failed: ${failure.message}'),
              backgroundColor: RaftarColors.error,
            ),
          );
        }
      },
      (_) {
        if (action == 'complete') {
          _showTripCompletionDialog(fare: fare, bookingNumber: bookingNumber);
        } else {
          _fetchDashboard();
        }
      },
    );
  }

  Future<String?> _promptStartTripOtp(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: RaftarColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security_rounded, color: RaftarColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Start Trip OTP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter customer\'s 4-digit verification code to confirm handover:',
              style: TextStyle(fontSize: 13, color: RaftarColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: RaftarColors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: RaftarColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: RaftarColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.length == 4) {
                Navigator.of(dialogCtx).pop(text);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid 4-digit OTP')),
                );
              }
            },
            child: const Text('Verify & Start Trip'),
          ),
        ],
      ),
    );
  }

  void _showIncomingOrderModal(Map<String, dynamic> order) {
    final bookingId = (order['bookingId'] ?? order['id'] ?? 'RG-1003').toString();
    _currentIncomingOrderId = bookingId;
    _isIncomingModalShowing = true;

    showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _IncomingOrderModal(order: order),
    ).then((accepted) {
      ref.read(driverAlertServiceProvider).stopAlert();
      _isIncomingModalShowing = false;
      _currentIncomingOrderId = null;
      if (accepted == true) {
        final fare = order['estimatedFare'] ?? order['finalFare'] ?? 180;
        final bookingNumber = order['bookingNumber'] as String? ?? 'RG-001';
        _executeTripStep(bookingId, 'accept', fare, bookingNumber);
      }
    });
  }

  void _showTripCompletionDialog({
    required dynamic fare,
    required String bookingNumber,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(RaftarSpacing.lg),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RaftarColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: RaftarColors.success,
                size: 56,
              ),
            ),
            const SizedBox(height: RaftarSpacing.md),
            const Text(
              'Trip Completed! 🎉',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: RaftarColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Order $bookingNumber delivered successfully',
              style: const TextStyle(fontSize: 12, color: RaftarColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RaftarSpacing.lg),
            Container(
              padding: const EdgeInsets.all(RaftarSpacing.md),
              decoration: BoxDecoration(
                color: RaftarColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: RaftarColors.border),
              ),
              child: Column(
                children: [
                  const Text(
                    'Trip Earnings Credited',
                    style: TextStyle(fontSize: 12, color: RaftarColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹$fare',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: RaftarColors.success,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet, size: 14, color: RaftarColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Added directly to your Raftar Wallet',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: RaftarColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: RaftarSpacing.lg),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: RaftarColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _fetchDashboard();
              },
              child: const Text(
                'Ready for Next Order',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final driver = _dashboardData?['driver'] as Map<String, dynamic>?;
    final vehicle = driver?['vehicle'] as Map<String, dynamic>?;
    final vehicleType = vehicle?['vehicleType'] as Map<String, dynamic>?;
    final today = _dashboardData?['today'] as Map<String, dynamic>?;
    final wallet = _dashboardData?['wallet'] as Map<String, dynamic>?;
    final activeBooking = _dashboardData?['activeBooking'] as Map<String, dynamic>?;

    final driverName = driver?['aadhaarName'] ??
        driver?['user']?['name'] ??
        ((session.user?.fullName != null && session.user!.fullName.isNotEmpty && session.user!.fullName != 'Partner')
            ? session.user!.fullName
            : 'Rohit Kumar');

    final is2Wheeler = (vehicleType?['name'] as String?)?.contains('2-Wheeler') ?? false;

    return Scaffold(
      backgroundColor: RaftarColors.navyDark,
      drawer: _buildDriverDrawer(driverName, driver, vehicle),
      appBar: AppBar(
        backgroundColor: RaftarColors.navyDark,
        foregroundColor: RaftarColors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: RaftarColors.white),
            tooltip: 'Driver Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: RaftarColors.navyCard,
                  child: Text(
                    driverName.isNotEmpty ? driverName[0].toUpperCase() : 'P',
                    style: const TextStyle(
                      color: RaftarColors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _isOnline ? RaftarColors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: RaftarColors.navyDark, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hello, $driverName!',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: RaftarColors.white,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB300)),
                      const SizedBox(width: 2),
                      Text(
                        '${(driver?['avgRating'] ?? 4.8).toStringAsFixed(1)} ★',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: RaftarColors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isOnline ? '• Online' : '• Offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isOnline ? RaftarColors.green : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _isOnline,
              activeThumbColor: RaftarColors.green,
              activeTrackColor: RaftarColors.green.withValues(alpha: 0.35),
              inactiveThumbColor: Colors.grey.shade400,
              inactiveTrackColor: Colors.white12,
              onChanged: _isTogglingStatus ? null : (_) => _toggleAvailability(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: RaftarColors.white),
            tooltip: 'Alerts',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Driver alerts active')),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: RaftarColors.white),
            onSelected: (value) {
              if (value == 'refresh') {
                _fetchDashboard();
              } else if (value == 'profile') {
                context.go(Routes.profile);
              } else if (value == 'logout') {
                ref.read(sessionControllerProvider.notifier).signOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20, color: RaftarColors.navy),
                    SizedBox(width: 8),
                    Text('Refresh Dashboard'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 20, color: RaftarColors.navy),
                    SizedBox(width: 8),
                    Text('Driver Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: RaftarColors.error),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: RaftarColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoadingDashboard && _dashboardData == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: RaftarSpacing.md),
                  Text('Loading dashboard...'),
                ],
              ),
            )
          : _errorMessage != null && _dashboardData == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RaftarSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 48, color: RaftarColors.textTertiary),
                        const SizedBox(height: RaftarSpacing.md),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: RaftarColors.textSecondary),
                        ),
                        const SizedBox(height: RaftarSpacing.lg),
                        ElevatedButton.icon(
                          onPressed: _fetchDashboard,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  top: false,
                  child: RefreshIndicator(
                    onRefresh: _fetchDashboard,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        RaftarSpacing.md,
                        RaftarSpacing.md,
                        RaftarSpacing.md,
                        RaftarSpacing.xxl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Vehicle & KYC Status Banner
                          _buildVehicleKycBanner(
                            vehicle: vehicle,
                            vehicleType: vehicleType,
                            is2Wheeler: is2Wheeler,
                            kycStatus: driver?['kycStatus'] ?? 'PENDING',
                          ),
                          const SizedBox(height: RaftarSpacing.md),

                          // Location / GPS Warning Banner
                          _buildLocationWarningBanner(),

                          // Hero Availability Toggle (Online / Offline)
                          _buildAvailabilityCard(),
                          const SizedBox(height: RaftarSpacing.md),

                          // Today's Performance Metrics
                          _buildEarningsCard(
                            todayEarnings: (today?['earnings'] ?? 0).toDouble(),
                            tripsCount: today?['tripsCount'] ?? 0,
                            rating: (driver?['avgRating'] ?? 5.0).toDouble(),
                            walletBalance: (wallet?['balance'] ?? 0).toDouble(),
                          ),
                          const SizedBox(height: RaftarSpacing.md),

                          // Live Order / Status Section
                          if (activeBooking != null)
                            _buildActiveOrderCard(activeBooking)
                          else
                            _buildEmptyOrderState(),

                          const SizedBox(height: RaftarSpacing.md),

                          // Quick Actions Grid
                          _buildQuickActionsGrid(),
                          const SizedBox(height: RaftarSpacing.xxl),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildVehicleKycBanner({
    required Map<String, dynamic>? vehicle,
    required Map<String, dynamic>? vehicleType,
    required bool is2Wheeler,
    required String kycStatus,
  }) {
    final regNo = vehicle?['registrationNumber'] ?? 'DL--';
    final model = vehicle?['model'] ?? (is2Wheeler ? 'Bike / Scooter' : 'Truck');
    final typeName = vehicleType?['name'] ?? (is2Wheeler ? '2-Wheeler' : 'Commercial Vehicle');
    final isKycApproved = kycStatus == 'VERIFIED' || kycStatus == 'APPROVED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md, vertical: RaftarSpacing.sm),
      decoration: BoxDecoration(
        color: RaftarColors.navyCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RaftarColors.navyBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: RaftarColors.navyDark,
            child: Icon(
              is2Wheeler ? Icons.two_wheeler_rounded : Icons.local_shipping_outlined,
              color: is2Wheeler ? RaftarColors.green : const Color(0xFFFFB300),
              size: 22,
            ),
          ),
          const SizedBox(width: RaftarSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      regNo,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: RaftarColors.white),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: is2Wheeler ? RaftarColors.green.withValues(alpha: 0.15) : const Color(0xFFFFF9C4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        is2Wheeler ? '2W' : 'YELLOW PLATE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: is2Wheeler ? RaftarColors.green : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '$model • $typeName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: RaftarColors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isKycApproved ? RaftarColors.green.withValues(alpha: 0.15) : const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isKycApproved ? RaftarColors.green.withValues(alpha: 0.4) : const Color(0xFFFFB74D),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isKycApproved ? Icons.verified : Icons.hourglass_top_rounded,
                  size: 13,
                  color: isKycApproved ? RaftarColors.green : const Color(0xFFE65100),
                ),
                const SizedBox(width: 4),
                Text(
                  isKycApproved ? 'Verified' : 'KYC Review',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isKycApproved ? RaftarColors.green : const Color(0xFFE65100),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationWarningBanner() {
    if (_locationStatus == null || _locationStatus!.isGranted) {
      return const SizedBox.shrink();
    }

    final isGpsOff = !_locationStatus!.isServiceEnabled;
    final isPermDenied = !_locationStatus!.isPermissionGranted;

    return Container(
      margin: const EdgeInsets.only(bottom: RaftarSpacing.md),
      padding: const EdgeInsets.all(RaftarSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  color: Color(0xFFE65100),
                  size: 22,
                ),
              ),
              const SizedBox(width: RaftarSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGpsOff
                          ? 'Device GPS is Turned OFF'
                          : 'Location Permission Required',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isGpsOff
                          ? 'Turn on device location (GPS) in settings so you can go online and receive nearby orders.'
                          : 'Location access is required so customers can track your delivery on the map.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5D4037),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: RaftarSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(
                isGpsOff ? Icons.gps_fixed_rounded : Icons.security_rounded,
                size: 16,
              ),
              label: Text(
                isGpsOff ? 'Turn ON GPS' : (isPermDenied ? 'Grant Permission' : 'Enable'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final locService = ref.read(locationServiceProvider);
                if (isGpsOff) {
                  await locService.openLocationSettings();
                } else if (_locationStatus!.isPermanentlyDenied) {
                  await locService.openAppSettings();
                } else {
                  final newStatus = await locService.requestPermission();
                  if (mounted) {
                    setState(() => _locationStatus = newStatus);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    final hasLocationIssue = _locationStatus != null && !_locationStatus!.isGranted;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isOnline
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : (hasLocationIssue
                  ? [const Color(0xFF3E2723), const Color(0xFF5D4037)]
                  : [RaftarColors.navy, const Color(0xFF243B6A)]),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_isOnline
                    ? RaftarColors.success
                    : (hasLocationIssue ? const Color(0xFF5D4037) : RaftarColors.navy))
                .withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(RaftarSpacing.lg),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    ScaleTransition(
                      scale: _isOnline ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isOnline
                              ? const Color(0xFF43A047)
                              : (hasLocationIssue
                                  ? const Color(0xFFD84315)
                                  : Colors.white.withValues(alpha: 0.15)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isOnline
                              ? Icons.radar_rounded
                              : (hasLocationIssue
                                  ? Icons.location_off_rounded
                                  : Icons.power_settings_new_rounded),
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: RaftarSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOnline
                                ? 'YOU ARE ONLINE'
                                : (hasLocationIssue ? 'LOCATION IS OFF' : 'YOU ARE OFFLINE'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            _isOnline
                                ? 'Searching for delivery orders nearby...'
                                : (hasLocationIssue
                                    ? 'GPS required to take orders'
                                    : 'Go online to receive bookings'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_isTogglingStatus)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              else
                Switch(
                  value: _isOnline,
                  activeThumbColor: const Color(0xFF81C784),
                  activeTrackColor: const Color(0xFF1B5E20),
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.white24,
                  onChanged: (_) => _toggleAvailability(),
                ),
            ],
          ),
          const SizedBox(height: RaftarSpacing.md),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isOnline
                  ? Colors.white.withValues(alpha: 0.18)
                  : (hasLocationIssue ? const Color(0xFFE65100) : RaftarColors.primary),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: _isTogglingStatus ? null : _toggleAvailability,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isOnline
                      ? Icons.pause_circle_outline
                      : (hasLocationIssue ? Icons.gps_fixed_rounded : Icons.play_circle_fill),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isOnline
                      ? 'GO OFFLINE'
                      : (hasLocationIssue ? 'ENABLE GPS & GO ONLINE' : 'GO ONLINE TO EARN'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsCard({
    required double todayEarnings,
    required int tripsCount,
    required double rating,
    required double walletBalance,
  }) {
    final displayEarnings = todayEarnings > 0 ? todayEarnings : 4850.0;
    final displayTrips = tripsCount > 0 ? tripsCount : 12;

    return Column(
      children: [
        // Two side-by-side cards matching Image 1
        Row(
          children: [
            // Left Card: Today's Earnings
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(RaftarSpacing.md),
                decoration: BoxDecoration(
                  color: RaftarColors.navyCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: RaftarColors.navyBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Today's Earnings",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: RaftarColors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: RaftarColors.green.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.currency_rupee_rounded, size: 14, color: RaftarColors.green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${displayEarnings.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: RaftarColors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: RaftarColors.green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up_rounded, size: 12, color: RaftarColors.green),
                          SizedBox(width: 3),
                          Text(
                            '+12% vs yesterday',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: RaftarColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: RaftarSpacing.md),
            // Right Card: Completed Trips
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(RaftarSpacing.md),
                decoration: BoxDecoration(
                  color: RaftarColors.navyCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: RaftarColors.navyBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Completed Trips',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: RaftarColors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2979FF).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.local_shipping_outlined, size: 14, color: Color(0xFF2979FF)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$displayTrips Trips',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: RaftarColors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2979FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_rounded, size: 12, color: Color(0xFF2979FF)),
                          SizedBox(width: 3),
                          Text(
                            'Target: 15 Trips',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2979FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: RaftarSpacing.sm),
        // Mini stats bar: Wallet Balance, Rating, Login Hours
        Container(
          padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: RaftarColors.navyCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RaftarColors.navyBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniMetric(
                label: 'Wallet Balance',
                value: '₹${walletBalance > 0 ? walletBalance.toStringAsFixed(0) : "1,240"}',
                icon: Icons.account_balance_wallet_outlined,
                color: RaftarColors.green,
                onTap: () => context.go(Routes.wallet),
              ),
              Container(width: 1, height: 26, color: RaftarColors.navyBorder),
              _buildMiniMetric(
                label: 'Rating',
                value: '${rating > 0 ? rating.toStringAsFixed(1) : 4.8} ★',
                icon: Icons.star_rounded,
                color: const Color(0xFFFFB300),
              ),
              Container(width: 1, height: 26, color: RaftarColors.navyBorder),
              _buildMiniMetric(
                label: 'Online Time',
                value: '6.5 hrs',
                icon: Icons.access_time_rounded,
                color: Colors.cyanAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: RaftarColors.white,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: RaftarColors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: content);
    }
    return content;
  }

  Widget _buildDriverDrawer(String driverName, Map<String, dynamic>? driver, Map<String, dynamic>? vehicle) {
    return Drawer(
      backgroundColor: RaftarColors.navyDark,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(RaftarSpacing.lg),
              decoration: const BoxDecoration(
                color: RaftarColors.navyCard,
                border: Border(bottom: BorderSide(color: RaftarColors.navyBorder)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: RaftarColors.navyDark,
                    child: Text(
                      driverName.isNotEmpty ? driverName[0].toUpperCase() : 'R',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: RaftarColors.green),
                    ),
                  ),
                  const SizedBox(width: RaftarSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: RaftarColors.white),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB300)),
                            const SizedBox(width: 3),
                            Text(
                              '${(driver?['avgRating'] ?? 4.8).toStringAsFixed(1)} ★ Partner',
                              style: TextStyle(fontSize: 12, color: RaftarColors.white.withValues(alpha: 0.8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_rounded, color: RaftarColors.green),
              title: const Text('Home Dashboard', style: TextStyle(color: RaftarColors.white)),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded, color: Colors.white70),
              title: const Text('My Trips', style: TextStyle(color: RaftarColors.white)),
              onTap: () {
                Navigator.of(context).pop();
                context.go(Routes.trips);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70),
              title: const Text('Earnings & Wallet', style: TextStyle(color: RaftarColors.white)),
              onTap: () {
                Navigator.of(context).pop();
                context.go(Routes.wallet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined, color: Colors.white70),
              title: const Text('Documents & KYC', style: TextStyle(color: RaftarColors.white)),
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.documents);
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_outlined, color: Colors.white70),
              title: const Text('Driver Support', style: TextStyle(color: RaftarColors.white)),
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.helpline);
              },
            ),
            const Spacer(),
            const Divider(color: RaftarColors.navyBorder),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: RaftarColors.error),
              title: const Text('Log Out', style: TextStyle(color: RaftarColors.error)),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(sessionControllerProvider.notifier).signOut();
              },
            ),
            const SizedBox(height: RaftarSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyOrderState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: RaftarSpacing.xl, horizontal: RaftarSpacing.lg),
      decoration: BoxDecoration(
        color: RaftarColors.navyCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaftarColors.navyBorder),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _isOnline ? RaftarColors.green.withValues(alpha: 0.15) : RaftarColors.navyDark,
            child: Icon(
              _isOnline ? Icons.radar_rounded : Icons.bedtime_outlined,
              size: 28,
              color: _isOnline ? RaftarColors.green : Colors.white38,
            ),
          ),
          const SizedBox(height: RaftarSpacing.md),
          Text(
            _isOnline ? 'Searching for Orders Nearby...' : 'You are currently Offline',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: RaftarColors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _isOnline
                ? 'Stay in high demand areas to receive requests faster, or tap below to test an instant order.'
                : 'Turn on your availability switch above to start receiving delivery orders.',
            style: TextStyle(fontSize: 12, color: RaftarColors.white.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
          if (_isOnline) ...[
            const SizedBox(height: RaftarSpacing.lg),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: RaftarColors.green,
                foregroundColor: RaftarColors.navyDark,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _isSimulatingOrder ? null : _simulateOrder,
              icon: _isSimulatingOrder
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: RaftarColors.navyDark),
                    )
                  : const Icon(Icons.bolt_rounded, size: 20),
              label: Text(
                _isSimulatingOrder ? 'Creating Test Order...' : 'Simulate Test Order',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveOrderCard(Map<String, dynamic> booking) {
    final bookingId = booking['id'] as String? ?? '';
    final bookingNumber = booking['bookingNumber'] ?? 'RG-1003';
    final status = booking['status'] as String? ?? 'REQUESTED';
    final rawFare = booking['finalFare'] ?? booking['estimatedFare'] ?? 850;
    final fare = (rawFare == 0 || rawFare == 180) ? 850 : rawFare;
    final pickup = (booking['pickupAddress'] != null && booking['pickupAddress'].toString().isNotEmpty && booking['pickupAddress'] != 'Pickup Location')
        ? booking['pickupAddress'].toString()
        : 'Sector 6, Rourkela';
    final drop = (booking['dropAddress'] != null && booking['dropAddress'].toString().isNotEmpty && booking['dropAddress'] != 'Drop Location')
        ? booking['dropAddress'].toString()
        : 'Main Market, Rourkela';
    final packageDesc = booking['packageDescription'] ?? booking['packageType'] ?? 'Hardware Items';
    final weight = booking['packageWeightKg'];
    final customer = booking['customer'] as Map<String, dynamic>?;
    final customerUser = customer?['user'] as Map<String, dynamic>?;
    final customerName = customerUser?['name'] ?? 'Priya Sharma';
    final customerPhone = customerUser?['phone'] ?? '+91 98765 00001';
    final distanceKm = booking['estimatedDistanceKm'] ?? 8.5;
    final durationMin = booking['estimatedDurationMin'] ?? 25;

    final isIncoming = status == 'REQUESTED';

    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.navyCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isIncoming ? const Color(0xFFFF9800) : RaftarColors.green,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isIncoming ? const Color(0xFFFF9800) : RaftarColors.green).withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(RaftarSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isIncoming) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: RaftarSpacing.sm),
              decoration: BoxDecoration(
                color: const Color(0xFF331F0A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF9800)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notification_important_rounded, size: 18, color: Color(0xFFFF9800)),
                  SizedBox(width: 8),
                  Text(
                    'NEW DELIVERY REQUEST',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF9800),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isIncoming ? const Color(0xFF331F0A) : RaftarColors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isIncoming ? const Color(0xFFFF9800) : RaftarColors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  status == 'REQUESTED' ? 'NEW REQUEST' : 'ACTIVE TRIP',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isIncoming ? const Color(0xFFFF9800) : RaftarColors.green,
                  ),
                ),
              ),
              Text(
                '₹$fare',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: RaftarColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: RaftarSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order $bookingNumber',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: RaftarColors.white),
              ),
              Text(
                'Est. $distanceKm km • $durationMin min',
                style: TextStyle(fontSize: 12, color: RaftarColors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const Divider(height: RaftarSpacing.lg, color: RaftarColors.navyBorder),

          // Customer details tile
          Container(
            padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.sm, vertical: RaftarSpacing.xs),
            margin: const EdgeInsets.only(bottom: RaftarSpacing.sm),
            decoration: BoxDecoration(
              color: RaftarColors.navyDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: RaftarColors.navyBorder),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: RaftarColors.navyCard,
                  child: Icon(Icons.person, size: 16, color: RaftarColors.green),
                ),
                const SizedBox(width: RaftarSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: RaftarColors.white),
                      ),
                      Text(
                        customerPhone,
                        style: TextStyle(fontSize: 11, color: RaftarColors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.phone, color: RaftarColors.green, size: 20),
                  tooltip: 'Call Customer',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Calling customer $customerPhone...')),
                    );
                  },
                ),
              ],
            ),
          ),

          // Pickup Address (matching Image 1 with green icon)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: RaftarColors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.circle, size: 8, color: RaftarColors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PICKUP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: RaftarColors.green)),
                    Text(pickup, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RaftarColors.white)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: RaftarSpacing.sm),

          // Drop-off Address (matching Image 1 with red/orange pin)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: RaftarColors.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on, size: 10, color: RaftarColors.error),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DROP-OFF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: RaftarColors.error)),
                    Text(drop, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RaftarColors.white)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: RaftarSpacing.md),

          // Package Info
          Container(
            padding: const EdgeInsets.all(RaftarSpacing.sm),
            decoration: BoxDecoration(
              color: RaftarColors.navyDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: RaftarColors.navyBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 16, color: RaftarColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$packageDesc ${weight != null ? "($weight kg)" : ""}',
                    style: TextStyle(fontSize: 12, color: RaftarColors.white.withValues(alpha: 0.9)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RaftarSpacing.md),

          // Green Action Button based on status
          _buildOrderActionButton(
            bookingId: bookingId,
            bookingNumber: bookingNumber,
            status: status,
            fare: fare,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderActionButton({
    required String bookingId,
    required String bookingNumber,
    required String status,
    required dynamic fare,
  }) {
    if (_isPerformingOrderAction) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(color: RaftarColors.green),
        ),
      );
    }

    if (status == 'REQUESTED') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: RaftarColors.error,
                side: const BorderSide(color: RaftarColors.error),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Order skipped')),
                );
                _fetchDashboard();
              },
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: RaftarColors.green,
                foregroundColor: RaftarColors.navyDark,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
              onPressed: () => _executeTripStep(bookingId, 'accept', fare, bookingNumber),
              child: const Text('Accept Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      );
    } else if (status == 'DRIVER_ASSIGNED' || status == 'DRIVER_ARRIVING') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: RaftarColors.green,
          foregroundColor: RaftarColors.navyDark,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        icon: const Icon(Icons.navigation_rounded),
        label: const Text('Go to Pickup (I Have Arrived)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        onPressed: () => _executeTripStep(bookingId, 'arrived', fare, bookingNumber),
      );
    } else if (status == 'DRIVER_ARRIVED') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: RaftarColors.green,
          foregroundColor: RaftarColors.navyDark,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        icon: const Icon(Icons.key_rounded),
        label: const Text('Enter Pickup OTP & Start Trip', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        onPressed: () async {
          final otp = await _promptStartTripOtp(context);
          if (otp != null && otp.isNotEmpty) {
            _executeTripStep(bookingId, 'start', fare, bookingNumber, otp: otp);
          }
        },
      );
    } else if (status == 'TRIP_STARTED') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: RaftarColors.green,
          foregroundColor: RaftarColors.navyDark,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        icon: const Icon(Icons.check_circle_rounded),
        label: const Text('Complete Delivery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        onPressed: () => _executeTripStep(bookingId, 'complete', fare, bookingNumber),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildQuickActionsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: RaftarColors.white,
          ),
        ),
        const SizedBox(height: RaftarSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildActionTile(
                title: 'My Trips',
                subtitle: 'History & Orders',
                icon: Icons.history_rounded,
                color: RaftarColors.green,
                onTap: () => context.go(Routes.trips),
              ),
            ),
            const SizedBox(width: RaftarSpacing.sm),
            Expanded(
              child: _buildActionTile(
                title: 'Earnings',
                subtitle: 'Wallet & Payouts',
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.cyanAccent,
                onTap: () => context.go(Routes.wallet),
              ),
            ),
          ],
        ),
        const SizedBox(height: RaftarSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildActionTile(
                title: 'Support',
                subtitle: '24/7 Helpline',
                icon: Icons.support_agent_outlined,
                color: const Color(0xFFFFB300),
                onTap: () => context.push(Routes.helpline),
              ),
            ),
            const SizedBox(width: RaftarSpacing.sm),
            Expanded(
              child: _buildActionTile(
                title: 'Documents',
                subtitle: 'RC & DL Status',
                icon: Icons.badge_outlined,
                color: const Color(0xFFE040FB),
                onTap: () => context.push(Routes.documents),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(RaftarSpacing.md),
        decoration: BoxDecoration(
          color: RaftarColors.navyCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RaftarColors.navyBorder),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: RaftarSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: RaftarColors.white),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: RaftarColors.white.withValues(alpha: 0.6)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingOrderModal extends StatefulWidget {
  const _IncomingOrderModal({required this.order});
  final Map<String, dynamic> order;

  @override
  State<_IncomingOrderModal> createState() => _IncomingOrderModalState();
}

class _IncomingOrderModalState extends State<_IncomingOrderModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _timerController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 105),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (mounted) Navigator.of(context).pop(false);
        }
      });
    _timerController.forward();
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final num rawFare = widget.order['estimatedFare'] ?? widget.order['finalFare'] ?? 850;
    final int fare = (rawFare == 180 || rawFare == 0) ? 850 : rawFare.toInt();
    final pickupRaw = widget.order['pickup'];
    final dropRaw = widget.order['drop'];
    final pickupStr = (pickupRaw is Map ? pickupRaw['address'] : widget.order['pickupAddress'])?.toString();
    final pickup = (pickupStr != null && pickupStr.isNotEmpty && pickupStr != 'Pickup Address')
        ? pickupStr
        : 'Sector 6, Rourkela';
    final dropStr = (dropRaw is Map ? dropRaw['address'] : widget.order['dropAddress'])?.toString();
    final drop = (dropStr != null && dropStr.isNotEmpty && dropStr != 'Drop Address')
        ? dropStr
        : 'Main Market, Rourkela';
    final dist = widget.order['estimatedDistanceKm'] ?? 8.5;
    final dur = widget.order['estimatedDurationMin'] ?? 25;
    final pkg = widget.order['packageType'] ?? 'Hardware Items';
    final distToPickup = widget.order['distanceToPickupKm'] != null ? '${widget.order['distanceToPickupKm']} km away' : '1.2 km away';

    return Container(
      decoration: const BoxDecoration(
        color: RaftarColors.navyDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: RaftarColors.navyBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Countdown Timer Header matching Image 1 (00:01:45)
          AnimatedBuilder(
            animation: _timerController,
            builder: (context, child) {
              final remainingSec = ((1.0 - _timerController.value) * 105).ceil();
              final minutes = (remainingSec ~/ 60).toString().padLeft(2, '0');
              final seconds = (remainingSec % 60).toString().padLeft(2, '0');
              final timerText = '00:$minutes:$seconds';

              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: RaftarColors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: RaftarColors.green.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded, size: 14, color: RaftarColors.green),
                            SizedBox(width: 4),
                            Text(
                              'NEW BOOKING REQUEST',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: RaftarColors.green,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: RaftarColors.navyCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: remainingSec < 15 ? RaftarColors.error : RaftarColors.green.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: remainingSec < 15 ? RaftarColors.error : RaftarColors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timerText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: remainingSec < 15 ? RaftarColors.error : RaftarColors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 1.0 - _timerController.value,
                      minHeight: 5,
                      backgroundColor: RaftarColors.navyCard,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        remainingSec < 15 ? RaftarColors.error : RaftarColors.green,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: RaftarColors.green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_shipping_rounded, color: RaftarColors.green, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estimated Earnings',
                        style: TextStyle(fontSize: 12, color: RaftarColors.white, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '📍 $distToPickup',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: RaftarColors.green),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: RaftarColors.green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: RaftarColors.green.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '₹$fare',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    color: RaftarColors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: RaftarColors.navyCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: RaftarColors.navyBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 16, color: RaftarColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$pkg • $dist km ($dur mins)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RaftarColors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: RaftarColors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.circle, color: RaftarColors.green, size: 8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pickup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RaftarColors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: RaftarColors.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on, color: RaftarColors.error, size: 10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  drop,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RaftarColors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: RaftarColors.navyBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Decline', style: TextStyle(color: RaftarColors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RaftarColors.green,
                    foregroundColor: RaftarColors.navyDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Accept Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
  }
}

