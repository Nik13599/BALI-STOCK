import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' hide Category;
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

  static Future<void> exportCurrentStock({required List<Category> categories, required List<Product> products}) async {
    final bytes = await buildCurrentStockPdf(categories: categories, products: products);
    await _saveOrShare(bytes, 'BALI-STOCK_ostatki_${_fileStamp(DateTime.now())}.pdf');
  }

  static Future<void> exportOperation(StockOperation operation) async {
    final bytes = await buildOperationPdf(operation);
    await _saveOrShare(bytes, 'BALI-STOCK_${_operationFileName(operation.type)}_${operation.id}_${_fileStamp(operation.createdAt)}.pdf');
  }

  static Future<void> exportPurchaseList({
    required List<PurchaseSuggestion> items,
    required List<StockSupplier> suppliers,
  }) async {
    final bytes = await buildPurchaseListPdf(items: items, suppliers: suppliers);
    await _saveOrShare(bytes, 'BALI-STOCK_zakupka_${_fileStamp(DateTime.now())}.pdf');
  }

  static Future<Uint8List> buildCurrentStockPdf({required List<Category> categories, required List<Product> products}) async {
    final theme = await _theme();
    final document = pw.Document(theme: theme);
    final generatedAt = DateTime.now();
    var usedCategories = 0;
    for (final category in categories) {
      if (products.any((product) => product.categoryId == category.id)) usedCategories++;
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
        header: (_) => _brandHeader('ТЕКУЩИЕ СКЛАДСКИЕ ОСТАТКИ'),
        footer: _footer,
        build: (_) {
          final widgets = <pw.Widget>[
            _metaBlock([
              'Сформировано: ${formatDateTime(generatedAt)}',
              'Позиций: ${products.length}',
              'Категорий: $usedCategories',
              'Расчётный остаток включает все проведённые поставки, списания и корректировки после последнего переучёта.',
            ]),
            pw.SizedBox(height: 12),
          ];
          for (final category in categories) {
            final items = products.where((product) => product.categoryId == category.id).toList(growable: false);
            if (items.isEmpty) continue;
            widgets.add(_categoryHeader(category.name, items.length));
            for (final product in items) {
              widgets.add(_stockProductRow(product));
            }
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
    final document = pw.Document(theme: theme);
    final title = '${operation.type.displayName.toUpperCase()} №${operation.id}';
    final grouped = <String, List<StockOperationLine>>{};
    for (final line in operation.lines) {
      grouped.putIfAbsent(line.categoryName, () => <StockOperationLine>[]).add(line);
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
        header: (_) => _brandHeader(title),
        footer: _footer,
        build: (_) {
          final meta = <String>[
            'Дата: ${formatDateTime(operation.createdAt)}',
            'Тип операции: ${operation.type.displayName}',
            'Позиций: ${operation.lines.length}',
          ];
          if (operation.employeeName?.trim().isNotEmpty == true) meta.add('Сотрудник: ${operation.employeeName}');
          if (operation.supplierName?.trim().isNotEmpty == true) meta.add('Поставщик: ${operation.supplierName}');
          if (operation.documentNumber?.trim().isNotEmpty == true) meta.add('Документ: ${operation.documentNumber}');
          if (operation.sourceLocationName?.trim().isNotEmpty == true) meta.add('Откуда: ${operation.sourceLocationName}');
          if (operation.targetLocationName?.trim().isNotEmpty == true) meta.add('Куда: ${operation.targetLocationName}');
          if (operation.correctionOf?.trim().isNotEmpty == true) meta.add('Корректирует операцию: ${operation.correctionOf}');
          if (operation.totalValue != null) meta.add('Сумма: ${formatMoney(operation.totalValue)}');
          if (operation.comment?.trim().isNotEmpty == true) meta.add('Комментарий: ${operation.comment}');
          if (operation.type == StockOperationType.stocktake) {
            if (operation.startedAt != null) meta.add('Начало: ${formatDateTime(operation.startedAt!)}');
            if (operation.completedAt != null) meta.add('Завершение: ${formatDateTime(operation.completedAt!)}');
            meta.add('Активное время: ${formatDurationSeconds(operation.activeSeconds)}');
            meta.add('Общий период: ${formatDurationSeconds(operation.totalSeconds)}');
          }
          final widgets = <pw.Widget>[
            _metaBlock(meta),
            pw.SizedBox(height: 8),
            pw.Text(
              'Исторический отчёт BALI STOCK. Проведённая операция не удаляется и не переписывается; исправления оформляются отдельной корректирующей операцией.',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.SizedBox(height: 12),
          ];
          for (final entry in grouped.entries) {
            widgets.add(_categoryHeader(entry.key, entry.value.length));
            for (final line in entry.value) {
              widgets.add(_operationRow(line, type: operation.type));
            }
            widgets.add(pw.SizedBox(height: 10));
          }
          return widgets;
        },
      ),
    );
    return document.save();
  }

  static Future<Uint8List> buildPurchaseListPdf({
    required List<PurchaseSuggestion> items,
    required List<StockSupplier> suppliers,
  }) async {
    final theme = await _theme();
    final document = pw.Document(theme: theme);
    final supplierNames = {for (final supplier in suppliers) supplier.id: supplier.name};
    final grouped = <String, List<PurchaseSuggestion>>{};
    for (final item in items) {
      final group = item.preferredSupplier == null ? 'ПОСТАВЩИК НЕ НАЗНАЧЕН' : (supplierNames[item.preferredSupplier] ?? 'ПОСТАВЩИК НЕ НАЙДЕН');
      grouped.putIfAbsent(group, () => []).add(item);
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
        header: (_) => _brandHeader('ЗАЯВКА НА ЗАКУПКУ'),
        footer: _footer,
        build: (_) {
          final widgets = <pw.Widget>[
            _metaBlock([
              'Сформировано: ${formatDateTime(DateTime.now())}',
              'Позиций к закупке: ${items.length}',
              'Рекомендуемое количество рассчитано от текущего остатка до целевого остатка; если цель не задана — до минимального.',
            ]),
            pw.SizedBox(height: 12),
          ];
          for (final entry in grouped.entries) {
            widgets.add(_categoryHeader(entry.key, entry.value.length));
            for (final item in entry.value) {
              final packages = item.stockUnit == StockUnit.piece ? item.suggestedQuantity : (item.suggestedQuantity / item.packageSize).ceil();
              final estimated = item.lastPrice == null ? null : item.lastPrice! * packages;
              widgets.add(
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E7E4'), width: .5))),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                          pw.Text(item.name, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                          pw.Text('${item.categoryName} • сейчас ${formatStockParts(item.currentQuantity, item.packageSize, item.stockUnit)}', style: pw.TextStyle(fontSize: 7.8, color: _muted)),
                        ]),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                          pw.Text('Заказать: $packages ${item.stockUnit.packageLabel}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          if (estimated != null) pw.Text('≈ ${formatMoney(estimated, item.currency)}', style: pw.TextStyle(fontSize: 7.8, color: _muted)),
                        ]),
                      ),
                    ],
                  ),
                ),
              );
            }
            widgets.add(pw.SizedBox(height: 10));
          }
          return widgets;
        },
      ),
    );
    return document.save();
  }

  static pw.Widget _brandHeader(String title) => pw.Container(
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

  static pw.Widget _metaBlock(List<String> lines) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        color: PdfColor.fromHex('#F5F8F6'),
        child: pw.Wrap(
          spacing: 18,
          runSpacing: 5,
          children: lines.map((line) => pw.Text(line, style: const pw.TextStyle(fontSize: 9.5))).toList(growable: false),
        ),
      );

  static pw.Widget _categoryHeader(String name, int count) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 5, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        color: _lightGreen,
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _green))),
            pw.Text('$count поз.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green)),
          ],
        ),
      );

  static pw.Widget _stockProductRow(Product product) {
    final stock = product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'Остаток не введён';
    final package = product.stockUnit == StockUnit.piece ? 'поштучно' : formatPackageSize(product.packageSize, product.stockUnit);
    final status = !product.stockInitialized ? 'не пересчитано' : product.isLow ? 'критический остаток' : 'норма';
    final target = product.targetAmount > 0 ? ' • цель ${formatMinimumAmount(product.targetAmount, product.stockUnit)}' : '';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E7E4'), width: .5))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(product.name, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              pw.Text('$package • минимум ${formatMinimumAmount(product.minimumAmount, product.stockUnit)}$target', style: pw.TextStyle(fontSize: 7.8, color: _muted)),
            ]),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 4,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(stock, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9.2, fontWeight: pw.FontWeight.bold)),
              pw.Text(status, style: pw.TextStyle(fontSize: 7.5, color: product.isLow ? PdfColors.red700 : _muted)),
              if (product.defaultCost != null) pw.Text('цена ${formatMoney(product.defaultCost, product.costCurrency)}', style: pw.TextStyle(fontSize: 7.5, color: _muted)),
            ]),
          ),
        ],
      ),
    );
  }

  static pw.Widget _operationRow(StockOperationLine line, {required StockOperationType type}) {
    final initialBalance = !line.beforeInitialized && (type == StockOperationType.stocktake || type == StockOperationType.spotStocktake);
    final change = line.changeTotalMl;
    final signedChange = '${change >= 0 ? '+' : '−'}${formatTotalAmount(change.abs(), line.stockUnit)}';
    final package = line.stockUnit == StockUnit.piece ? 'поштучно' : formatPackageSize(line.bottleMl, line.stockUnit);
    final before = initialBalance ? 'остаток не был задан' : formatStockParts(line.beforeTotalMl, line.bottleMl, line.stockUnit);
    final after = formatStockParts(line.afterTotalMl, line.bottleMl, line.stockUnit);
    final middle = switch (type) {
      StockOperationType.delivery => 'Принято: $signedChange',
      StockOperationType.stocktake => initialBalance ? 'Первичный остаток: $after' : 'Расхождение: $signedChange',
      StockOperationType.spotStocktake => initialBalance ? 'Первичный точечный остаток: $after' : 'Точечное расхождение: $signedChange',
      StockOperationType.writeoff => 'Списано: $signedChange',
      StockOperationType.transfer => 'Перемещено: ${formatTotalAmount(change.abs(), line.stockUnit)}',
      StockOperationType.correction => 'Коррекция: $signedChange',
    };
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E7E4'), width: .5))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          pw.Expanded(child: pw.Text(line.productName, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
          pw.Text(package, style: pw.TextStyle(fontSize: 8, color: _muted)),
        ]),
        pw.SizedBox(height: 3),
        pw.Wrap(spacing: 12, runSpacing: 3, children: [
          if (type != StockOperationType.transfer) pw.Text('Было: $before', style: const pw.TextStyle(fontSize: 8)),
          pw.Text(middle, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: change < 0 ? PdfColors.red700 : _green)),
          if (!initialBalance && type != StockOperationType.transfer) pw.Text('Стало: $after', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          if (line.unitCost != null) pw.Text('Цена: ${formatMoney(line.unitCost)}', style: const pw.TextStyle(fontSize: 8)),
          if (line.lineValue != null) pw.Text('Сумма: ${formatMoney(line.lineValue)}', style: const pw.TextStyle(fontSize: 8)),
        ]),
        if (line.comment?.trim().isNotEmpty == true) ...[
          pw.SizedBox(height: 3),
          pw.Text('Комментарий: ${line.comment}', style: pw.TextStyle(fontSize: 7.8, color: _muted)),
        ],
      ]),
    );
  }

  static pw.Widget _footer(pw.Context context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('BALI STOCK • страница ${context.pageNumber} из ${context.pagesCount}', style: pw.TextStyle(fontSize: 7.5, color: _muted)),
      );

  static Future<pw.ThemeData> _theme() => _themeFuture ??= _loadTheme();

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
      await XFile.fromData(bytes, mimeType: 'application/pdf', name: filename).saveTo(location.path);
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static String _operationFileName(StockOperationType type) => switch (type) {
        StockOperationType.delivery => 'postavka',
        StockOperationType.stocktake => 'pereuchet',
        StockOperationType.spotStocktake => 'tochechniy_pereuchet',
        StockOperationType.writeoff => 'spisanie',
        StockOperationType.transfer => 'peremeshenie',
        StockOperationType.correction => 'korrektirovka',
      };

  static String _fileStamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}';
  }
}
