import 'dart:io';

import '../../core/paths.dart';
import '../../rust/api.dart' as bridge;
import '../../rust/models.dart';

class AuthRepository {
  Future<SessionInfo?> restoreSession(String homeserver) async {
    final sp = await sessionPath();
    if (!await File(sp).exists()) return null;
    return bridge.restoreSession(
      homeserver: homeserver,
      storePath: await storePath(),
      sessionPath: sp,
    );
  }

  Future<SessionInfo> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    return bridge.login(
      homeserver: homeserver,
      username: username,
      password: password,
      storePath: await storePath(),
      sessionPath: await sessionPath(),
    );
  }

  Future<void> logout() async {
    await bridge.logout(sessionPath: await sessionPath());
  }
}
