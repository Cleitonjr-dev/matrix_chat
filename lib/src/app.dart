import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/rooms/rooms_page.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return MaterialApp(
      title: 'matrix_chat',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: auth.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const LoginPage(),
        data: (session) => session == null ? const LoginPage() : const RoomsPage(),
      ),
    );
  }
}
