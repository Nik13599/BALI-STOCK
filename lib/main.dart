import 'package:flutter/material.dart';

import 'app.dart';
import 'offline_first_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = OfflineFirstWarehouseController();

  // Show the application shell immediately. If local database or startup
  // synchronization fails, replace the spinner with a readable error screen
  // instead of letting the process exit silently.
  runApp(BaliStockApp(controller: controller));

  try {
    await controller.initialize();
  } catch (error, stackTrace) {
    debugPrint('BALI STOCK startup error: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(_StartupErrorApp(message: error.toString()));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF39FF6A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0F10),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BALI STOCK',
                        style: TextStyle(
                          color: Color(0xFF39FF6A),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Не удалось запустить локальную базу приложения',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Скопируйте текст ошибки ниже и передайте администратору. Данные общей базы при этом не удаляются.',
                      ),
                      const SizedBox(height: 14),
                      SelectableText(message),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
