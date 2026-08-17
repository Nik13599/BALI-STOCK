import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models.dart';

class PdfExportService {
  PdfExportService._();

  static final PdfColor _green = PdfColor.fromHex('#159447');
  static final PdfColor _lightGreen = PdfColor.fromHex('#EAF7EF');
  static final PdfColor _muted = PdfColor.fromHex('#66736B');
  static Future<pw.ThemeData>? _themeFuture;

  static Future<void> exportCurrentStock({
    required List<Category> categories,
    required List<Product> products,
  }) async {
    final bytes = await buildCurrentStockPdf(categories: categories, products: products);
    await _saveOrShare(bytes, 'BALI-STOCK_ostatki_${_fileStamp(DateTime.now())}.pdf');
  }

  static Future<void> exportOperation(StockOperation operation) async {
    final bytes = await buildOperationPdf(operation);
    final kind = operation.type == StockOperationType.delivery ? 'postavka' : 'pereuchet';
    await _saveOrShare(bytes, 'BALI-STOCK_${kind}_${operation.id}_${_fileStamp(operation.createdAt)}.pdf');
  }

  static Future<Uint8List> buildCurrentStockPdf({
    required List<Category> categories,
    required List<Product> products,
  }) async {
    final theme = await _theme();
    final document = pw.Document();
    final generatedAt = DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
        theme: theme,
        header: (_) => _brandHeader('ТЕКУЩИЕ СКЛАДСКИЕ ОСТАТКИ'),
        footer: _footer,
        build: (_) {
          final widgets = <pw.Widget>[
            _metaBlock([
              'Сформировано: ${formatDateTime(generatedAt)}',
              'Позиций: ${products.length}',
              'Категорий: ${categories.where((c) => products.any((p) => p.categoryId == c.id)).length}',
            ]),
            pw.SizedBox(height: 12),
          ];

          for (final category in categories) {
            final items = products.where((p) => p.categoryId == category.id).toList(growable: false);
            if (items.isEmpty) continue;
            widgets.add(_categoryHeader(category.name, items.length));
            widgets.addAll(items.map(_stockProductRow));
            widgets.add(pw.SizedBox(height: 10));
          }
          return widgets;
        },
      ),
    );

    return document.save();
  }

  static Future<Uint8List> buildOperationPdf(StockOperation operation) async {
    final theme = await _theme();
    final document = pw.Document();
    final delivery = operation.type == StockOperationType.delivery;
    final title = delivery ? 'ПОСТАВКА №${operation.id}' : 'ПЕРЕУЧЁТ №${operation.id}';

    final grouped = <String, List<StockOperationLine>>{};
    for (final line in operation.lines) {
      grouped.putIfAbsent(line.categoryName, () => <StockOperationLine>[]).add(line);
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
        theme: theme,
        header: (_) => _brandHeader(title),
        footer: _footer,
        build: (_) {
          final meta = <String>[
            'Дата: ${formatDateTime(operation.createdAt)}',
            'Позиций: ${operation.lines.length}',
          ];
          if (operation.employeeName?.trim().isNotEmpty == true) {
            meta.add('Сотрудник: ${operation.employeeName}');
          }
          if (!delivery) {
            if (operation.startedAt != null) meta.add('Начало: ${formatDateTime(operation.startedAt!)}');
            if (operation.completedAt != null) meta.add('Завершение: ${formatDateTime(operation.completedAt!)}');
            meta.add('Активное время: ${formatDurationSeconds(operation.activeSeconds)}');
            meta.add('Общий период: ${formatDurationSeconds(operation.totalSeconds)}');
          }

          final widgets = <pw.Widget>[
            _metaBlock(meta),
            pw.SizedBox(height: 12),
          ];
          for (final entry in grouped.entries) {
            widgets.add(_categoryHeader(entry.key, entry.value.length));
            widgets.addAll(entry.value.map((line) => _operationRow(line, delivery: delivery)));
            widgets.add(pw.SizedBox(height: 10));
          }
          return widgets;
        },
      ),
    );

    return document.save();
  }

  static pw.Widget _brandHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _green, width: 2))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('BALI STOCK', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _green)),
          pw.Spacer(),
          pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _metaBlock(List<String> lines) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F5F8F6'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Wrap(
        spacing: 18,
        runSpacing: 5,
        children: lines.map((line) => pw.Text(line, style: const pw.TextStyle(fontSize: 9.5))).toList(growable: false),
      ),
    );
  }

  static pw.Widget _categoryHeader(String name, int count) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 5, bottom: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(color: _lightGreen, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              name.toUpperCase(),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _green),
            ),
          ),
          pw.Text('$count поз.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green)),
        ],
      ),
    );
  }

  static pw.Widget _stockProductRow(Product product) {
    final stock = product.stockInitialized
        ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit)
        : 'Остаток не введён';
    final status = !product.stockInitialized
        ? 'не пересчитано'
        : product.isLow
            ? 'критический остаток'
            : 'норма';
    final package = product.stockUnit == StockUnit.piece ? 'поштучно' : formatPackageSize(product.packageSize, product.stockUnit);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E7E4'), width: .5))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(product.name, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                pw.Text('$package • минимум ${formatMinimumAmount(product.minimumAmount, product.stockUnit)}', style: pw.TextStyle(fontSize: 7.8, color: _muted)),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(stock, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9.2, fontWeight: pw.FontWeight.bold)),
                pw.Text(status, style: pw.TextStyle(fontSize: 7.5, color: product.isLow ? PdfColors.red700 : _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _operationRow(StockOperationLine line, {required bool delivery}) {
    final initialBalance = !line.beforeInitialized && !delivery;
    final change = line.changeTotalMl;
    final signedChange = '${change >= 0 ? '+' : '−'}${formatTotalAmount(change.abs(), line.stockUnit)}';
    final package = line.stockUnit == StockUnit.piece ? 'поштучно' : formatPackageSize(line.bottleMl, line.stockUnit);
    final before = initialBalance ? 'остаток не был задан' : formatStockParts(line.beforeTotalMl, line.bottleMl, line.stockUnit);
    final after = formatStockParts(line.afterTotalMl, line.bottleMl, line.stockUnit);
    final middle = initialBalance
        ? 'Первичный остаток: $after'
        : delivery
            ? 'Принято: $signedChange'
            : 'Расхождение: $signedChange';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E7E4'), width: .5))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text(line.productName, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
              pw.Text(package, style: pw.TextStyle(fontSize: 8, color: _muted)),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              pw.Text('Было: $before', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(middle, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: change < 0 ? PdfColors.red700 : _green)),
              if (!initialBalance) pw.Text('Стало: $after', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'BALI STOCK • страница ${context.pageNumber} из ${context.pagesCount}',
        style: pw.TextStyle(fontSize: 7.5, color: _muted),
      ),
    );
  }

  static Future<pw.ThemeData> _theme() {
    return _themeFuture ??= _loadTheme();
  }

  static Future<pw.ThemeData> _loadTheme() async {
    final regular = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static Future<void> _saveOrShare(Uint8List bytes, String filename) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final location = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [XTypeGroup(label: 'PDF', extensions: ['pdf'])],
      );
      if (location == null) return;
      final file = XFile.fromData(bytes, mimeType: 'application/pdf', name: filename);
      await file.saveTo(location.path);
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static String _fileStamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}';
  }
}
