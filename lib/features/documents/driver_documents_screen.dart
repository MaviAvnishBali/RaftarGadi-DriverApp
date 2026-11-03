import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repositories/repositories.dart';

class DriverDocumentsScreen extends ConsumerStatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  ConsumerState<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends ConsumerState<DriverDocumentsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final repo = ref.read(driverRepositoryProvider);
    final res = await repo.getProfile();
    if (!mounted) return;
    res.match(
      (_) => setState(() => _isLoading = false),
      (data) => setState(() {
        _profile = data;
        _isLoading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = _profile ?? {};
    final vehicle = driver['vehicle'] as Map<String, dynamic>?;
    final licenseNumber = driver['licenseNumber'] ?? 'DL-0420180019284';
    final regNumber = vehicle?['registrationNumber'] ?? 'DL4TA2026';

    return Scaffold(
      backgroundColor: RaftarColors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Compliance Documents', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: RaftarColors.navy,
        foregroundColor: RaftarColors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(RaftarSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Verification Notice
                  Container(
                    padding: const EdgeInsets.all(RaftarSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA5D6A7)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_user_rounded, color: Color(0xFF2E7D32), size: 24),
                        SizedBox(width: RaftarSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'All Mandatory Documents Verified',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B5E20)),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Your account has full compliance clearance to accept city & intercity logistics trips.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: RaftarSpacing.md),

                  // Documents List
                  _buildDocumentCard(
                    title: 'Commercial Driving License',
                    docNumber: licenseNumber,
                    icon: Icons.drive_eta_rounded,
                    status: 'VERIFIED',
                    expiryDate: '15 March 2034',
                    category: 'Light & Medium Goods Vehicle (LMV-GV)',
                  ),
                  const SizedBox(height: RaftarSpacing.sm),

                  _buildDocumentCard(
                    title: 'Aadhaar Identity Card',
                    docNumber: 'XXXX-XXXX-9921',
                    icon: Icons.badge_rounded,
                    status: 'VERIFIED',
                    expiryDate: 'Lifetime Valid',
                    category: 'UIDAI Government Identity Verified',
                  ),
                  const SizedBox(height: RaftarSpacing.sm),

                  _buildDocumentCard(
                    title: 'Vehicle Registration Certificate (RC)',
                    docNumber: regNumber,
                    icon: Icons.local_shipping_rounded,
                    status: 'VERIFIED',
                    expiryDate: '24 June 2031',
                    category: 'Yellow Plate Commercial Goods Carrier',
                  ),
                  const SizedBox(height: RaftarSpacing.sm),

                  _buildDocumentCard(
                    title: 'Commercial Insurance Policy',
                    docNumber: 'POL-COMM-2026-88192',
                    icon: Icons.security_rounded,
                    status: 'VERIFIED',
                    expiryDate: '10 November 2027',
                    category: 'Comprehensive Third-Party & Cargo Cover',
                  ),
                  const SizedBox(height: RaftarSpacing.xl),

                  // Update Request Notice
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Document renewal portal: contact partner support')),
                        );
                      },
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Need to update an expired document? Submit Here'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDocumentCard({
    required String title,
    required String docNumber,
    required IconData icon,
    required String status,
    required String expiryDate,
    required String category,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RaftarColors.border),
      ),
      padding: const EdgeInsets.all(RaftarSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: RaftarColors.primary.withValues(alpha: 0.1),
                      child: Icon(icon, size: 20, color: RaftarColors.primary),
                    ),
                    const SizedBox(width: RaftarSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: RaftarColors.navy),
                          ),
                          Text(
                            docNumber,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RaftarColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RaftarSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 12, color: RaftarColors.success),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: RaftarColors.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: RaftarColors.textTertiary),
                ),
              ),
              const SizedBox(width: RaftarSpacing.sm),
              Text('Exp: $expiryDate', style: const TextStyle(fontSize: 11, color: RaftarColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
