import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync_events.dart';
import '../../data/repositories/rooms_repository.dart';
import '../../rust/models.dart';

final roomsControllerProvider =
    AsyncNotifierProvider<RoomsController, List<RoomInfo>>(RoomsController.new);

class RoomsController extends AsyncNotifier<List<RoomInfo>> {
  RoomsRepository get _repo => ref.read(roomsRepositoryProvider);

  @override
  Future<List<RoomInfo>> build() async {
    final events = ref.read(syncEventsProvider);
    final sub = events.listen((event) {
      if (event.kind == 'rooms_updated') {
        _reload();
      }
    });
    ref.onDispose(sub.cancel);

    return _repo.listRooms();
  }

  Future<void> _reload() async {
    try {
      state = AsyncData(await _repo.listRooms());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
