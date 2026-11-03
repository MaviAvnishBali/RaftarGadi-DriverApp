import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:repositories/repositories.dart';

class DriverWalletScreen extends ConsumerStatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  ConsumerState<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends ConsumerState<DriverWalletScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _walletData;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
  }

  Future<void> _fetchWalletData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final walletRepo = ref.read(walletRepositoryProvider);

    final walletFuture = walletRepo.getMyWallet();
    final txFuture = walletRepo.getMyTransactions(limit: 30);

    final results = await Future.wait([walletFuture, txFuture]);

    if (!mounted) return;

    final walletRes = results[0];
    final txRes = results[1];

    walletRes.match(
      (failure) {
        setState(() {
          _isLoading = false;
          _errorMessage = failure.message;
        });
      },
      (data) {
        final transactions = txRes.match(
          (_) => <Map<String, dynamic>>[],
          (txList) => txList as List<Map<String, dynamic>>,
        );

        setState(() {
          _isLoading = false;
          _walletData = data as Map<String, dynamic>;
          _transactions = transactions;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = (_walletData?['balance'] ?? 0.0).toDouble();
    final totalEarned = (_walletData?['totalEarned'] ?? 0.0).toDouble();

    return Scaffold(
      backgroundColor: RaftarColors.surfaceMuted,
      appBar: AppBar(
        title: const Text('My Wallet & Earnings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: RaftarColors.navy,
        foregroundColor: RaftarColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Wallet',
            onPressed: _fetchWalletData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchWalletData,
        child: _isLoading && _walletData == null
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null && _walletData == null
                ? _buildErrorView()
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(RaftarSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Hero Balance Card
                        _buildHeroBalanceCard(balance, totalEarned),
                        const SizedBox(height: RaftarSpacing.md),

                        // Payout Schedule Banner
                        _buildPayoutScheduleCard(),
                        const SizedBox(height: RaftarSpacing.md),

                        // Transactions Ledger Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Transaction History',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: RaftarColors.navy,
                                  ),
                            ),
                            Text(
                              '${_transactions.length} records',
                              style: const TextStyle(fontSize: 12, color: RaftarColors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: RaftarSpacing.sm),

                        // Transactions List
                        if (_transactions.isEmpty)
                          _buildEmptyTransactions()
                        else
                          ..._transactions.map(_buildTransactionTile),

                        const SizedBox(height: RaftarSpacing.xxl),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHeroBalanceCard(double balance, double totalEarned) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [RaftarColors.navy, Color(0xFF1B3A6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: RaftarColors.navy.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(RaftarSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'WITHDRAWABLE BALANCE',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF81C784).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_clock, size: 12, color: Color(0xFF81C784)),
                    SizedBox(width: 4),
                    Text(
                      'Instant Payout',
                      style: TextStyle(fontSize: 10, color: Color(0xFF81C784), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹${balance.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Lifetime Earned', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    '₹${totalEarned.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RaftarColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.account_balance, size: 16),
                label: const Text('Withdraw', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: balance > 0 ? () => _showWithdrawalModal(balance) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutScheduleCard() {
    return Container(
      padding: const EdgeInsets.all(RaftarSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 20),
          SizedBox(width: RaftarSpacing.sm),
          Expanded(
            child: Text(
              'Weekly auto-settlement processes every Monday directly to your registered bank account or UPI ID.',
              style: TextStyle(fontSize: 12, color: Color(0xFF1B5E20), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final type = tx['type']?.toString() ?? 'CREDIT';
    final amount = (tx['amount'] ?? 0.0).toDouble();
    final description = tx['description']?.toString() ?? 'Trip Settlement';
    final createdAtStr = tx['createdAt']?.toString();
    final date = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
    final formattedDate = date != null ? DateFormat('dd MMM, hh:mm a').format(date) : '';

    final isPositive = amount > 0;
    final isWithdrawal = type.contains('WITHDRAW');

    Color iconBg;
    IconData icon;
    Color amountColor;

    if (isWithdrawal) {
      iconBg = const Color(0xFFFFF3E0);
      icon = Icons.account_balance;
      amountColor = const Color(0xFFE65100);
    } else if (isPositive) {
      iconBg = const Color(0xFFE8F5E9);
      icon = Icons.add_circle_outline;
      amountColor = RaftarColors.success;
    } else {
      iconBg = const Color(0xFFFFEBEE);
      icon = Icons.remove_circle_outline;
      amountColor = RaftarColors.error;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: RaftarSpacing.xs),
      padding: const EdgeInsets.all(RaftarSpacing.md),
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RaftarColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconBg,
            child: Icon(icon, size: 18, color: amountColor),
          ),
          const SizedBox(width: RaftarSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: RaftarColors.navy),
                ),
                if (formattedDate.isNotEmpty)
                  Text(
                    formattedDate,
                    style: const TextStyle(fontSize: 11, color: RaftarColors.textTertiary),
                  ),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}₹${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactions() {
    return Container(
      padding: const EdgeInsets.all(RaftarSpacing.xl),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RaftarColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RaftarColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_outlined, size: 40, color: RaftarColors.textTertiary),
          SizedBox(height: RaftarSpacing.sm),
          Text(
            'No transactions yet',
            style: TextStyle(fontWeight: FontWeight.bold, color: RaftarColors.navy),
          ),
          SizedBox(height: 2),
          Text(
            'Completed delivery payouts and commissions will show here.',
            style: TextStyle(fontSize: 12, color: RaftarColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showWithdrawalModal(double maxBalance) {
    final amountController = TextEditingController(text: maxBalance.toStringAsFixed(0));
    final upiController = TextEditingController(text: 'driver@okhdfcbank');
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: RaftarColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            RaftarSpacing.lg,
            RaftarSpacing.lg,
            RaftarSpacing.lg,
            MediaQuery.of(context).viewInsets.bottom + RaftarSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RaftarColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: RaftarSpacing.md),
              const Text(
                'Request Payout',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: RaftarColors.navy),
              ),
              const SizedBox(height: 4),
              Text(
                'Available withdrawable balance: ₹${maxBalance.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: RaftarColors.textSecondary),
              ),
              const SizedBox(height: RaftarSpacing.lg),

              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Withdrawal Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: RaftarSpacing.md),

              TextField(
                controller: upiController,
                decoration: const InputDecoration(
                  labelText: 'UPI ID / VPA',
                  hintText: 'e.g. mobile@upi',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: RaftarSpacing.xl),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RaftarColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final enteredAmount = double.tryParse(amountController.text) ?? 0;
                          if (enteredAmount <= 0 || enteredAmount > maxBalance) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid amount within your balance')),
                            );
                            return;
                          }

                          setModalState(() => isSubmitting = true);
                          final res = await ref.read(walletRepositoryProvider).requestWithdrawal(
                                enteredAmount,
                                upiId: upiController.text,
                              );

                          if (!mounted) return;
                          Navigator.pop(ctx);

                          res.match(
                            (failure) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(failure.message),
                                  backgroundColor: RaftarColors.error,
                                ),
                              );
                            },
                            (_) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('₹$enteredAmount withdrawal request submitted successfully!'),
                                  backgroundColor: RaftarColors.success,
                                ),
                              );
                              _fetchWalletData();
                            },
                          );
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirm & Withdraw', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: RaftarSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RaftarSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: RaftarColors.textTertiary),
            const SizedBox(height: RaftarSpacing.md),
            Text(_errorMessage ?? 'Failed to load wallet'),
            const SizedBox(height: RaftarSpacing.md),
            ElevatedButton.icon(
              onPressed: _fetchWalletData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
