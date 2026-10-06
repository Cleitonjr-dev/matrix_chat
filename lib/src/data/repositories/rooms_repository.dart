import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api.dart' as bridge;
import '../../rust/models.dart';

final roomsRepositoryProvider = Provider<RoomsRepository>((ref) => RoomsRepository());

class RoomsRepository {
  Future<List<RoomInfo>> listRooms() => bridge.listRooms();

  Stream<SyncEvent> startSync() => bridge.startSync();
}
