import 'package:flutter/material.dart';

import '../services/voice_input_service.dart';

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.controller,
    this.append = false,
    this.tooltip = 'Речевой ввод',
    this.onApplied,
  });

  final TextEditingController controller;
  final bool append;
  final String tooltip;
  final VoidCallback? onApplied;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  bool _listening = false;

  Future<void> _dictate() async {
    if (_listening) {
      await VoiceInputService.instance.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() => _listening = true);
    try {
      final text = await VoiceInputService.instance.dictate();
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Речь не распознана. Проверьте доступ к микрофону и повторите.')),
        );
        return;
      }

      final recognized = text.trim();
      if (widget.append && widget.controller.text.trim().isNotEmpty) {
        widget.controller.text = '${widget.controller.text.trim()} $recognized';
      } else {
        widget.controller.text = recognized;
      }
      widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
      widget.onApplied?.call();
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening ? 'Остановить распознавание' : widget.tooltip,
      onPressed: _dictate,
      icon: _listening
          ? const Icon(Icons.mic, color: Color(0xFF39FF6A))
          : const Icon(Icons.mic_none_outlined),
    );
  }
}
