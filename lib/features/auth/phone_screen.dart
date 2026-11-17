import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repositories/repositories.dart';
import 'package:shared_widgets/shared_widgets.dart';

import 'auth_page.dart';

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
    return DoubleBackExitScope(
      child: AuthPage(
        eyebrow: 'Partner Portal',
        title: 'Welcome Back!',
        subtitle: 'Enter your registered mobile number to continue.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RaftarColors.navyCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: RaftarColors.navyBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mobile Number',
                    style: TextStyle(
                      color: RaftarColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: RaftarColors.navyDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: RaftarColors.navyBorder),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '🇮🇳 +91',
                              style: TextStyle(
                                color: RaftarColors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                            color: RaftarColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter 10-digit number',
                            hintStyle: TextStyle(
                              color: RaftarColors.white.withValues(alpha: 0.35),
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: RaftarColors.navyDark,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: RaftarColors.navyBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: RaftarColors.navyBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: RaftarColors.green, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: RaftarColors.error, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: RaftarSpacing.xl),
            RaftarButton(
              label: 'Send OTP',
              isLoading: _busy,
              onPressed: _requestOtp,
            ),
            const SizedBox(height: RaftarSpacing.xl),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'New driver partner? ',
                    style: TextStyle(
                      color: RaftarColors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push(Routes.registerLicense),
                    child: const Text(
                      'Register Now',
                      style: TextStyle(
                        color: RaftarColors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: RaftarSpacing.md),
            Text(
              'By continuing, you agree to our Driver Terms & Conditions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: RaftarColors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
