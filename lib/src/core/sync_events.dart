import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/rooms_repository.dart';
import '../rust/models.dart';

/// Stream compartilhado de eventos de sincronização.
///
/// Inicia o loop de sync do Rust (`start_sync`) uma única vez e o expõe como
/// um [Stream] broadcast, para que as telas de salas e de chat possam ouvir as
/// mesmas notificações de atualização em tempo real.
final syncEventsProvider = Provider<Stream<SyncEvent>>((ref) {
  final controller = StreamController<SyncEvent>.broadcast();
  final rustStream = RoomsRepository().startSync();

  final sub = rustStream.listen(
    controller.add,
    onError: controller.addError,
  );
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
