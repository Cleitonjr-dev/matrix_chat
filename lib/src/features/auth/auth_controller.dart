import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../rust/models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authControllerProvider =
    AsyncNotifierProvider<AuthController, SessionInfo?>(AuthController.new);

class AuthController extends AsyncNotifier<SessionInfo?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<SessionInfo?> build() async {
    return _repo.restoreSession('https://matrix.org');
  }

  Future<void> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async => _repo.login(
        homeserver: homeserver,
        username: username,
        password: password,
      ),
    );
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncData(null);
  }
}
