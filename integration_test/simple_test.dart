import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:matrix_chat/src/app.dart';
import 'package:matrix_chat/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('aplicação inicia', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    expect(find.byType(App), findsOneWidget);
  });
}
