import 'dart:async';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repositories/repositories.dart';
import 'package:shared_models/shared_models.dart';

/// Partner Support live chat screen for Drivers.
/// Allows partner drivers to interact directly with human support executives.
class DriverChatScreen extends ConsumerStatefulWidget {
  const DriverChatScreen({this.bookingId, super.key});

  final String? bookingId;

  @override
  ConsumerState<DriverChatScreen> createState() => _DriverChatScreenState();
}

class _DriverChatScreenState extends ConsumerState<DriverChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  SupportTicket? _ticket;
  List<SupportMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  StreamSubscription<Map<String, dynamic>>? _socketSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final repo = ref.read(supportRepositoryProvider);
    final result = await repo.getOrCreateSession(
      bookingId: widget.bookingId,
      subject: widget.bookingId != null
          ? 'Driver Partner Help - Trip #${widget.bookingId!.length > 6 ? widget.bookingId!.substring(0, 6).toUpperCase() : widget.bookingId}'
          : 'Driver Partner Operations Support',
    );

    if (!mounted) return;

    result.match(
      (err) {
        setState(() {
          _isLoading = false;
          _errorMessage = err.message;
        });
      },
      (ticket) {
        setState(() {
          _ticket = ticket;
          _messages = List.from(ticket.messages);
          _isLoading = false;
        });

        _setupSocketAndPolling(ticket.id);
        _scrollToBottom();
      },
    );
  }

  void _setupSocketAndPolling(String ticketId) {
    final socket = ref.read(socketServiceProvider);
    socket.connect(token: ref.read(apiClientProvider).authToken);
    socket.joinSupportTicket(ticketId);

    _socketSub = socket.watchSupportMessages(ticketId).listen((data) {
      if (!mounted) return;
      try {
        final newMsg = SupportMessage.fromJson(data);
        if (!_messages.any((m) => m.id == newMsg.id)) {
          setState(() {
            _messages.add(newMsg);
          });
          _scrollToBottom();
        }
      } catch (e) {
        debugPrint('[DriverChat] Error parsing incoming socket message: $e');
      }
    });

    // 5-second polling fallback to guarantee message synchronization
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshMessages(ticketId));
  }

  Future<void> _refreshMessages(String ticketId) async {
    final repo = ref.read(supportRepositoryProvider);
    final result = await repo.getMessages(ticketId);
    if (!mounted) return;

    result.match(
      (_) {},
      (msgs) {
        if (msgs.length != _messages.length) {
          setState(() {
            _messages = msgs;
          });
          _scrollToBottom();
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _ticket == null || _isSending) return;

    _messageController.clear();
    setState(() => _isSending = true);

    final repo = ref.read(supportRepositoryProvider);
    final result = await repo.sendMessage(_ticket!.id, text);

    if (!mounted) return;
    setState(() => _isSending = false);

    result.match(
      (err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${err.message}'),
            backgroundColor: RaftarColors.error,
          ),
        );
      },
      (msg) {
        if (!_messages.any((m) => m.id == msg.id)) {
          setState(() {
            _messages.add(msg);
          });
          _scrollToBottom();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaftarColors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: RaftarColors.navy,
        foregroundColor: RaftarColors.white,
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: RaftarColors.primary.withValues(alpha: 0.3),
                  child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 22),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: RaftarColors.navy, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: RaftarSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Partner Support Desk',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    _ticket?.assignedName != null
                        ? '${_ticket!.assignedName} • Partner Officer'
                        : 'Live Support • Avg response < 1m',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.greenAccent),
            tooltip: 'Call 24/7 Helpline',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Partner Helpline'),
                  content: const Text(
                    '24x7 Operations Emergency Helpline:\n\n1800-723-827 (1800-RAF-TAR)',
                    style: TextStyle(fontSize: 14),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              if (_ticket != null) {
                _refreshMessages(_ticket!.id);
              } else {
                _initSession();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: RaftarColors.primary),
                  SizedBox(height: RaftarSpacing.md),
                  Text(
                    'Connecting to Partner Support Executive...',
                    style: TextStyle(color: RaftarColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RaftarSpacing.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: RaftarColors.error, size: 48),
                        const SizedBox(height: RaftarSpacing.md),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: RaftarColors.navy, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: RaftarSpacing.lg),
                        ElevatedButton.icon(
                          onPressed: _initSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: RaftarColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry Connection'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_ticket?.bookingId != null || widget.bookingId != null)
                      _buildLinkedBookingPill(_ticket?.bookingId ?? widget.bookingId!),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: RaftarSpacing.md,
                          vertical: RaftarSpacing.md,
                        ),
                        itemCount: _messages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildIntroSecurityCard();
                          }
                          final msg = _messages[index - 1];
                          return _buildMessageBubble(msg);
                        },
                      ),
                    ),
                    _buildInputBar(),
                  ],
                ),
    );
  }

  Widget _buildLinkedBookingPill(String bookingId) {
    final displayId = bookingId.length > 8 ? bookingId.substring(0, 8).toUpperCase() : bookingId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md, vertical: 8),
      decoration: BoxDecoration(
        color: RaftarColors.accent.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: RaftarColors.accent.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_rounded, size: 18, color: RaftarColors.primary),
          const SizedBox(width: RaftarSpacing.sm),
          Expanded(
            child: Text(
              'Trip Context: #$displayId',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: RaftarColors.navy,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: RaftarColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Trip Active',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroSecurityCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: RaftarSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md, vertical: RaftarSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(RaftarRadii.md),
            border: Border.all(color: RaftarColors.border),
          ),
          child: Column(
            children: const [
              Icon(Icons.shield_outlined, size: 16, color: RaftarColors.primary),
              SizedBox(height: 4),
              Text(
                'Direct channel with Raftar Partner Care.\nReal human support officers available 24/7 for delivery & payout assistance.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: RaftarColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(SupportMessage msg) {
    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(RaftarRadii.pill),
            ),
            child: Text(
              msg.message,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }

    // If sender is NOT an agent/system, it is sent by driver (current user)
    final isMe = msg.isCustomer;
    final timeStr =
        '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: RaftarColors.primary,
              child: const Icon(Icons.support_agent_rounded, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? RaftarColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(RaftarRadii.lg),
                  topRight: const Radius.circular(RaftarRadii.lg),
                  bottomLeft: Radius.circular(isMe ? RaftarRadii.lg : 2),
                  bottomRight: Radius.circular(isMe ? 2 : RaftarRadii.lg),
                ),
                border: isMe ? null : Border.all(color: RaftarColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        msg.senderName ?? 'Partner Desk Officer',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: RaftarColors.primary,
                        ),
                      ),
                    ),
                  Text(
                    msg.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? Colors.white : RaftarColors.navy,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white70 : Colors.black45,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
                          size: 13,
                          color: msg.isRead ? Colors.lightBlueAccent : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final isResolved = _ticket?.isResolved ?? false;

    if (isResolved) {
      return Container(
        padding: const EdgeInsets.all(RaftarSpacing.md),
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'This support session was marked as resolved.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
              const SizedBox(height: RaftarSpacing.sm),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    if (_ticket != null) {
                      _ticket = SupportTicket(
                        id: _ticket!.id,
                        userId: _ticket!.userId,
                        bookingId: _ticket!.bookingId,
                        subject: _ticket!.subject,
                        status: 'IN_PROGRESS',
                        priority: _ticket!.priority,
                        createdAt: _ticket!.createdAt,
                        updatedAt: DateTime.now(),
                        messages: _ticket!.messages,
                      );
                    }
                  });
                },
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: const Text('Reopen Session'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: RaftarColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: RaftarColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(RaftarRadii.pill),
                  border: Border.all(color: RaftarColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: RaftarSpacing.md),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(fontSize: 14, color: RaftarColors.navy),
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Type your message for support...',
                    hintStyle: TextStyle(fontSize: 13, color: RaftarColors.textSecondary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: RaftarSpacing.sm),
            Container(
              decoration: const BoxDecoration(
                color: RaftarColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
