import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security.dart';

Future<String?> showOperationPinValueDialog(BuildContext context) async {
  final controller = TextEditingController();
  var invalid = false;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Введите пароль доступа'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Пароль', errorText: invalid ? 'Неверный пароль' : null),
            onSubmitted: (_) {
              final value = controller.text;
              if (verifyOperationPin(value)) {
                Navigator.of(dialogContext).pop(value);
              } else {
                setState(() => invalid = true);
              }
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final value = controller.text;
              if (verifyOperationPin(value)) {
                Navigator.of(dialogContext).pop(value);
              } else {
                setState(() => invalid = true);
              }
            },
            child: const Text('Продолжить'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}
