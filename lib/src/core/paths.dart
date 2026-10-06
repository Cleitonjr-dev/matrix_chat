import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> storePath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}matrix_store';
}

Future<String> sessionPath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}session.json';
}
