import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix_chat/src/data/repositories/auth_repository.dart';
import 'package:matrix_chat/src/features/auth/auth_controller.dart';
import 'package:matrix_chat/src/rust/models.dart';

class FakeAuthRepository extends AuthRepository {
  @override
  Future<SessionInfo?> restoreSession(String homeserver) async => null;

  @override
  Future<SessionInfo> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    return const SessionInfo(userId: '@test:matrix.org', displayName: 'test');
  }
}

void main() {
  test('AuthController restaura null sem sessão salva', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => FakeAuthRepository()),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(authControllerProvider.future);
    expect(result, isNull);
  });

  test('AuthController faz login e expõe a sessão', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => FakeAuthRepository()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authControllerProvider.notifier);
    await notifier.login(
      homeserver: 'https://matrix.org',
      username: 'test',
      password: 'secret',
    );

    expect(notifier.state.value?.userId, '@test:matrix.org');
  });
}
