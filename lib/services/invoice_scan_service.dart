import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';

class InvoiceScanResult {
  const InvoiceScanResult({
    required this.imagePath,
    required this.rawText,
    required this.lines,
  });

  final String imagePath;
  final String rawText;
  final List<InvoiceRecognizedLine> lines;
}

class InvoiceRecognizedLine {
  const InvoiceRecognizedLine({
    required this.sourceText,
    required this.product,
    required this.quantity,
    required this.confidence,
  });

  final String sourceText;
  final Product? product;
  final int quantity;
  final double confidence;

  bool get needsReview => product == null || confidence < .78;
}

class InvoiceScanService {
  InvoiceScanService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<InvoiceScanResult?> scanFromCamera(List<Product> products) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw UnsupportedError('Сканирование камерой доступно на Android и iPhone. На Windows используйте ручной ввод.');
    }
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return null;
    return _recognize(image.path, products);
  }

  Future<InvoiceScanResult?> scanFromGallery(List<Product> products) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw UnsupportedError('Распознавание изображения доступно на Android и iPhone. На Windows используйте ручной ввод.');
    }
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 96);
    if (image == null) return null;
    return _recognize(image.path, products);
  }

  Future<InvoiceScanResult> _recognize(String imagePath, List<Product> products) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      final sourceLines = <String>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final value = line.text.trim();
          if (value.isNotEmpty) sourceLines.add(value);
        }
      }
      final matched = _matchLines(sourceLines, products);
      return InvoiceScanResult(imagePath: imagePath, rawText: recognized.text, lines: matched);
    } finally {
      await recognizer.close();
    }
  }

  List<InvoiceRecognizedLine> _matchLines(List<String> sourceLines, List<Product> products) {
    final results = <InvoiceRecognizedLine>[];
    final seen = <int>{};

    for (var i = 0; i < sourceLines.length; i++) {
      final line = sourceLines[i];
      final context = [
        if (i > 0) sourceLines[i - 1],
        line,
        if (i + 1 < sourceLines.length) sourceLines[i + 1],
      ].join(' ');

      Product? best;
      var bestScore = 0.0;
      for (final product in products) {
        final score = _similarity(line, product);
        if (score > bestScore) {
          bestScore = score;
          best = product;
        }
      }
      if (best == null || bestScore < .48 || seen.contains(best.id)) continue;

      final quantity = _extractQuantity(context, best);
      if (quantity <= 0) continue;
      seen.add(best.id);
      results.add(
        InvoiceRecognizedLine(
          sourceText: line,
          product: best,
          quantity: quantity,
          confidence: bestScore,
        ),
      );
    }
    return results;
  }

  double _similarity(String source, Product product) {
    final a = _normalize(source);
    final b = _normalize(product.name);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.contains(b)) return .99;

    final productTokens = b.split(' ').where((e) => e.length >= 2).toSet();
    final sourceTokens = a.split(' ').where((e) => e.length >= 2).toSet();
    if (productTokens.isEmpty) return 0;
    final matched = productTokens.where(sourceTokens.contains).length;
    var score = matched / productTokens.length;

    final volumeHints = <String>{
      '${product.packageSize}',
      if (product.stockUnit == StockUnit.ml) (product.packageSize / 1000).toString().replaceAll('.', ','),
    };
    if (volumeHints.any(a.contains)) score += .08;
    return score.clamp(0, 1).toDouble();
  }

  int _extractQuantity(String context, Product product) {
    final normalized = context.toLowerCase().replaceAll(',', '.');
    final explicitPatterns = <RegExp>[
      RegExp(r'(?:кол(?:-?во)?|qty|quantity)\s*[:xх]?\s*(\d{1,3})', caseSensitive: false),
      RegExp(r'(\d{1,3})\s*(?:шт\.?|бут\.?|бутыл|pcs\b)', caseSensitive: false),
      RegExp(r'(?:x|х|×)\s*(\d{1,3})\b', caseSensitive: false),
    ];
    for (final pattern in explicitPatterns) {
      final match = pattern.firstMatch(normalized);
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value > 0 && value <= 500) return value;
    }

    final candidates = RegExp(r'\b\d{1,3}\b')
        .allMatches(normalized)
        .map((m) => int.tryParse(m.group(0) ?? ''))
        .whereType<int>()
        .where((v) => v > 0 && v <= 200)
        .where((v) => v != product.packageSize)
        .toList();
    if (candidates.isEmpty) return 0;
    return candidates.last;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('&', ' ')
        .replaceAll(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
