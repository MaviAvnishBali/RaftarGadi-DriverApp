import 'auth_page.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repositories/repositories.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String get _normalizedPhone {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('91') && digits.length == 12
        ? '+$digits'
        : '+91$digits';
  }

  Future<void> _requestOtp() async {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      setState(() => _error = 'Enter a valid 10-digit phone number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final phone = _normalizedPhone;
    final result = await ref.read(authRepositoryProvider).requestOtp(phone);
    if (!mounted) return;
    setState(() => _busy = false);

    result.match(
      (failure) => setState(() => _error = failure.message),
      (_) => context.go('${Routes.otp}?phone=${Uri.encodeComponent(phone)}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      eyebrow: 'Driver Login',
      title: 'Drive with Raftar.',
      subtitle: 'Enter your phone number to sign in as a driver.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaftarTextField(
            label: 'Phone number',
            controller: _phone,
            hint: '98765 43210',
            prefixIcon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: RaftarSpacing.xl),
          RaftarButton(
            label: 'Continue with OTP',
            isLoading: _busy,
            onPressed: _requestOtp,
          ),
          const SizedBox(height: RaftarSpacing.xl),
          Text(
            'By continuing, you agree to our Driver Terms of Service.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
