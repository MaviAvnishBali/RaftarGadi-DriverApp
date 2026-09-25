import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
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
  final _license = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _license.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _license.text.trim();
    if (text.isEmpty) return;
    
    setState(() => _busy = true);
    
    final result = await ref.read(driverRepositoryProvider).registerDriver(text);
    if (!mounted) return;
    setState(() => _busy = false);
    
    result.match(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (_) => context.go(Routes.registerVehicle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Onboarding')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RaftarSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter your License Number',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: RaftarSpacing.xl),
              RaftarTextField(
                label: 'License Number',
                controller: _license,
                hint: 'DL-1420110012345',
              ),
              const Spacer(),
              RaftarButton(
                label: 'Next',
                isLoading: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

