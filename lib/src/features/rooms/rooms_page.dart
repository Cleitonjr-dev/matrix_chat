import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../chat/chat_page.dart';
import 'rooms_controller.dart';

class RoomsPage extends ConsumerWidget {
  const RoomsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Nenhuma sala encontrada'))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final room = list[i];
                  return ListTile(
                    title: Text(room.name),
                    subtitle: Text(
                      'Room ID: ${room.roomId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          roomId: room.roomId,
                          title: room.name,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
