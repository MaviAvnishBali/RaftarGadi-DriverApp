import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:repositories/repositories.dart';
import 'package:shared_models/shared_models.dart';

class DriverTripsScreen extends ConsumerStatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  ConsumerState<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends ConsumerState<DriverTripsScreen> {
  String _selectedFilter = 'ALL'; // ALL, COMPLETED, CANCELLED
  bool _isLoading = true;
  String? _errorMessage;
  List<Booking> _allBookings = [];

  @override
  void initState() {
    super.initState();
    _fetchTrips();
  }

  Future<void> _fetchTrips() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final repo = ref.read(bookingRepositoryProvider);
    final result = await repo.getDriverBookings(pageSize: 50);

    if (!mounted) return;

    result.match(
      (failure) {
        setState(() {
          _isLoading = false;
          _errorMessage = failure.message;
        });
      },
      (paginated) {
        setState(() {
          _isLoading = false;
          _allBookings = paginated.items;
        });
      },
    );
  }

  List<Booking> get _filteredBookings {
    if (_selectedFilter == 'COMPLETED') {
      return _allBookings.where((b) => b.status == BookingStatus.completed).toList();
    } else if (_selectedFilter == 'CANCELLED') {
      return _allBookings.where((b) => b.status == BookingStatus.cancelled).toList();
    }
    return _allBookings;
  }

  double get _totalEarnings {
    return _allBookings
        .where((b) => b.status == BookingStatus.completed)
        .fold(0.0, (sum, b) => sum + b.fare.total);
  }

  int get _completedCount =>
      _allBookings.where((b) => b.status == BookingStatus.completed).length;

  int get _cancelledCount =>
      _allBookings.where((b) => b.status == BookingStatus.cancelled).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaftarColors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Trip History', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: RaftarColors.navy,
        foregroundColor: RaftarColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Trips',
            onPressed: _fetchTrips,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTrips,
        child: Column(
          children: [
            // Top Summary Metrics
            _buildMetricsHeader(),

            // Filter Tabs
            _buildFilterTabs(),

            // Trips List
            Expanded(
              child: _isLoading && _allBookings.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null && _allBookings.isEmpty
                      ? _buildErrorView()
                      : _filteredBookings.isEmpty
                          ? _buildEmptyView()
                          : _buildTripsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsHeader() {
    return Container(
      color: RaftarColors.navy,
      padding: const EdgeInsets.fromLTRB(RaftarSpacing.md, 0, RaftarSpacing.md, RaftarSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(RaftarSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              label: 'Total Trips',
              value: '${_allBookings.length}',
              icon: Icons.local_shipping_outlined,
            ),
            Container(width: 1, height: 32, color: Colors.white24),
            _buildStatItem(
              label: 'Completed',
              value: '$_completedCount',
              icon: Icons.check_circle_outline,
              color: const Color(0xFF81C784),
            ),
            Container(width: 1, height: 32, color: Colors.white24),
            _buildStatItem(
              label: 'Earnings',
              value: '₹${_totalEarnings.toStringAsFixed(0)}',
              icon: Icons.currency_rupee,
              color: const Color(0xFFFFD54F),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    Color color = Colors.white,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      color: RaftarColors.white,
      padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md, vertical: RaftarSpacing.sm),
      child: Row(
        children: [
          _buildFilterChip('ALL', 'All Trips (${_allBookings.length})'),
          const SizedBox(width: RaftarSpacing.xs),
          _buildFilterChip('COMPLETED', 'Completed ($_completedCount)'),
          const SizedBox(width: RaftarSpacing.xs),
          _buildFilterChip('CANCELLED', 'Cancelled ($_cancelledCount)'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedFilter = filterKey),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? RaftarColors.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? RaftarColors.primary : RaftarColors.border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? RaftarColors.primary : RaftarColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTripsList() {
    final bookings = _filteredBookings;
    return ListView.separated(
      padding: const EdgeInsets.all(RaftarSpacing.md),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: RaftarSpacing.sm),
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return _buildTripCard(booking);
      },
    );
  }

  Widget _buildTripCard(Booking booking) {
    final isCompleted = booking.status == BookingStatus.completed;
    final isCancelled = booking.status == BookingStatus.cancelled;
    final fare = booking.fare.total;
    final formattedDate = DateFormat('dd MMM, hh:mm a').format(booking.createdAt);

    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RaftarColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _showTripDetailsModal(booking),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(RaftarSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: ID, Date, and Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: RaftarColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#${booking.id.length > 8 ? booking.id.substring(booking.id.length - 8).toUpperCase() : booking.id.toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: RaftarColors.navy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formattedDate,
                          style: const TextStyle(fontSize: 11, color: RaftarColors.textTertiary),
                        ),
                      ],
                    ),
                    _buildStatusPill(booking.status),
                  ],
                ),
                const Divider(height: 20),

                // Route: Pickup & Drop
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.circle, size: 10, color: RaftarColors.success),
                        Container(width: 2, height: 26, color: RaftarColors.border),
                        const Icon(Icons.location_on, size: 14, color: RaftarColors.error),
                      ],
                    ),
                    const SizedBox(width: RaftarSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.pickup.formattedAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            booking.drop.formattedAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                // Bottom: Distance, Vehicle, and Fare
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: RaftarColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${booking.fare.distanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          booking.vehicleType.name.toUpperCase(),
                          style: const TextStyle(fontSize: 11, color: RaftarColors.textSecondary),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          isCancelled ? '₹0' : '₹${fare.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isCompleted
                                ? RaftarColors.success
                                : isCancelled
                                    ? RaftarColors.textTertiary
                                    : RaftarColors.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 18, color: RaftarColors.textTertiary),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(BookingStatus status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case BookingStatus.completed:
        bg = const Color(0xFFE8F5E9);
        fg = RaftarColors.success;
        text = 'Completed';
        break;
      case BookingStatus.cancelled:
        bg = const Color(0xFFFFEBEE);
        fg = RaftarColors.error;
        text = 'Cancelled';
        break;
      case BookingStatus.inTransit:
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1976D2);
        text = 'In Transit';
        break;
      case BookingStatus.arrivingPickup:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFF57C00);
        text = 'Arriving';
        break;
      case BookingStatus.driverAssigned:
        bg = const Color(0xFFE1F5FE);
        fg = const Color(0xFF0288D1);
        text = 'Assigned';
        break;
      default:
        bg = RaftarColors.surfaceMuted;
        fg = RaftarColors.textSecondary;
        text = status.name.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  void _showTripDetailsModal(Booking booking) {
    final fare = booking.fare.total;
    final platformCommission = (fare * 0.15); // 15% standard commission
    final driverPayout = fare - platformCommission;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: RaftarColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(RaftarSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: RaftarColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: RaftarSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${booking.id.length > 8 ? booking.id.substring(booking.id.length - 8).toUpperCase() : booking.id.toUpperCase()}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: RaftarColors.navy),
                ),
                _buildStatusPill(booking.status),
              ],
            ),
            Text(
              DateFormat('EEEE, dd MMMM yyyy • hh:mm a').format(booking.createdAt),
              style: const TextStyle(fontSize: 12, color: RaftarColors.textSecondary),
            ),
            const Divider(height: 24),

            // Pickup & Drop
            const Text('DELIVERY ROUTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: RaftarColors.textSecondary)),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.circle, color: RaftarColors.success, size: 14),
              title: const Text('Pickup Point', style: TextStyle(fontSize: 11, color: RaftarColors.textSecondary)),
              subtitle: Text(booking.pickup.formattedAddress, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on, color: RaftarColors.error, size: 16),
              title: const Text('Delivery Point', style: TextStyle(fontSize: 11, color: RaftarColors.textSecondary)),
              subtitle: Text(booking.drop.formattedAddress, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 24),

            // Fare Breakdown
            const Text('EARNINGS BREAKDOWN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: RaftarColors.textSecondary)),
            const SizedBox(height: 8),
            _buildFareRow('Total Customer Fare', '₹${fare.toStringAsFixed(2)}'),
            _buildFareRow('Platform Commission (15%)', '- ₹${platformCommission.toStringAsFixed(2)}', isNegative: true),
            const Divider(height: 16),
            _buildFareRow('Net Driver Earnings', '₹${driverPayout.toStringAsFixed(2)}', isTotal: true),
            const SizedBox(height: RaftarSpacing.lg),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RaftarColors.navy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: RaftarSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildFareRow(String label, String value, {bool isNegative = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? RaftarColors.navy : RaftarColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: isTotal
                  ? RaftarColors.success
                  : isNegative
                      ? RaftarColors.error
                      : RaftarColors.navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RaftarSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 64, color: RaftarColors.textTertiary),
            const SizedBox(height: RaftarSpacing.md),
            Text(
              _selectedFilter == 'ALL'
                  ? 'No trips recorded yet'
                  : 'No $_selectedFilter trips found',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: RaftarColors.navy),
            ),
            const SizedBox(height: 4),
            const Text(
              'Trips and deliveries you take will appear here with complete receipts and earnings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: RaftarColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RaftarSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: RaftarColors.textTertiary),
            const SizedBox(height: RaftarSpacing.md),
            Text(_errorMessage ?? 'Failed to load trips'),
            const SizedBox(height: RaftarSpacing.md),
            ElevatedButton.icon(
              onPressed: _fetchTrips,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
