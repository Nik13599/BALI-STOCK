import 'dart:math' as math;

import '../models.dart';
import 'invoice_recognition_service.dart' as legacy;

class InvoiceNotRecognizedException implements Exception {
  const InvoiceNotRecognizedException();

  @override
  String toString() => 'Накладная не распознана. Загрузите оригинальную накладную.';
}

class InvoiceRecognitionV15Result {
  const InvoiceRecognitionV15Result({
    required this.rawText,
    required this.lines,
    required this.unmatchedLines,
    required this.documentConfidence,
    this.supplierId,
    this.supplierText,
    this.documentNumber,
    this.documentDate,
  });

  final String rawText;
  final List<InvoiceRecognitionLine> lines;
  final List<String> unmatchedLines;
  final double documentConfidence;
  final String? supplierId;
  final String? supplierText;
  final String? documentNumber;
  final DateTime? documentDate;
}

class InvoiceRecognitionServiceV15 {
  final legacy.InvoiceRecognitionService _legacy = legacy.InvoiceRecognitionService();

  Future<InvoiceRecognitionV15Result> recognize({
    required String imagePath,
    required List<Product> products,
    List<ProductSupplierLink> supplierLinks = const [],
    List<StockSupplier> suppliers = const [],
  }) async {
    if (products.isEmpty) throw StateError('В складе нет позиций для сопоставления с накладной.');
    final rawText = await _legacy.extractText(imagePath);
    if (rawText.trim().isEmpty) throw const InvoiceNotRecognizedException();

    final validation = _validateInvoice(rawText, products);
    if (!validation.accepted) throw const InvoiceNotRecognizedException();

    final parsed = _legacy.parseText(rawText, products: products, supplierLinks: supplierLinks);
    final enriched = parsed.lines.map((line) => _enrichLine(line, rawText)).toList(growable: false);
    final plausible = enriched.where((line) => line.quantityBase > 0 && line.confidence >= .50).toList(growable: false);
    if (plausible.isEmpty) throw const InvoiceNotRecognizedException();

    final supplierMatch = _detectSupplier(rawText, suppliers);
    return InvoiceRecognitionV15Result(
      rawText: rawText,
      lines: plausible,
      unmatchedLines: parsed.unmatchedLines,
      documentConfidence: validation.confidence,
      supplierId: supplierMatch?.id,
      supplierText: supplierMatch?.name ?? _extractSupplierText(rawText),
      documentNumber: _extractDocumentNumber(rawText),
      documentDate: _extractDocumentDate(rawText),
    );
  }

  _DocumentValidation _validateInvoice(String rawText, List<Product> products) {
    final text = _normalize(rawText);
    final docTerms = [
      'товарно транспортная накладная',
      'товарная накладная',
      'накладная',
      'ттн',
      'тн 2',
      'тн2',
      'invoice',
      'счет фактура',
    ];
    final tableTerms = ['наименование', 'количество', 'кол во', 'цена', 'сумма', 'ед изм', 'единица измерения'];
    final businessTerms = ['поставщик', 'грузоотправитель', 'получатель', 'покупатель', 'унп', 'реквизиты'];
    final totalTerms = ['итого', 'всего', 'ндс', 'сумма с ндс'];

    final hasDoc = docTerms.any(text.contains);
    final tableCount = tableTerms.where(text.contains).length;
    final businessCount = businessTerms.where(text.contains).length;
    final totalCount = totalTerms.where(text.contains).length;
    final hasDate = RegExp(r'\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b').hasMatch(rawText);
    final hasNumber = RegExp(r'(?:№|no\.?|номер|накладн\w*|ттн|тн)\s*[:#№-]?\s*[a-zа-я0-9/-]{2,}', caseSensitive: false, unicode: true).hasMatch(rawText);

    var productHits = 0;
    for (final product in products) {
      final name = _normalize(product.name);
      if (name.length >= 4 && text.contains(name)) {
        productHits++;
        if (productHits >= 3) break;
      }
    }

    var score = 0.0;
    if (hasDoc) score += 4.0;
    score += math.min(tableCount, 4) * 1.05;
    score += math.min(businessCount, 3) * .9;
    score += math.min(totalCount, 2) * .55;
    if (hasDate) score += .55;
    if (hasNumber) score += .55;
    score += productHits * .7;

    final structurallyInvoice = hasDoc
        ? (tableCount >= 1 || businessCount >= 1 || productHits >= 1)
        : (tableCount >= 3 && businessCount >= 1 && (hasDate || hasNumber || totalCount >= 1));
    final accepted = structurallyInvoice && score >= 5.5;
    return _DocumentValidation(accepted: accepted, confidence: (score / 10).clamp(0.0, 1.0));
  }

  InvoiceRecognitionLine _enrichLine(InvoiceRecognitionLine line, String rawText) {
    final cost = _bestUnitCost(rawText, line.sourceText, line.packages, line.unitCost);
    var confidence = line.confidence;
    if (cost != null && line.unitCost == null) confidence = math.min(1.0, confidence + .04);
    return InvoiceRecognitionLine(
      sourceText: line.sourceText,
      product: line.product,
      quantityBase: line.quantityBase,
      packages: line.packages,
      extraAmount: line.extraAmount,
      confidence: confidence,
      unitCost: cost,
    );
  }

  double? _bestUnitCost(String rawText, String sourceText, int packages, double? fallback) {
    final lines = rawText.replaceAll('\r', '\n').split('\n').map((x) => x.replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
    var index = lines.indexWhere((x) => x == sourceText);
    if (index < 0) {
      final wanted = _normalize(sourceText);
      index = lines.indexWhere((x) => _normalize(x).contains(wanted) || wanted.contains(_normalize(x)));
    }
    final candidates = <double>[];
    if (index >= 0) {
      for (var i = index; i <= math.min(index + 1, lines.length - 1); i++) {
        candidates.addAll(_moneyValues(lines[i]));
      }
    }
    if (candidates.isEmpty) return fallback;
    if (packages > 0 && candidates.length >= 2) {
      for (var i = 0; i < candidates.length; i++) {
        for (var j = i + 1; j < candidates.length; j++) {
          final a = candidates[i];
          final b = candidates[j];
          if (_approximately(a * packages, b)) return a;
          if (_approximately(b * packages, a)) return b;
        }
      }
    }
    if (fallback != null && candidates.any((x) => (x - fallback).abs() < .01)) return fallback;
    return fallback ?? candidates.first;
  }

  List<double> _moneyValues(String value) => RegExp(r'(?<!\d)(\d{1,7}[.,]\d{2,4})(?!\d)')
      .allMatches(value)
      .map((m) => double.tryParse(m.group(1)!.replaceAll(',', '.')))
      .whereType<double>()
      .where((x) => x > .01 && x < 1000000)
      .toList(growable: false);

  bool _approximately(double expected, double actual) {
    if (actual == 0) return false;
    return (expected - actual).abs() / actual.abs() <= .06;
  }

  StockSupplier? _detectSupplier(String rawText, List<StockSupplier> suppliers) {
    final text = _normalize(rawText);
    StockSupplier? best;
    var bestScore = 0.0;
    for (final supplier in suppliers.where((x) => x.active)) {
      final name = _normalize(supplier.name);
      if (name.isEmpty) continue;
      if (text.contains(name)) return supplier;
      final tokens = name.split(' ').where((x) => x.length > 2).toSet();
      if (tokens.isEmpty) continue;
      final hits = tokens.where(text.contains).length;
      final score = hits / tokens.length;
      if (score > bestScore && score >= .66) {
        best = supplier;
        bestScore = score;
      }
    }
    return best;
  }

  String? _extractSupplierText(String rawText) {
    final lines = rawText.replaceAll('\r', '\n').split('\n').map((x) => x.replaceAll(RegExp(r'\s+'), ' ').trim()).where((x) => x.isNotEmpty);
    for (final line in lines) {
      final match = RegExp(r'(?:поставщик|грузоотправитель)\s*[:\-]?\s*(.{3,80})$', caseSensitive: false, unicode: true).firstMatch(line);
      if (match != null) {
        final value = match.group(1)?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String? _extractDocumentNumber(String rawText) {
    final patterns = [
      RegExp(r'(?:ттн|тн|накладн\w*|invoice)\s*(?:№|no\.?|номер)?\s*[:#№-]?\s*([a-zа-я0-9][a-zа-я0-9/\-.]{1,23})', caseSensitive: false, unicode: true),
      RegExp(r'(?:№|no\.?|номер)\s*[:#№-]?\s*([a-zа-я0-9][a-zа-я0-9/\-.]{1,23})', caseSensitive: false, unicode: true),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(rawText);
      final value = match?.group(1)?.trim();
      if (value != null && value.length >= 2 && !RegExp(r'^\d{1,2}[./-]\d{1,2}').hasMatch(value)) return value;
    }
    return null;
  }

  DateTime? _extractDocumentDate(String rawText) {
    final matches = RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b').allMatches(rawText);
    for (final match in matches) {
      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      var year = int.tryParse(match.group(3)!);
      if (day == null || month == null || year == null) continue;
      if (year < 100) year += 2000;
      if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) continue;
      try {
        final date = DateTime(year, month, day);
        if (date.day == day && date.month == month) return date;
      } catch (_) {}
    }
    return null;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _DocumentValidation {
  const _DocumentValidation({required this.accepted, required this.confidence});
  final bool accepted;
  final double confidence;
}
