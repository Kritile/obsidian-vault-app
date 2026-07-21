import 'package:flutter_riverpod/legacy.dart';

import 'app_controller.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  final controller = AppController();
  controller.initialize();
  return controller;
});

