import 'auth_page.dart';
import 'dart:async';

import 'package:driver_app/session/session_controller.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mock_data/mock_data.dart' show kDemoOtp;
import 'package:repositories/repositories.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:go_router/go_router.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({required this.phone, super.key});

  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otp = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_otp.text.length < 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(authRepositoryProvider)
        .verifyOtp(
          phone: widget.phone,
          otp: _otp.text,
          role: 'DRIVER',
        );
    if (!mounted) return;

    await result.match(
      (failure) async {
        setState(() {
          _busy = false;
          _error = failure.message;
        });
      },
      (user) async {
        await ref.read(sessionControllerProvider.notifier).signIn(user);
        if (mounted) {
          // If we need onboarding for drivers, navigate there. Otherwise router will handle.
          // Wait, does the router redirect handle registerLicense? Let's assume after auth we want to check license, but for now let's just let router redirect or we can push it.
          // Actually, let's just let the router navigate home if authenticated. But the requirements say "Build a simple license_screen.dart... fake submit button navigates to Home."
          // So if we need to show it, we can navigate here:
          context.go(Routes.registerLicense);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RaftarSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: RaftarSpacing.xl),
              Text(
                'Verify your number',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: RaftarSpacing.sm),
              Text(
                'Enter the 6-digit code sent to ${widget.phone}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: RaftarSpacing.xxl),
              RaftarTextField(
                label: 'Verification code',
                controller: _otp,
                hint: '••••••',
                prefixIcon: Icons.lock_outline_rounded,
                keyboardType: TextInputType.number,
                errorText: _error,
                onChanged: (value) {
                  if (_error != null) setState(() => _error = null);
                  if (value.length == 6) unawaited(_verify());
                },
              ),
              const SizedBox(height: RaftarSpacing.md),
              Container(
                padding: const EdgeInsets.all(RaftarSpacing.md),
                decoration: BoxDecoration(
                  color: RaftarColors.primaryContainer,
                  borderRadius: BorderRadius.circular(RaftarRadii.sm),
                ),
                child: Text(
                  'Demo: use code $kDemoOtp',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: RaftarColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: RaftarSpacing.xl),
              RaftarButton(
                label: 'Verify',
                isLoading: _busy,
                onPressed: _verify,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
