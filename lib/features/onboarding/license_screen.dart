import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:driver_app/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repositories/repositories.dart';

class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key});

  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  final _licenseController = TextEditingController();
  final _dobController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _aadhaarNameController = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _licenseController.dispose();
    _dobController.dispose();
    _aadhaarController.dispose();
    _aadhaarNameController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
    final initialDate = _dobController.text.isNotEmpty
        ? DateTime.tryParse(_dobController.text) ?? eighteenYearsAgo
        : eighteenYearsAgo;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(eighteenYearsAgo) ? eighteenYearsAgo : initialDate,
      firstDate: DateTime(1950),
      lastDate: eighteenYearsAgo,
      helpText: 'Select Date of Birth (Must be 18+)',
    );

    if (picked != null) {
      final formatted = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _dobController.text = formatted;
      });
    }
  }

  Future<void> _submit() async {
    final licenseText = _licenseController.text.trim().replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final dobText = _dobController.text.trim();
    final aadhaarText = _aadhaarController.text.trim().replaceAll(RegExp(r'[\s-]'), '');
    final nameText = _aadhaarNameController.text.trim();

    if (licenseText.isEmpty || dobText.isEmpty || aadhaarText.isEmpty || nameText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields.')),
      );
      return;
    }

    // Validate Driving License format (e.g. DL1420110012345)
    final dlRegex = RegExp(r'^[A-Z]{2}[0-9]{2}[0-9]{4}[0-9]{7}$');
    if (!dlRegex.hasMatch(licenseText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Driving License format. Expected 15-16 alphanumeric characters (e.g. DL1420110012345).'),
        ),
      );
      return;
    }

    // Validate Date of Birth format (YYYY-MM-DD)
    final dobRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dobRegex.hasMatch(dobText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date of Birth must be in YYYY-MM-DD format.')),
      );
      return;
    }

    // Validate Aadhaar number (12 digits)
    final aadhaarRegex = RegExp(r'^[2-9]{1}[0-9]{11}$');
    if (!aadhaarRegex.hasMatch(aadhaarText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid Aadhaar number. Must be a valid 12-digit UIDAI number.')),
      );
      return;
    }

    setState(() => _busy = true);

    final result = await ref.read(driverRepositoryProvider).submitKycDetails(
          licenseNumber: licenseText,
          dob: dobText,
          aadhaarNumber: aadhaarText,
          aadhaarName: nameText,
        );

    if (!mounted) return;
    setState(() => _busy = false);

    result.match(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
      },
      (_) {
        ref.read(sessionControllerProvider.notifier).onLicenseCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Identification details saved successfully! Proceed to vehicle details.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go(Routes.registerVehicle);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Identification'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RaftarSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Identity & License Details',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.xs),
              Text(
                'Enter your Driving License and Aadhaar details to register as a driver.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: RaftarColors.textSecondary,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.xl),

              // Driving License Section
              Text(
                'Driving License',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.sm),
              RaftarTextField(
                label: 'Driving License Number',
                controller: _licenseController,
                hint: 'e.g. DL1420110012345',
                prefixIcon: Icons.badge_outlined,
              ),
              const SizedBox(height: RaftarSpacing.md),
              InkWell(
                onTap: _pickDateOfBirth,
                borderRadius: BorderRadius.circular(8),
                child: IgnorePointer(
                  child: RaftarTextField(
                    label: 'Date of Birth (as on License)',
                    controller: _dobController,
                    hint: 'YYYY-MM-DD',
                    prefixIcon: Icons.calendar_today_outlined,
                  ),
                ),
              ),

              const SizedBox(height: RaftarSpacing.xl),

              // Aadhaar Card Section
              Text(
                'Aadhaar Card',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.sm),
              RaftarTextField(
                label: '12-Digit Aadhaar Number',
                controller: _aadhaarController,
                hint: 'e.g. 548912345678',
                keyboardType: TextInputType.number,
                prefixIcon: Icons.fingerprint,
              ),
              const SizedBox(height: RaftarSpacing.md),
              RaftarTextField(
                label: 'Full Name (as per Aadhaar)',
                controller: _aadhaarNameController,
                hint: 'e.g. Ramesh Kumar',
                prefixIcon: Icons.person_outline,
              ),

              const SizedBox(height: RaftarSpacing.xl),

              // Information Card
              Container(
                padding: const EdgeInsets.all(RaftarSpacing.md),
                decoration: BoxDecoration(
                  color: RaftarColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: RaftarColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: RaftarColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: RaftarSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your details are securely encrypted and masked. Government KYC validation will be completed automatically.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: RaftarColors.textSecondary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: RaftarSpacing.xxl),

              RaftarButton(
                label: 'Save & Proceed',
                isLoading: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: RaftarSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
