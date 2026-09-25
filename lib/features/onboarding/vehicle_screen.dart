import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repositories/repositories.dart';

class VehicleScreen extends ConsumerStatefulWidget {
  const VehicleScreen({super.key});

  @override
  ConsumerState<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends ConsumerState<VehicleScreen> {
  final _regNumber = TextEditingController();
  String? _selectedTypeId;
  bool _busy = false;
  List<dynamic> _types = [];

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final result = await ref.read(vehicleRepositoryProvider).getVehicleTypes();
    if (!mounted) return;
    result.match(
      (_) {}, // Ignoring errors for now
      (types) => setState(() {
        _types = types;
        if (_types.isNotEmpty) _selectedTypeId = _types.first['id'];
      }),
    );
  }

  @override
  void dispose() {
    _regNumber.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _regNumber.text.trim();
    if (text.isEmpty || _selectedTypeId == null) return;
    
    setState(() => _busy = true);
    
    final result = await ref.read(vehicleRepositoryProvider).registerVehicle(_selectedTypeId!, text);
    if (!mounted) return;
    setState(() => _busy = false);
    
    result.match(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (_) => context.go(Routes.home),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Registration')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RaftarSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter Vehicle Details',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: RaftarSpacing.xl),
              if (_types.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedTypeId,
                  decoration: const InputDecoration(labelText: 'Vehicle Type'),
                  items: _types.map((t) => DropdownMenuItem<String>(
                    value: t['id'],
                    child: Text(t['name']),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedTypeId = val),
                ),
              const SizedBox(height: RaftarSpacing.xl),
              RaftarTextField(
                label: 'Registration Number',
                controller: _regNumber,
                hint: 'MH 12 AB 1234',
              ),
              const Spacer(),
              RaftarButton(
                label: 'Submit & Go to Home',
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
