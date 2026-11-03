import 'package:design_system/design_system.dart';
import 'package:driver_app/app/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DriverHelplineScreen extends StatefulWidget {
  const DriverHelplineScreen({super.key});

  @override
  State<DriverHelplineScreen> createState() => _DriverHelplineScreenState();
}

class _DriverHelplineScreenState extends State<DriverHelplineScreen> {
  final List<Map<String, String>> _faqs = [
    {
      'q': 'How are my trip earnings and platform fee calculated?',
      'a': 'You earn the base fare plus per-km distance charges and waiting time. Raftar Gaddi charges a nominal 15% platform fee on completed deliveries. Toll charges and parking fees are 100% reimbursed to you.',
    },
    {
      'q': 'When and how do I receive my earnings payout?',
      'a': 'Earnings are settled automatically every Monday directly into your verified bank account or UPI ID. You can also request an instant withdrawal at any time from your Wallet tab.',
    },
    {
      'q': 'What happens if a customer cancels after I arrive at pickup?',
      'a': 'If you have arrived at the pickup location and the customer cancels or fails to hand over the goods within 10 minutes, a cancellation fee is automatically credited directly to your wallet.',
    },
    {
      'q': 'What should I do in case of an accident or vehicle breakdown?',
      'a': 'First ensure personal safety and call emergency services if needed. Then tap the Emergency Breakdown Assistance button on this screen or call 1800-723-827 immediately. Our ops team will dispatch a replacement vehicle to secure the customer’s parcel.',
    },
    {
      'q': 'How do I claim reimbursement for toll taxes paid?',
      'a': 'Toll charges are automatically detected along approved highway routes and added to the customer invoice. If an unlisted municipal toll was paid, submit the receipt photo via the Live Support Chat.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaftarColors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Partner Helpline & FAQs', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: RaftarColors.navy,
        foregroundColor: RaftarColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(RaftarSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 24x7 Call Banner
            _buildCallBanner(),
            const SizedBox(height: RaftarSpacing.md),

            // Live Support Chat Action
            _buildLiveChatAction(),
            const SizedBox(height: RaftarSpacing.lg),

            // FAQ Header
            Text(
              'Frequently Asked Questions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: RaftarColors.navy,
                  ),
            ),
            const SizedBox(height: RaftarSpacing.sm),

            // FAQs
            ..._faqs.map(_buildFaqAccordion),

            const SizedBox(height: RaftarSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildCallBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB71C1C).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(RaftarSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.phone_in_talk, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text(
                '24x7 Toll-Free Partner Helpline',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Immediate phone assistance for on-trip emergencies, route diversions, or parcel handover issues.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: RaftarSpacing.md),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFB71C1C),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.call, size: 20),
            label: const Text('Call 1800-723-827 (Toll Free)', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Call Partner Helpline'),
                  content: const Text('Connecting to 24x7 Toll-Free Operations Center:\n\n1800-723-827 (1800-RAF-TAR)'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: RaftarColors.primary, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Dialing 1800-723-827...')),
                        );
                      },
                      child: const Text('Dial Now'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveChatAction() {
    return Container(
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RaftarColors.border),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF00897B).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.forum_outlined, color: Color(0xFF00897B), size: 22),
        ),
        title: const Text('Chat with Partner Support', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: const Text('Connect with a real support executive live', style: TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20, color: RaftarColors.textTertiary),
        onTap: () => context.push(Routes.supportChat),
      ),
    );
  }

  Widget _buildFaqAccordion(Map<String, String> faq) {
    return Container(
      margin: const EdgeInsets.only(bottom: RaftarSpacing.sm),
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RaftarColors.border),
      ),
      child: ExpansionTile(
        title: Text(
          faq['q']!,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RaftarColors.navy),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(RaftarSpacing.md, 0, RaftarSpacing.md, RaftarSpacing.md),
        children: [
          Text(
            faq['a']!,
            style: const TextStyle(fontSize: 12, color: RaftarColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}
