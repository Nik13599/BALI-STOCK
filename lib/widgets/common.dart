import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security.dart';

Future<bool> showOperationPinDialog(BuildContext context) async {
  final controller = TextEditingController();
  var invalid = false;
  final result = await showDialog<bool>(
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
              if (verifyOperationPin(controller.text)) {
                Navigator.of(dialogContext).pop(true);
              } else {
                setState(() => invalid = true);
              }
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (verifyOperationPin(controller.text)) {
                Navigator.of(dialogContext).pop(true);
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
  return result ?? false;
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 62, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, required this.icon, this.danger = false});

  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: danger ? colors.errorContainer.withValues(alpha: .45) : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: danger ? colors.error : colors.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class TwoFields extends StatelessWidget {
  const TwoFields({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 440) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: first), const SizedBox(width: 12), Expanded(child: second)]);
      },
    );
  }
}

class IntegerField extends StatelessWidget {
  const IntegerField({super.key, required this.controller, required this.label, required this.min, this.validator, this.onChanged});

  final TextEditingController controller;
  final String label;
  final int min;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      validator: validator ?? (value) => integerValidator(value, min: min),
      onChanged: onChanged,
    );
  }
}

String? requiredText(String? value) => value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

String? integerValidator(String? value, {required int min}) {
  if (value == null || value.isEmpty) return 'Укажите значение';
  final parsed = int.tryParse(value);
  if (parsed == null) return 'Только целое число';
  if (parsed < min) return 'Минимум $min';
  return null;
}

void showErrorSnack(BuildContext context, Object error) {
  final text = error.toString().replaceFirst('Invalid argument(s): ', '').replaceFirst('Bad state: ', '');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<String?> showTextValueDialog(BuildContext context, String title, String label) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Добавить')),
      ],
    ),
  );
  controller.dispose();
  return result;
}
