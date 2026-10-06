import '../../rust/api.dart' as bridge;
import '../../rust/models.dart';

class ChatRepository {
  Future<List<Message>> getMessages(String roomId) =>
      bridge.getMessages(roomId: roomId);

  Future<void> sendMessage(
    String roomId,
    String text, {
    String? replyToEventId,
  }) async {
    await bridge.sendMessage(
      roomId: roomId,
      text: text,
      replyToEventId: replyToEventId,
    );
  }
}
