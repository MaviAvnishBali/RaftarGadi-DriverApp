import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show ServiceStatus;
import 'package:go_router/go_router.dart';
import 'package:localization/localization.dart';
import 'package:repositories/repositories.dart';
import 'package:shared_widgets/shared_widgets.dart';

/// Hosts the primary driver navigation tabs inside the adaptive [RaftarNavShell].
/// The GoRouter [StatefulNavigationShell] preserves each tab's navigation state.
/// Also globally monitors GPS status and app lifecycle across all tabs.
class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell>
    with WidgetsBindingObserver {
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceStatusSub = ref
        .read(locationServiceProvider)
        .getServiceStatusStream()
        .listen((status) {
      if (status == ServiceStatus.disabled) {
        _forceGoOffline(
          'Device GPS turned OFF. You have been placed OFFLINE.',
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceStatusSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationOnResume();
    }
  }

  Future<void> _checkLocationOnResume() async {
    final status = await ref.read(locationServiceProvider).checkStatus();
    if (!status.isGranted) {
      await _forceGoOffline(
        !status.isServiceEnabled
            ? 'Device GPS is turned OFF. You have been placed OFFLINE.'
            : 'Location permission is required. You have been placed OFFLINE.',
      );
    }
  }

  Future<void> _forceGoOffline(String message) async {
    try {
      await ref.read(driverRepositoryProvider).goOffline();
    } catch (_) {}
    try {
      ref.read(locationServiceProvider).stopTracking();
      ref.read(socketServiceProvider).setDriverOffline();
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.location_off_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: RaftarColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DoubleBackExitScope(
      onBack: () {
        if (widget.navigationShell.currentIndex != 0) {
          widget.navigationShell.goBranch(0);
          return true;
        }
        return false;
      },
      child: RaftarNavShell(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) => widget.navigationShell.goBranch(
          index,
          initialLocation: index == widget.navigationShell.currentIndex,
        ),
        destinations: [
          RaftarDestination(
            icon: Icons.radar_outlined,
            selectedIcon: Icons.radar_rounded,
            label: l10n.navHome,
          ),
          RaftarDestination(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: l10n.navBookings,
          ),
          RaftarDestination(
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet_rounded,
            label: l10n.navWallet,
          ),
          RaftarDestination(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: l10n.navProfile,
          ),
        ],
        body: widget.navigationShell,
      ),
    );
  }
}

