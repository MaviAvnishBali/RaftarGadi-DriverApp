import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:driver_app/session/session_controller.dart';
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
  final _regNumberController = TextEditingController();
  final _modelController = TextEditingController();

  String? _selectedTypeId;
  String _selectedBodyType = 'DELIVERY_BAG';
  bool _busy = false;
  List<dynamic> _types = [];

  bool get _isTwoWheeler {
    if (_selectedTypeId == null) return false;
    final item = _types.firstWhere(
      (t) => t['id'] == _selectedTypeId,
      orElse: () => null,
    );
    if (item == null) return false;
    final name = (item['name'] as String? ?? '').toLowerCase();
    return name.contains('2-wheeler') || name.contains('bike') || name.contains('scooter');
  }

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final result = await ref.read(vehicleRepositoryProvider).getVehicleTypes();
    if (!mounted) return;
    result.match(
      (_) {
        setState(() {
          _types = [
            {'id': '2w-bike', 'name': '2-Wheeler (Bike / Scooter)', 'maxWeightKg': 20},
            {'id': '3w-cargo', 'name': '3-Wheeler Cargo', 'maxWeightKg': 500},
            {'id': 'tata-ace', 'name': 'Tata Ace (Chota Hathi)', 'maxWeightKg': 850},
            {'id': 'pickup-8ft', 'name': '8ft Pickup / Bolero', 'maxWeightKg': 1200},
          ];
          _selectedTypeId = _types.first['id'];
          _selectedBodyType = 'DELIVERY_BAG';
        });
      },
      (types) => setState(() {
        _types = types.isNotEmpty
            ? types
            : [
                {'id': '2w-bike', 'name': '2-Wheeler (Bike / Scooter)', 'maxWeightKg': 20},
                {'id': '3w-cargo', 'name': '3-Wheeler Cargo', 'maxWeightKg': 500},
                {'id': 'tata-ace', 'name': 'Tata Ace (Chota Hathi)', 'maxWeightKg': 850},
                {'id': 'pickup-8ft', 'name': '8ft Pickup / Bolero', 'maxWeightKg': 1200},
              ];
        if (_types.isNotEmpty) {
          _selectedTypeId = _types.first['id'];
          _selectedBodyType = _isTwoWheeler ? 'DELIVERY_BAG' : 'OPEN';
        }
      }),
    );
  }

  @override
  void dispose() {
    _regNumberController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawReg = _regNumberController.text.trim().replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final modelText = _modelController.text.trim();

    if (rawReg.isEmpty || _selectedTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select vehicle type and enter registration number.')),
      );
      return;
    }

    // Validate Indian Number Plate (e.g. MH12AB1234 or DL1LAA1234)
    final plateRegex = RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4}$');
    if (!plateRegex.hasMatch(rawReg)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Registration Number format. Example: MH12AB1234 or DL01LAA1234.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);

    final result = await ref.read(vehicleRepositoryProvider).registerVehicle(
          _selectedTypeId!,
          rawReg,
          bodyType: _selectedBodyType,
          model: modelText.isNotEmpty ? modelText : null,
        );

    if (!mounted) return;
    setState(() => _busy = false);

    result.match(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
      },
      (_) {
        ref.read(sessionControllerProvider.notifier).onVehicleCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle registered successfully! Welcome to Raftar Gaddi.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go(Routes.home);
      },
    );
  }

  Widget _buildBodyTypeCard({
    required String title,
    required String description,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedBodyType == value;
    return InkWell(
      onTap: () => setState(() => _selectedBodyType = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md, vertical: RaftarSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected ? RaftarColors.primaryContainer : RaftarColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? RaftarColors.primary : RaftarColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? RaftarColors.primary : RaftarColors.textSecondary,
              size: 26,
            ),
            const SizedBox(width: RaftarSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? RaftarColors.navy : RaftarColors.textPrimary,
                        ),
                  ),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: RaftarColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: RaftarColors.primary, size: 20)
            else
              const Icon(Icons.radio_button_unchecked, color: RaftarColors.borderStrong, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final is2W = _isTwoWheeler;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Registration'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RaftarSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Register Your Vehicle',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.xs),
              Text(
                'Enter vehicle details to receive deliveries and transportation orders.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: RaftarColors.textSecondary,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.xl),

              // Vehicle Category / Tier
              if (_types.isNotEmpty) ...[
                Text(
                  'Vehicle Category',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: RaftarSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTypeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Select Vehicle Type',
                    prefixIcon: Icon(
                      is2W ? Icons.two_wheeler_rounded : Icons.local_shipping_outlined,
                      color: RaftarColors.textTertiary,
                    ),
                  ),
                  items: _types.map((t) {
                    final weight = t['maxWeightKg'] != null ? ' (Max ${t['maxWeightKg']} kg)' : '';
                    return DropdownMenuItem<String>(
                      value: t['id'],
                      child: Text(
                        '${t['name']}$weight',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedTypeId = val;
                      _selectedBodyType = _isTwoWheeler ? 'DELIVERY_BAG' : 'OPEN';
                    });
                  },
                ),
                const SizedBox(height: RaftarSpacing.xl),
              ],

              // Number Plate Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Registration Number',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: is2W ? RaftarColors.primaryContainer : const Color(0xFFFFD54F),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: is2W ? RaftarColors.primary : Colors.black54),
                    ),
                    child: Text(
                      is2W ? '2-WHEELER / BIKE' : 'COMMERCIAL (YELLOW PLATE)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: is2W ? RaftarColors.navy : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RaftarSpacing.sm),
              RaftarTextField(
                label: is2W ? 'Bike / Scooter Number' : 'Commercial RC Number',
                controller: _regNumberController,
                hint: 'e.g. DL 01 AB 1234',
                prefixIcon: Icons.confirmation_number_outlined,
              ),

              const SizedBox(height: RaftarSpacing.xl),

              // Vehicle Make & Model
              Text(
                'Vehicle Make & Model',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.sm),
              RaftarTextField(
                label: 'Model Name (Optional)',
                controller: _modelController,
                hint: is2W ? 'e.g. Honda Activa / Hero Splendor' : 'e.g. Tata Ace Gold Diesel / Bolero Maxi Truck',
                prefixIcon: is2W ? Icons.motorcycle_outlined : Icons.directions_car_outlined,
              ),

              const SizedBox(height: RaftarSpacing.xl),

              // Body Type / Equipment Selection
              Text(
                is2W ? 'Delivery Equipment Setup' : 'Cargo Body Type',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.xs),
              Text(
                is2W
                    ? 'Select your delivery gear to receive suitable package requests.'
                    : 'Matches your truck to suitable customer cargo types.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RaftarColors.textSecondary,
                    ),
              ),
              const SizedBox(height: RaftarSpacing.md),

              if (is2W) ...[
                _buildBodyTypeCard(
                  title: 'Delivery Bag / Backpack',
                  description: 'Thermal backpack for food, parcels, electronics, and documents.',
                  value: 'DELIVERY_BAG',
                  icon: Icons.backpack_outlined,
                ),
                const SizedBox(height: RaftarSpacing.sm),
                _buildBodyTypeCard(
                  title: 'Mounted Rear Box',
                  description: 'Lockable box mounted on carrier for secure parcel transit.',
                  value: 'REAR_BOX',
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(height: RaftarSpacing.sm),
                _buildBodyTypeCard(
                  title: 'Standard (Personal Carry)',
                  description: 'Carrying small parcels, keys, and documents without dedicated box.',
                  value: 'STANDARD',
                  icon: Icons.two_wheeler_outlined,
                ),
              ] else ...[
                _buildBodyTypeCard(
                  title: 'Open Body',
                  description: 'Standard open truck bed for furniture, machinery, and general cargo.',
                  value: 'OPEN',
                  icon: Icons.all_out,
                ),
                const SizedBox(height: RaftarSpacing.sm),
                _buildBodyTypeCard(
                  title: 'Closed Container',
                  description: 'Sealed weatherproof container for electronics, e-commerce, and FMCG.',
                  value: 'CLOSED_CONTAINER',
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(height: RaftarSpacing.sm),
                _buildBodyTypeCard(
                  title: 'Tarpaulin Covered',
                  description: 'Open bed equipped with waterproof tarpaulin cover for all-weather transit.',
                  value: 'TARPAULIN',
                  icon: Icons.beach_access_outlined,
                ),
              ],

              const SizedBox(height: RaftarSpacing.xl),

              // Regulatory Notice
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
                      Icons.info_outline,
                      color: RaftarColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: RaftarSpacing.sm),
                    Expanded(
                      child: Text(
                        is2W
                            ? '2-Wheelers are eligible for parcel and courier orders up to 20 kg. Valid driver license and vehicle insurance are required.'
                            : 'Ensure your truck has an active Commercial Fitness Certificate and Insurance. Private white-plate vehicles are not permitted for trucks.',
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
                label: 'Complete Onboarding',
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
