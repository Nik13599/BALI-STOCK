import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controller.dart';
import '../models.dart';
import '../services/invoice_recognition_service.dart';
import '../services/pdf_export_service.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';
import '../widgets/product_code_actions.dart';
import '../widgets/voice_input_button.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final Map<int, DeliveryDraftLine> _lines = {};
  final _employee = TextEditingController();
  final _document = TextEditingController();
  final _comment = TextEditingController();
  final _productSearch = TextEditingController();
  final _recognizer = InvoiceRecognitionService();
  bool _saving = false;
  bool _recognizing = false;
  String? _supplierId;
  String? _locationId;
  String? _invoicePath;
  String? _rawOcrText;

  @override
  void initState() {
    super.initState();
    _productSearch.addListener(_refreshProductSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _locationId = widget.controller.primaryLocation?.id);
    });
  }

  @override
  void dispose() {
    _productSearch.removeListener(_refreshProductSearch);
    _employee.dispose();
    _document.dispose();
    _comment.dispose();
    _productSearch.dispose();
    super.dispose();
  }

  void _refreshProductSearch() {
    if (mounted) setState(() {});
  }

  Future<void> _addLine([DeliveryDraftLine? initial, Product? preselectedProduct, bool scanWorkflow = false]) async {
    final line = await showDeliveryLineDialog(
      context,
      widget.controller.products,
      initial: initial,
      preselectedProduct: preselectedProduct,
      scanWorkflow: scanWorkflow,
    );
    if (line == null || !mounted) return;
    setState(() => _lines[line.product.id] = line);
  }

  Future<void> _manualProductCode() async {
    final code = await enterProductCode(context);
    if (!mounted || code == null) return;
    final product = findProductByCode(widget.controller.products, code);
    if (product == null) {
      showErrorSnack(context, 'Код товара ${code.trim()} не привязан ни к одной позиции.');
      return;
    }
    await _addLine(_lines[product.id], product);
  }

  Future<void> _scanProductWorkflow() async {
    while (mounted) {
      final code = await scanProductCode(context);
      if (!mounted || code == null) return;
      final product = findProductByCode(widget.controller.products, code);
      if (product == null) {
        showErrorSnack(context, 'Код товара ${code.trim()} не привязан ни к одной позиции. Сканируйте следующий товар или закройте сканер.');
        continue;
      }
      final before = _lines[product.id];
      final line = await showDeliveryLineDialog(
        context,
        widget.controller.products,
        initial: before,
        preselectedProduct: product,
        scanWorkflow: true,
      );
      if (!mounted || line == null) return;
      setState(() => _lines[line.product.id] = line);
    }
  }

  List<Product> _searchResults() {
    final q = _productSearch.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return widget.controller.products
        .where((p) => '${p.name} ${p.categoryName} ${p.barcode ?? ''}'.toLowerCase().contains(q))
        .take(12)
        .toList(growable: false);
  }

  Future<void> _addSupplier() async {
    final created = await showSupplierDialog(context, widget.controller);
    if (created != null && mounted) setState(() => _supplierId = created);
  }

  XTypeGroup _imageTypeGroup() {
    if (Platform.isWindows) {
      return const XTypeGroup(label: 'Изображение накладной', extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'tif', 'tiff']);
    }
    if (Platform.isIOS) {
      return const XTypeGroup(label: 'Изображение накладной', uniformTypeIdentifiers: ['public.image']);
    }
    return const XTypeGroup(label: 'Изображение накладной', mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/bmp', 'image/tiff']);
  }

  Future<void> _scanInvoice({bool camera = false, bool gallery = false}) async {
    if (_recognizing) return;
    XFile? file;
    try {
      if (camera && (Platform.isAndroid || Platform.isIOS)) {
        file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 94, maxWidth: 2600);
      } else if (gallery && (Platform.isAndroid || Platform.isIOS)) {
        file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 96, maxWidth: 3000);
      } else {
        file = await openFile(acceptedTypeGroups: [_imageTypeGroup()]);
      }
      if (file == null || !mounted) return;
      setState(() {
        _recognizing = true;
        _invoicePath = file!.path;
      });
      final result = await _recognizer.recognize(
        imagePath: file.path,
        products: widget.controller.products,
        supplierLinks: widget.controller.productSuppliers,
        suppliers: widget.controller.suppliers,
      );
      if (!mounted) return;
      setState(() {
        _rawOcrText = result.rawText;
        if (result.documentNumber?.trim().isNotEmpty == true) _document.text = result.documentNumber!.trim();
        if (result.supplierId != null && widget.controller.suppliers.any((supplier) => supplier.id == result.supplierId)) {
          _supplierId = result.supplierId;
        }
        for (final recognized in result.lines) {
          _lines[recognized.product.id] = recognized.toDeliveryLine();
        }
      });
      final doubtful = result.lines.where((line) => line.confidence < .72).length;
      final autoFields = <String>[
        if (result.supplierName?.trim().isNotEmpty == true) 'поставщик: ${result.supplierName}',
        if (result.documentNumber?.trim().isNotEmpty == true) 'накладная №${result.documentNumber}',
      ];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Накладная распознана: ${result.lines.length} позиций'
          '${doubtful > 0 ? ', проверить вручную: $doubtful' : ''}'
          '${autoFields.isEmpty ? '' : '. Автоматически заполнено: ${autoFields.join(', ')}'}.'
          ' Перед проведением сверьте результат с оригиналом.',
        ),
      ));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<String?> _archiveInvoiceIfPresent() async {
    final path = _invoicePath;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final fileName = path.split(Platform.pathSeparator).last;
    return widget.controller.uploadInvoiceAttachment(bytes: bytes, fileName: fileName, mimeType: _mimeForPath(path));
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) return;
    if (_employee.text.trim().isEmpty) {
      showErrorSnack(context, 'Укажите ФИО сотрудника, принимающего поставку.');
      return;
    }
    final missingPrice = _lines.values.where((line) => line.unitCost == null).length;
    if (missingPrice > 0) {
      showErrorSnack(context, 'У $missingPrice позиций не заполнена закупочная цена. Цена обязательна для каждой позиции поставки.');
      return;
    }
    final lowConfidence = _lines.values.where((line) => (line.confidence ?? 1) < .55 && !line.manuallyCorrected).length;
    if (lowConfidence > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Есть сомнительно распознанные строки'),
          content: Text('$lowConfidence позиций имеют низкую уверенность OCR. Проверьте количество и товар перед проведением.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Вернуться к проверке')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Я проверил, продолжить')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      final attachmentPath = await _archiveInvoiceIfPresent();
      String? scanId;
      if ((_rawOcrText?.trim().isNotEmpty ?? false)) {
        scanId = await widget.controller.saveInvoiceScan(
          employee: _employee.text.trim(),
          supplierId: _supplierId,
          documentNumber: _document.text.trim().isEmpty ? null : _document.text.trim(),
          attachmentUrl: attachmentPath,
          rawText: _rawOcrText!,
          lines: _lines.values.toList(growable: false),
        );
      }
      await widget.controller.receiveDelivery(
        _lines.values.toList(growable: false),
        employee: _employee.text.trim(),
        supplierId: _supplierId,
        documentNumber: _document.text.trim().isEmpty ? null : _document.text.trim(),
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        attachmentUrl: attachmentPath,
        locationId: _locationId,
        metadata: {
          if (scanId?.isNotEmpty == true) 'invoice_scan_id': scanId,
          'ocr_used': _rawOcrText?.trim().isNotEmpty == true,
          'invoice_archived': attachmentPath?.isNotEmpty == true,
        },
      );
      if (!mounted) return;
      final operation = widget.controller.operations.isEmpty ? null : widget.controller.operations.first;
      setState(() {
        _lines.clear();
        _rawOcrText = null;
        _invoicePath = null;
        _document.clear();
        _comment.clear();
        _productSearch.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(attachmentPath == null ? 'Поставка принята. Остатки обновлены на всех устройствах.' : 'Поставка принята. Накладная сохранена в приватном архиве.'),
        action: operation == null ? null : SnackBarAction(label: 'PDF', onPressed: () => PdfExportService.exportOperation(operation)),
      ));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final products = widget.controller.products;
        final notInitialized = products.where((p) => !p.stockInitialized).length;
        final searchResults = _searchResults();
        return Scaffold(
          appBar: AppBar(title: const Text('Принять поставку')),
          body: products.isEmpty
              ? const EmptyState(icon: Icons.local_shipping_outlined, title: 'Нет складских позиций', message: 'Сначала добавьте позиции в разделе «Склад».')
              : notInitialized > 0
                  ? EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'Сначала проведите первичный переучёт',
                      message: 'У $notInitialized позиций ещё не введён фактический остаток. Поставка станет доступна после полного первичного пересчёта всего склада.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                      children: [
                        const InfoBanner(
                          icon: Icons.local_shipping_outlined,
                          text: 'Поставка поддерживает скан товара камерой, ввод кода, поиск по названию, речевой ввод и автоматическое распознавание накладной по фото/скану.',
                        ),
                        const SizedBox(height: 18),
                        _deliveryHeader(context),
                        const SizedBox(height: 18),
                        _scanActions(context),
                        const SizedBox(height: 22),
                        Text('Позиции поставки', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _saving || _recognizing ? null : _scanProductWorkflow,
                              icon: const BaliNavIcon(kind: BaliNavIconKind.scan, active: true, size: 20),
                              label: const Text('Сканировать товар'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _saving || _recognizing ? null : _manualProductCode,
                              icon: const Icon(Icons.pin_outlined),
                              label: const Text('Ввести код товара'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _saving || _recognizing ? null : () => _addLine(),
                              icon: const Icon(Icons.edit_note_outlined),
                              label: const Text('Выбрать из списка'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _productSearch,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: 'Найти товар по названию или коду',
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                VoiceInputButton(
                                  controller: _productSearch,
                                  tooltip: 'Найти товар голосом',
                                  onApplied: _refreshProductSearch,
                                ),
                                if (_productSearch.text.isNotEmpty)
                                  IconButton(onPressed: _productSearch.clear, tooltip: 'Очистить', icon: const Icon(Icons.clear)),
                              ],
                            ),
                          ),
                        ),
                        if (_productSearch.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Card(
                            child: searchResults.isEmpty
                                ? const Padding(padding: EdgeInsets.all(16), child: Text('Совпадений нет.'))
                                : Column(
                                    children: [
                                      for (var i = 0; i < searchResults.length; i++) ...[
                                        Builder(builder: (context) {
                                          final product = searchResults[i];
                                          final added = _lines.containsKey(product.id);
                                          return ListTile(
                                            leading: Icon(added ? Icons.check_circle_outline : Icons.add_circle_outline),
                                            title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                            subtitle: Text('${product.categoryName}${product.barcode?.trim().isNotEmpty == true ? ' • код ${product.barcode}' : ''}'),
                                            trailing: Chip(label: Text(added ? 'ДОБАВЛЕНО' : 'ДОБАВИТЬ')),
                                            onTap: _saving ? null : () => _addLine(_lines[product.id], product),
                                          );
                                        }),
                                        if (i != searchResults.length - 1) const Divider(height: 1),
                                      ],
                                    ],
                                  ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_lines.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
                            child: const Text('Пока нет позиций. Сканируйте товар, загрузите накладную, продиктуйте название или найдите товар вручную.', textAlign: TextAlign.center),
                          )
                        else
                          _linesCard(context),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _lines.isEmpty || _saving || _recognizing ? null : _submit,
                          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
                          label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('ПРОВЕСТИ ПОСТАВКУ')),
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _deliveryHeader(BuildContext context) {
    final suppliers = widget.controller.suppliers.where((supplier) => supplier.active).toList(growable: false);
    final locations = widget.controller.locations.where((location) => location.active).toList(growable: false);
    if (_supplierId != null && !suppliers.any((supplier) => supplier.id == _supplierId)) _supplierId = null;
    if (_locationId == null && locations.isNotEmpty) _locationId = widget.controller.primaryLocation?.id ?? locations.first.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _employee,
              decoration: InputDecoration(
                labelText: 'Сотрудник, ФИО *',
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: VoiceInputButton(controller: _employee, tooltip: 'Продиктовать ФИО'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _supplierId,
                    decoration: const InputDecoration(labelText: 'Поставщик', prefixIcon: Icon(Icons.business_outlined)),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Не указан')),
                      ...suppliers.map((supplier) => DropdownMenuItem<String?>(value: supplier.id, child: Text(supplier.name))),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _supplierId = value),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _saving ? null : _addSupplier, tooltip: 'Добавить поставщика', icon: const Icon(Icons.add_business)),
              ],
            ),
            const SizedBox(height: 12),
            if (locations.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _locationId,
                decoration: const InputDecoration(labelText: 'Куда принять', prefixIcon: Icon(Icons.warehouse_outlined)),
                items: locations.map((location) => DropdownMenuItem(value: location.id, child: Text(location.name))).toList(growable: false),
                onChanged: _saving ? null : (value) => setState(() => _locationId = value),
              ),
            if (locations.isNotEmpty) const SizedBox(height: 12),
            TextField(
              controller: _document,
              decoration: InputDecoration(
                labelText: 'Номер накладной / ТТН',
                prefixIcon: const Icon(Icons.receipt_long_outlined),
                suffixIcon: VoiceInputButton(controller: _document, tooltip: 'Продиктовать номер накладной'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Комментарий',
                prefixIcon: const Icon(Icons.notes_outlined),
                suffixIcon: VoiceInputButton(controller: _comment, append: true, tooltip: 'Продиктовать комментарий'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanActions(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Накладная / ТТН — автоматическое распознавание', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Сфотографируйте накладную, выберите фото из галереи или подгрузите готовый скан. OCR автоматически ищет товары, количество, закупочную цену, поставщика и номер накладной. Сомнительные строки отмечаются для ручной проверки.'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (Platform.isAndroid || Platform.isIOS)
                  FilledButton.tonalIcon(
                    onPressed: _recognizing || _saving ? null : () => _scanInvoice(camera: true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Сфотографировать накладную'),
                  ),
                if (Platform.isAndroid || Platform.isIOS)
                  FilledButton.tonalIcon(
                    onPressed: _recognizing || _saving ? null : () => _scanInvoice(gallery: true),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Выбрать фото'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _recognizing || _saving ? null : () => _scanInvoice(),
                  icon: _recognizing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.document_scanner_outlined),
                  label: Text(_recognizing ? 'Распознавание накладной…' : 'Подгрузить скан / файл'),
                ),
                if (_rawOcrText != null)
                  Chip(avatar: const Icon(Icons.auto_awesome, size: 18), label: Text('OCR: ${_lines.values.where((line) => line.confidence != null).length} поз.')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linesCard(BuildContext context) {
    final values = _lines.values.toList(growable: false)
      ..sort((a, b) {
        final c = a.product.categoryName.compareTo(b.product.categoryName);
        return c == 0 ? a.product.name.compareTo(b.product.name) : c;
      });
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Builder(builder: (context) {
              final line = values[i];
              final confidence = line.confidence;
              final needsCheck = confidence != null && confidence < .72 && !line.manuallyCorrected;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                title: Row(
                  children: [
                    Expanded(child: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                    const Chip(visualDensity: VisualDensity.compact, avatar: Icon(Icons.check_circle_outline, size: 17), label: Text('ДАННЫЕ ВВЕДЕНЫ')),
                    if (confidence != null)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(needsCheck ? Icons.warning_amber_rounded : Icons.auto_awesome, size: 17),
                        label: Text(line.manuallyCorrected ? 'проверено' : '${(confidence * 100).round()}%'),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${line.product.categoryName} • ${_productUnitLabel(line.product)}'),
                    if (line.sourceText != null) Text('OCR: ${line.sourceText}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    Text(line.unitCost == null ? 'Цена не заполнена' : 'Цена: ${formatMoney(line.unitCost, line.product.costCurrency)} за упаковку/единицу'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('+${formatStockParts(line.addedMl, line.product.packageSize, line.product.stockUnit)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    IconButton(onPressed: _saving ? null : () => _addLine(line, line.product), tooltip: 'Проверить / исправить', icon: const Icon(Icons.edit_outlined)),
                    IconButton(onPressed: _saving ? null : () => setState(() => _lines.remove(line.product.id)), tooltip: 'Удалить строку', icon: const Icon(Icons.delete_outline)),
                  ],
                ),
              );
            }),
            if (i != values.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

String _productUnitLabel(Product product) {
  return switch (product.stockUnit) {
    StockUnit.ml => 'бутылка ${formatPackageSize(product.packageSize, product.stockUnit)}',
    StockUnit.gram => 'упаковка ${formatPackageSize(product.packageSize, product.stockUnit)}',
    StockUnit.piece => 'штучный учёт',
  };
}

Future<String?> showSupplierDialog(BuildContext context, WarehouseController controller) async {
  final name = TextEditingController();
  final contact = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final notes = TextEditingController();
  var saving = false;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Новый поставщик'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Название *')),
                const SizedBox(height: 10),
                TextField(controller: contact, decoration: const InputDecoration(labelText: 'Контактное лицо')),
                const SizedBox(height: 10),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Телефон')),
                const SizedBox(height: 10),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'E-mail')),
                const SizedBox(height: 10),
                TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Примечание')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton.icon(
            onPressed: saving
                ? null
                : () async {
                    if (name.text.trim().isEmpty) {
                      showErrorSnack(dialogContext, 'Введите название поставщика');
                      return;
                    }
                    setState(() => saving = true);
                    try {
                      final id = await controller.addSupplier(
                        name: name.text.trim(),
                        contactPerson: contact.text.trim().isEmpty ? null : contact.text.trim(),
                        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                        email: email.text.trim().isEmpty ? null : email.text.trim(),
                        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext, id);
                    } catch (e) {
                      if (dialogContext.mounted) showErrorSnack(dialogContext, e);
                      setState(() => saving = false);
                    }
                  },
            icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_business),
            label: const Text('Добавить'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  contact.dispose();
  phone.dispose();
  email.dispose();
  notes.dispose();
  return result;
}

Future<DeliveryDraftLine?> showDeliveryLineDialog(
  BuildContext context,
  List<Product> products, {
  DeliveryDraftLine? initial,
  Product? preselectedProduct,
  bool scanWorkflow = false,
}) async {
  if (products.isEmpty) return null;
  var productId = initial?.product.id ?? preselectedProduct?.id ?? products.first.id;
  final whole = TextEditingController(text: '${initial?.bottles ?? 0}');
  final extra = TextEditingController(text: '${initial?.extraMl ?? 0}');
  final cost = TextEditingController(text: initial?.unitCost?.toStringAsFixed(2) ?? '');
  final key = GlobalKey<FormState>();

  final result = await showDialog<DeliveryDraftLine>(
    context: context,
    barrierDismissible: !scanWorkflow,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final product = products.firstWhere((p) => p.id == productId);
        final wholeLabel = switch (product.stockUnit) {
          StockUnit.ml => 'Бутылок принято',
          StockUnit.gram => 'Упаковок принято',
          StockUnit.piece => 'Количество, шт.',
        };
        final extraLabel = product.stockUnit == StockUnit.ml ? 'Доп. объём, мл' : 'Доп. остаток, г';
        final productLocked = initial != null || preselectedProduct != null;

        return AlertDialog(
          title: Row(
            children: [
              const BaliNavIcon(kind: BaliNavIconKind.delivery, active: true, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Text(initial == null ? 'Позиция поставки' : 'Проверить позицию поставки')),
            ],
          ),
          content: SizedBox(
            width: 580,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: productId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Позиция',
                        helperText: productLocked ? 'Позиция зафиксирована выбранным/отсканированным кодом.' : null,
                      ),
                      items: products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.categoryName} — ${p.name} (${_productUnitLabel(p)})'))).toList(growable: false),
                      onChanged: productLocked
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  productId = value;
                                  whole.text = '0';
                                  extra.text = '0';
                                  cost.text = '';
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    if (product.stockUnit == StockUnit.piece)
                      IntegerField(controller: whole, label: wholeLabel, min: 0)
                    else
                      TwoFields(
                        first: IntegerField(controller: whole, label: wholeLabel, min: 0),
                        second: IntegerField(
                          controller: extra,
                          label: extraLabel,
                          min: 0,
                          validator: (value) {
                            final base = integerValidator(value, min: 0);
                            if (base != null) return base;
                            final parsed = int.tryParse(value ?? '');
                            if (parsed != null && parsed >= product.packageSize) return 'Меньше ${product.packageSize} ${product.stockUnit.symbol}';
                            return null;
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: cost,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Закупочная цена за упаковку / единицу, ${product.costCurrency} *'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Закупочная цена обязательна';
                        final parsed = double.tryParse(value.replaceAll(',', '.'));
                        return parsed == null || parsed < 0 ? 'Некорректная цена' : null;
                      },
                    ),
                    if (initial?.sourceText != null) ...[
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: Text('Распознано: ${initial!.sourceText}', style: Theme.of(context).textTheme.bodySmall)),
                    ],
                    if (scanWorkflow) ...[
                      const SizedBox(height: 10),
                      const InfoBanner(icon: Icons.qr_code_scanner, text: 'После сохранения автоматически откроется камера для следующего товара. Чтобы закончить серию — закройте следующий экран сканера.'),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
            FilledButton.icon(
              onPressed: () {
                if (!(key.currentState?.validate() ?? false)) return;
                final wholeCount = int.parse(whole.text);
                final extraAmount = product.stockUnit == StockUnit.piece ? 0 : int.parse(extra.text);
                if (wholeCount == 0 && extraAmount == 0) {
                  showErrorSnack(dialogContext, 'Количество поставки не может быть нулевым');
                  return;
                }
                Navigator.of(dialogContext).pop(DeliveryDraftLine(
                  product: product,
                  bottles: wholeCount,
                  extraMl: extraAmount,
                  unitCost: double.parse(cost.text.replaceAll(',', '.')),
                  sourceText: initial?.sourceText,
                  confidence: initial?.confidence,
                  manuallyCorrected: initial != null,
                ));
              },
              icon: scanWorkflow ? const BaliNavIcon(kind: BaliNavIconKind.scan, active: true, size: 19) : const Icon(Icons.check_circle_outline),
              label: Text(scanWorkflow ? 'Сохранить → следующий скан' : (initial == null ? 'Добавить' : 'Подтвердить')),
            ),
          ],
        );
      },
    ),
  );
  whole.dispose();
  extra.dispose();
  cost.dispose();
  return result;
}
