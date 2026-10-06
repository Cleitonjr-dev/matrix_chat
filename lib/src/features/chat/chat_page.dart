import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/models.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';

String _formatTime(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.roomId, required this.title});

  final String roomId;
  final String title;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();

  String? _replyingToId;
  String? _replyingToPreview;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _startReply(Message m) {
    setState(() {
      _replyingToId = m.eventId;
      _replyingToPreview = '${_shortName(m.sender)}: ${m.body}';
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToPreview = null;
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final replyTo = _replyingToId;
    _cancelReply();
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(widget.roomId, text, replyToEventId: replyTo);
      ref.read(messagesProvider(widget.roomId).notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao enviar: $e')),
        );
      }
    }
  }

  String _shortName(String sender) {
    if (sender.startsWith('@')) {
      final colon = sender.indexOf(':');
      final end = colon == -1 ? sender.length : colon;
      return sender.substring(1, end);
    }
    return sender;
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.roomId));
    final ownUserId = ref.watch(authControllerProvider).value?.userId;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Sem mensagens'))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[i];
                        return GestureDetector(
                          onLongPress: () => _startReply(m),
                          child: _MessageBubble(
                            message: m,
                            isMine: m.sender == ownUserId,
                            senderName: _shortName(m.sender),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_replyingToId != null) _buildReplyBar(context),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'Mensagem'),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.reply, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Respondendo a $_replyingToPreview',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.senderName,
  });

  final Message message;
  final bool isMine;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isMine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = isMine ? scheme.onPrimary : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.replyToBody.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        left:
                            BorderSide(color: fg.withValues(alpha: 0.5), width: 2),
                      ),
                      borderRadius: BorderRadius.circular(4),
                      color: fg.withValues(alpha: 0.08),
                    ),
                    child: Text(
                      message.replyToBody,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    senderName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                Text(
                  message.body,
                  style: TextStyle(color: fg, fontSize: 15),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(
              _formatTime(message.timestampMillis.toInt()),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
