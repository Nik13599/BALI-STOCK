import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceInputService {
  VoiceInputService._();

  static final VoiceInputService instance = VoiceInputService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _initializing = false;
  Completer<bool>? _initializeCompleter;
  Completer<String?>? _activeCompleter;
  String _lastWords = '';
  String? _russianLocale;

  bool get isListening => _speech.isListening;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    if (_initializing) return _initializeCompleter!.future;

    _initializing = true;
    _initializeCompleter = Completer<bool>();
    try {
      _initialized = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
      if (_initialized) {
        final locales = await _speech.locales();
        for (final locale in locales) {
          final id = locale.localeId.toLowerCase();
          if (id == 'ru_ru' || id == 'ru-ru' || id.startsWith('ru_') || id.startsWith('ru-')) {
            _russianLocale = locale.localeId;
            break;
          }
        }
      }
      _initializeCompleter?.complete(_initialized);
      return _initialized;
    } catch (_) {
      _initialized = false;
      if (!(_initializeCompleter?.isCompleted ?? true)) _initializeCompleter?.complete(false);
      return false;
    } finally {
      _initializing = false;
    }
  }

  Future<String?> dictate({Duration timeout = const Duration(seconds: 25)}) async {
    if (!await _ensureInitialized()) return null;

    if (_activeCompleter != null && !(_activeCompleter?.isCompleted ?? true)) {
      await cancel();
    }

    _lastWords = '';
    final completer = Completer<String?>();
    _activeCompleter = completer;

    try {
      await _speech.listen(
        onResult: _onResult,
        localeId: _russianLocale,
        listenFor: timeout,
        pauseFor: const Duration(seconds: 4),
      );
    } catch (_) {
      _finish(null);
    }

    return completer.future.timeout(
      timeout + const Duration(seconds: 5),
      onTimeout: () {
        _speech.stop();
        _finish(_lastWords.trim().isEmpty ? null : _lastWords.trim());
        return _lastWords.trim().isEmpty ? null : _lastWords.trim();
      },
    );
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } finally {
      _finish(_lastWords.trim().isEmpty ? null : _lastWords.trim());
    }
  }

  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } finally {
      _finish(null);
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    _lastWords = result.recognizedWords;
    if (result.finalResult) _finish(_lastWords.trim().isEmpty ? null : _lastWords.trim());
  }

  void _onStatus(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'done' || normalized == 'notlistening') {
      _finish(_lastWords.trim().isEmpty ? null : _lastWords.trim());
    }
  }

  void _onError(SpeechRecognitionError error) {
    _finish(_lastWords.trim().isEmpty ? null : _lastWords.trim());
  }

  void _finish(String? value) {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(value);
    _activeCompleter = null;
  }
}
