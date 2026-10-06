import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _homeserver = TextEditingController(text: 'https://matrix.org');
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _homeserver.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _homeserver,
                decoration: const InputDecoration(labelText: 'Homeserver'),
              ),
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Usuário'),
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
              ),
              const SizedBox(height: 16),
              if (state.isLoading)
                const CircularProgressIndicator()
              else
                FilledButton(
                  onPressed: () => ref
                      .read(authControllerProvider.notifier)
                      .login(
                        homeserver: _homeserver.text.trim(),
                        username: _username.text.trim(),
                        password: _password.text,
                      ),
                  child: const Text('Entrar'),
                ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Não foi possível entrar. Verifique suas credenciais.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
