import 'package:flutter/material.dart';

import 'app.dart';
import 'controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = WarehouseController();
  await controller.initialize();
  runApp(BaliStockApp(controller: controller));
}
