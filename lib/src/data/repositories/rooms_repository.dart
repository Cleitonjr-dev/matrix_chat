import '../../rust/api.dart' as bridge;
import '../../rust/models.dart';

class RoomsRepository {
  Future<List<RoomInfo>> listRooms() => bridge.listRooms();

  Stream<SyncEvent> startSync() => bridge.startSync();
}
