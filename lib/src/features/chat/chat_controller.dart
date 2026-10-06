import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync_events.dart';
import '../../data/repositories/chat_repository.dart';
import '../../rust/models.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository());

final messagesProvider =
    AsyncNotifierProvider.family<MessagesController, List<Message>, String>(
  MessagesController.new,
);

class MessagesController extends AsyncNotifier<List<Message>> {
  MessagesController(this.roomId);

  final String roomId;
  bool _refreshing = false;

  @override
  Future<List<Message>> build() {
    final events = ref.read(syncEventsProvider);
    final sub = events.listen((event) {
      if (event.kind == 'rooms_updated') {
        refresh();
      }
    });
    ref.onDispose(sub.cancel);

    return _fetch();
  }

  Future<List<Message>> _fetch() {
    return ref.read(chatRepositoryProvider).getMessages(roomId);
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      state = AsyncError(e, st);
    } finally {
      _refreshing = false;
    }
  }
}
