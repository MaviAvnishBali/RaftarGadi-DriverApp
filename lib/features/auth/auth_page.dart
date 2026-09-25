import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_widgets/shared_widgets.dart';

/// Responsive shell shared by the customer authentication screens.
///
/// On wide displays it pairs the form with a concise brand statement; on a
/// phone it keeps the form focused and comfortably constrained.
class AuthPage extends StatelessWidget {
  const AuthPage({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final form = ContentConstraint(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RaftarSpacing.xl,
          vertical: RaftarSpacing.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: RaftarLogo(height: 48),
            ),
            const SizedBox(height: RaftarSpacing.huge),
            Text(
              eyebrow.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: RaftarColors.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: RaftarSpacing.sm),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: RaftarSpacing.sm),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: RaftarSpacing.xxxl),
            child,
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBuilder(
          mobile: (_) => SingleChildScrollView(child: form),
          tablet: (_) => SingleChildScrollView(child: form),
          desktop: (_) => Row(
            children: [
              const Expanded(child: _AuthBrandPanel()),
              Expanded(child: SingleChildScrollView(child: form)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RaftarColors.navy,
      padding: const EdgeInsets.all(RaftarSpacing.huge),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RaftarLogo(height: 88, onNavyPanel: false),
          SizedBox(height: RaftarSpacing.xxxl),
          Text(
            'Every move,\nright on time.',
            style: TextStyle(
              color: RaftarColors.white,
              fontSize: 42,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          SizedBox(height: RaftarSpacing.lg),
          Text(
            'Book trusted local transport for parcels, furniture, and more.',
            style: TextStyle(color: RaftarColors.white, fontSize: 18),
          ),
        ],
      ),
    );
  }
}
