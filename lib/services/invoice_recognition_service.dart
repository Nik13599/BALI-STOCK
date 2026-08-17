import 'dart:io';
import 'dart:math' as math;

import 'package:flusseract/flusseract.dart' as tess;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models.dart';

class InvoiceRecognitionResult {
  const InvoiceRecognitionResult({
    required this.rawText,
    required this.lines,
    required this.unmatchedLines,
  });

  final String rawText;
  final List<InvoiceRecognitionLine> lines;
  final List<String> unmatchedLines;
}

class InvoiceRecognitionService {
  static const _languages = ['rus', 'eng'];
  static const _modelBase = 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main';

  Future<InvoiceRecognitionResult> recognize({
    required String imagePath,
    required List<Product> products,
    List<ProductSupplierLink> supplierLinks = const [],
  }) async {
    if (products.isEmpty) throw StateError('В складе нет позиций для сопоставления с накладной.');
    final text = await extractText(imagePath);
    if (text.trim().isEmpty) throw StateError('На накладной не удалось распознать текст. Попробуйте сфотографировать документ ровнее и при хорошем освещении.');
    return parseText(text, products: products, supplierLinks: supplierLinks);
  }

  Future<String> extractText(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) throw StateError('Файл накладной не найден.');
    final tessDataPath = await _ensureModels();
    final engine = tess.Tesseract(
      languages: _languages,
      tessDataPath: tessDataPath,
      pageSegMode: tess.PageSegMode.auto,
    );
    try {
      engine.setVariable('preserve_interword_spaces', '1');
      return await engine.processDocument(imagePath);
    } finally {
      engine.dispose();
    }
  }

  Future<String> _ensureModels() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'bali_stock_tessdata'));
    if (!await directory.exists()) await directory.create(recursive: true);
    for (final language in _languages) {
      final target = File(p.join(directory.path, '$language.traineddata'));
      if (await target.exists() && await target.length() > 100000) continue;
      final response = await http.get(Uri.parse('$_modelBase/$language.traineddata')).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.length < 100000) {
        throw StateError('Не удалось загрузить OCR-модель $language. Проверьте интернет и повторите сканирование.');
      }
      await target.writeAsBytes(response.bodyBytes, flush: true);
    }
    return directory.path;
  }

  InvoiceRecognitionResult parseText(
    String rawText, {
    required List<Product> products,
    List<ProductSupplierLink> supplierLinks = const [],
  }) {
    final sourceLines = rawText
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.length >= 2)
        .toList(growable: false);
    final used = <int>{};
    final recognized = <InvoiceRecognitionLine>[];

    for (final product in products.where((product) => product.active)) {
      var bestIndex = -1;
      var bestScore = 0.0;
      for (var i = 0; i < sourceLines.length; i++) {
        if (used.contains(i)) continue;
        final score = _nameScore(product.name, sourceLines[i]);
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }
      if (bestIndex < 0 || bestScore < 0.50) continue;
      final candidates = <String>[
        if (bestIndex > 0) sourceLines[bestIndex - 1],
        sourceLines[bestIndex],
        if (bestIndex + 1 < sourceLines.length) sourceLines[bestIndex + 1],
      ];
      final quantity = _extractQuantity(product, candidates);
      if (quantity == null || quantity.quantityBase <= 0) continue;
      used.add(bestIndex);
      recognized.add(InvoiceRecognitionLine(
        sourceText: sourceLines[bestIndex],
        product: product,
        quantityBase: quantity.quantityBase,
        packages: quantity.packages,
        extraAmount: quantity.extraAmount,
        confidence: (bestScore * 0.72 + quantity.confidence * 0.28).clamp(0.0, 1.0),
        unitCost: _extractUnitCost(sourceLines[bestIndex], product),
      ));
    }

    recognized.sort((a, b) {
      final category = a.product.categoryName.compareTo(b.product.categoryName);
      return category == 0 ? a.product.name.compareTo(b.product.name) : category;
    });
    final unmatched = <String>[];
    for (var i = 0; i < sourceLines.length; i++) {
      if (!used.contains(i) && !_looksLikeHeader(sourceLines[i])) unmatched.add(sourceLines[i]);
    }
    return InvoiceRecognitionResult(rawText: rawText, lines: recognized, unmatchedLines: unmatched);
  }

  _QuantityGuess? _extractQuantity(Product product, List<String> lines) {
    final joined = lines.join(' | ').toLowerCase().replaceAll('х', 'x');

    // Explicit package / piece count is the safest signal in supplier invoices.
    final explicit = RegExp(r'(?:кол-?во|количество|qty|quantity)?\s*[:=]?\s*(\d{1,4}(?:[.,]\d+)?)\s*(?:x\s*)?(шт\.?|штук|бут\.?|бутыл(?:ка|ки|ок)?|уп\.?|упак(?:овка|овки|овок)?|pcs?|btl)', caseSensitive: false)
        .allMatches(joined)
        .toList();
    for (final match in explicit.reversed) {
      final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
      if (value == null || value <= 0 || value > 10000) continue;
      final packages = value.round();
      final base = product.stockUnit == StockUnit.piece ? packages : packages * product.packageSize;
      return _QuantityGuess(base, packages, 0, 0.98);
    }

    // Direct base units, useful for ingredients supplied by weight/volume.
    final direct = RegExp(r'(\d{1,7}(?:[.,]\d+)?)\s*(мл|ml|л|l|г|gr|g|кг|kg)\b', caseSensitive: false).allMatches(joined).toList();
    for (final match in direct.reversed) {
      final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
      if (value == null || value <= 0) continue;
      final unit = match.group(2)!.toLowerCase();
      int base;
      if (unit == 'л' || unit == 'l') {
        base = (value * 1000).round();
      } else if (unit == 'кг' || unit == 'kg') {
        base = (value * 1000).round();
      } else {
        base = value.round();
      }
      if (product.stockUnit == StockUnit.piece) continue;
      final packages = base ~/ product.packageSize;
      final extra = base % product.packageSize;
      return _QuantityGuess(base, packages, extra, 0.90);
    }

    // Fallback: infer a likely quantity column from integers, while excluding
    // the package size (700/750/1000 etc.) and numbers embedded in the SKU name.
    final productNumbers = RegExp(r'\d+').allMatches(product.name).map((m) => int.tryParse(m.group(0)!)).whereType<int>().toSet();
    final numbers = RegExp(r'(?<![.,\d])(\d{1,4})(?![.,\d])').allMatches(joined).map((m) => int.tryParse(m.group(1)!)).whereType<int>().toList();
    for (final value in numbers.reversed) {
      if (value <= 0 || value > 500) continue;
      if (value == product.packageSize || productNumbers.contains(value)) continue;
      final base = product.stockUnit == StockUnit.piece ? value : value * product.packageSize;
      return _QuantityGuess(base, value, 0, 0.63);
    }
    return null;
  }

  double? _extractUnitCost(String line, Product product) {
    final values = RegExp(r'(?<!\d)(\d{1,6}[.,]\d{2})(?!\d)')
        .allMatches(line)
        .map((match) => double.tryParse(match.group(1)!.replaceAll(',', '.')))
        .whereType<double>()
        .where((value) => value > 0.01 && value < 100000)
        .toList();
    if (values.isEmpty) return null;
    // On most invoices the first decimal after the item/quantity is the unit price.
    return values.first;
  }

  double _nameScore(String productName, String line) {
    final a = _normalize(productName);
    final b = _normalize(line);
    if (a.isEmpty || b.isEmpty) return 0;
    if (b.contains(a)) return 1.0;
    final aTokens = a.split(' ').where((e) => e.length > 1).toSet();
    final bTokens = b.split(' ').where((e) => e.length > 1).toSet();
    final common = aTokens.intersection(bTokens).length;
    final tokenScore = aTokens.isEmpty ? 0.0 : common / aTokens.length;
    final compactA = a.replaceAll(' ', '');
    final compactB = b.replaceAll(' ', '');
    final distance = _levenshtein(compactA, compactB.length > compactA.length * 2 ? _bestWindow(compactA, compactB) : compactB);
    final maxLen = math.max(compactA.length, compactB.length).clamp(1, 10000);
    final editScore = 1 - distance / maxLen;
    return (tokenScore * 0.65 + editScore.clamp(0.0, 1.0) * 0.35).clamp(0.0, 1.0);
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('’', "'")
      .replaceAll('`', "'")
      .replaceAll(RegExp(r'[^a-zа-я0-9]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _bestWindow(String needle, String haystack) {
    if (haystack.length <= needle.length) return haystack;
    var best = haystack.substring(0, needle.length);
    var bestDistance = _levenshtein(needle, best);
    final step = math.max(1, needle.length ~/ 4);
    for (var start = 0; start + needle.length <= haystack.length; start += step) {
      final candidate = haystack.substring(start, start + needle.length);
      final distance = _levenshtein(needle, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final insert = current[j] + 1;
        final delete = previous[j + 1] + 1;
        final replace = previous[j] + (a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1);
        current[j + 1] = math.min(insert, math.min(delete, replace));
      }
      previous = current;
    }
    return previous.last;
  }

  bool _looksLikeHeader(String value) {
    final normalized = _normalize(value);
    const words = ['накладная', 'поставщик', 'покупатель', 'итого', 'сумма', 'ндс', 'количество', 'цена', 'наименование', 'товар'];
    return words.any(normalized.contains) || RegExp(r'^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}$').hasMatch(normalized);
  }
}

class _QuantityGuess {
  const _QuantityGuess(this.quantityBase, this.packages, this.extraAmount, this.confidence);

  final int quantityBase;
  final int packages;
  final int extraAmount;
  final double confidence;
}
