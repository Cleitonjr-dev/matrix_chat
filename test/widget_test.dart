import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix_chat/src/data/repositories/auth_repository.dart';
import 'package:matrix_chat/src/features/auth/auth_controller.dart';
import 'package:matrix_chat/src/features/auth/login_page.dart';
import 'package:matrix_chat/src/rust/models.dart';

class FakeAuthRepository extends AuthRepository {
  @override
  Future<SessionInfo?> restoreSession(String homeserver) async => null;
}

void main() {
  testWidgets('LoginPage exibe campos de autenticação', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => FakeAuthRepository()),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Homeserver'), findsOneWidget);
    expect(find.text('Usuário'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
