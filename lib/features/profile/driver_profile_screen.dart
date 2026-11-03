import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:driver_app/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repositories/repositories.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  ConsumerState<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final repo = ref.read(driverRepositoryProvider);
    final result = await repo.getProfile();

    if (!mounted) return;

    result.match(
      (failure) {
        setState(() {
          _isLoading = false;
          _errorMessage = failure.message;
        });
      },
      (data) {
        setState(() {
          _isLoading = false;
          _profileData = data;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;

    final driver = _profileData ?? {};
    final vehicle = driver['vehicle'] as Map<String, dynamic>?;
    final vehicleType = vehicle?['vehicleType'] as Map<String, dynamic>?;

    final fullName = driver['aadhaarName'] ?? user?.fullName ?? 'Driver Partner';
    final phone = user?.phone ?? driver['user']?['phone'] ?? '+91 99999 00003';
    final rating = (driver['avgRating'] ?? 5.0).toDouble();
    final kycStatus = (driver['kycStatus'] ?? 'APPROVED').toString();
    final isKycApproved = kycStatus == 'APPROVED' || kycStatus == 'VERIFIED';

    final regNumber = vehicle?['registrationNumber'] ?? 'DL4TA2026';
    final model = vehicle?['model'] ?? 'Tata Ace Gold';
    final vehicleTypeName = vehicleType?['name'] ?? 'Small Commercial Vehicle';

    return Scaffold(
      backgroundColor: RaftarColors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Driver Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: RaftarColors.navy,
        foregroundColor: RaftarColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Profile',
            onPressed: _fetchProfile,
          ),
        ],
      ),
      body: _isLoading && _profileData == null
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _profileData == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RaftarSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: RaftarColors.error, size: 48),
                        const SizedBox(height: RaftarSpacing.md),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: RaftarSpacing.md),
                        ElevatedButton(onPressed: _fetchProfile, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(RaftarSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              _buildHeaderCard(fullName, phone, rating, isKycApproved),
              const SizedBox(height: RaftarSpacing.md),

              // Vehicle Information Card
              _buildVehicleCard(model, regNumber, vehicleTypeName),
              const SizedBox(height: RaftarSpacing.md),

              // KYC & Verification Documents Checklist
              _buildKycChecklist(driver, isKycApproved),
              const SizedBox(height: RaftarSpacing.md),

              // Support & Safety Section
              _buildSupportSection(),
              const SizedBox(height: RaftarSpacing.md),

              // App Settings & Preferences
              _buildSettingsSection(),
              const SizedBox(height: RaftarSpacing.md),

              // Logout Button
              _buildLogoutButton(),
              const SizedBox(height: RaftarSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String name, String phone, double rating, bool isVerified) {
    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaftarColors.border),
      ),
      padding: const EdgeInsets.all(RaftarSpacing.md),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: RaftarColors.primary.withValues(alpha: 0.15),
                child: const Icon(Icons.person, size: 40, color: RaftarColors.primary),
              ),
              if (isVerified)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.check_circle, size: 18, color: RaftarColors.success),
                  ),
                ),
            ],
          ),
          const SizedBox(width: RaftarSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: RaftarColors.navy),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isVerified ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isVerified ? 'Verified' : 'Under Review',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isVerified ? RaftarColors.success : const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(phone, style: const TextStyle(fontSize: 13, color: RaftarColors.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Color(0xFFFFB300)),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    const Text('•  Partner Driver', style: TextStyle(fontSize: 12, color: RaftarColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(String model, String regNumber, String typeName) {
    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaftarColors.border),
      ),
      padding: const EdgeInsets.all(RaftarSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Assigned Vehicle',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: RaftarColors.navy,
                    ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9C4),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFBC02D)),
                ),
                child: const Text(
                  'COMMERCIAL',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: RaftarSpacing.sm),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: Color(0xFFF57F17), size: 28),
              ),
              const SizedBox(width: RaftarSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: RaftarColors.navy),
                    ),
                    Text(
                      typeName,
                      style: const TextStyle(fontSize: 12, color: RaftarColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEB3B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.black87, width: 1.5),
                ),
                child: Text(
                  regNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKycChecklist(Map<String, dynamic> driver, bool isVerified) {
    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaftarColors.border),
      ),
      padding: const EdgeInsets.all(RaftarSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Regulatory Compliance & KYC',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: RaftarColors.navy,
                    ),
              ),
              TextButton(
                onPressed: () => context.push(Routes.documents),
                child: const Text('View All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: RaftarSpacing.xs),
          _buildDocumentCheckItem(
            title: 'Commercial Driving License (DL)',
            subtitle: 'Valid for Light & Medium Goods Vehicle',
            isVerified: isVerified,
          ),
          const Divider(height: 16),
          _buildDocumentCheckItem(
            title: 'Aadhaar Identity Verification',
            subtitle: 'Government Identity Verified',
            isVerified: isVerified,
          ),
          const Divider(height: 16),
          _buildDocumentCheckItem(
            title: 'Vehicle Registration Certificate (RC)',
            subtitle: 'Yellow Commercial Plate Verified',
            isVerified: isVerified,
          ),
          const Divider(height: 16),
          _buildDocumentCheckItem(
            title: 'Commercial Vehicle Insurance',
            subtitle: 'Comprehensive Goods Carrier Policy',
            isVerified: isVerified,
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCheckItem({
    required String title,
    required String subtitle,
    required bool isVerified,
  }) {
    return Row(
      children: [
        Icon(
          isVerified ? Icons.check_circle : Icons.hourglass_top,
          color: isVerified ? RaftarColors.success : const Color(0xFFF57C00),
          size: 20,
        ),
        const SizedBox(width: RaftarSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: RaftarColors.navy)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: RaftarColors.textSecondary)),
            ],
          ),
        ),
        Text(
          isVerified ? 'Active' : 'Pending',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isVerified ? RaftarColors.success : const Color(0xFFF57C00),
          ),
        ),
      ],
    );
  }

  Widget _buildSupportSection() {
    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaftarColors.border),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.support_agent, color: RaftarColors.primary),
            title: const Text('24x7 Partner Helpline & FAQs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('Emergency support & common questions', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, size: 20, color: RaftarColors.textTertiary),
            onTap: () => context.push(Routes.helpline),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00897B)),
            title: const Text('Live Support Chat', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('Chat live with support executive', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, size: 20, color: RaftarColors.textTertiary),
            onTap: () => context.push(Routes.supportChat),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaftarColors.border),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.language, color: RaftarColors.navy),
            title: const Text('App Language', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('English (Default)', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, size: 20, color: RaftarColors.textTertiary),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Language selection: English & Hindi supported')),
              );
            },
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline, color: RaftarColors.textSecondary),
            title: Text('App Version', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text('Raftar Gaddi Partner v1.0.0 (Production Build)', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: RaftarColors.error,
        side: const BorderSide(color: RaftarColors.error),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.logout),
      label: const Text('Logout from Partner Account', style: TextStyle(fontWeight: FontWeight.bold)),
      onPressed: () {
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Sign Out'),
            content: const Text('Are you sure you want to sign out from your driver partner account?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RaftarColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  ref.read(sessionControllerProvider.notifier).signOut();
                },
                child: const Text('Logout'),
              ),
            ],
          ),
        );
      },
    );
  }
}
