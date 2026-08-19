import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/remote_purchase_v15_extension.dart';
import '../data/remote_stock_service.dart';
import '../models.dart';
import '../purchase_models.dart';
import '../services/invoice_recognition_service_v15.dart';
import '../services/pdf_export_service.dart';
import '../v14_controller.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';
import '../widgets/product_code_actions.dart';
import 'delivery_screen.dart' as legacy;

class DeliveryScreenV15 extends StatefulWidget {
  const DeliveryScreenV15({super.key, required this.controller});

  final V14WarehouseController controller;

  @override
  State<DeliveryScreenV15> createState() => _DeliveryScreenV15State();
}

class _DeliveryScreenV15State extends State<DeliveryScreenV15> {
  final _lines = <int, DeliveryDraftLine>{};
  final _employee = TextEditingController();
  final _document = TextEditingController();
  final _comment = TextEditingController();
  final _search = TextEditingController();
  final _recognizer = InvoiceRecognitionServiceV15();
  final _remote = RemoteStockService();
  final _picker = ImagePicker();

  List<StockPurchaseRequest> _requests = const [];
  String? _supplierId;
  String? _locationId;
  String? _purchaseRequestId;
  String? _invoicePath;
  String? _rawOcrText;
  DateTime? _recognizedDocumentDate;
  double? _documentConfidence;
  bool _saving = false;
  bool _recognizing = false;
  bool _loadingRequests = false;
  int _visibleLineLimit = 35;

  @override
  void initState() {
    super.initState();
    _search.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _locationId = widget.controller.primaryLocation?.id);
      _reloadRequests();
    });
  }

  @override
  void dispose() {
    _search.removeListener(_rebuild);
    _employee.dispose();
    _document.dispose();
    _comment.dispose();
    _search.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  int _initialVisibleLimit(int count) {
    if (count <= 35) return 35;
    return count < 70 ? count : 70;
  }

  String _productKey(Product product) => _remote.productKey(
        name: product.name,
        unit: product.stockUnit,
        packageSize: product.packageSize,
      );

  Product? _productForKey(String key) =>
      widget.controller.products.where((product) => _productKey(product) == key).firstOrNull;

  StockSupplier? _supplier(String? id) => id == null
      ? null
      : widget.controller.suppliers.where((supplier) => supplier.active && supplier.id == id).firstOrNull;

  Future<void> _reloadRequests() async {
    if (_loadingRequests) return;
    setState(() => _loadingRequests = true);
    try {
      final values = await _remote.fetchPurchaseRequestsV15();
      if (mounted) setState(() => _requests = values.where((request) => request.canReceive).toList(growable: false));
    } catch (_) {
      // Заявка — дополнительный сценарий. Обычная поставка остаётся доступна.
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _selectRequest(String? id) async {
    if (id == null) {
      setState(() => _purchaseRequestId = null);
      return;
    }
    final request = _requests.where((value) => value.id == id).firstOrNull;
    if (request == null) return;
    final prefilled = <int, DeliveryDraftLine>{};
    for (final requestLine in request.lines) {
      final outstanding = requestLine.outstandingQuantity;
      if (outstanding <= 0) continue;
      final product = _productForKey(requestLine.productKey);
      if (product == null) continue;
      final whole = product.stockUnit == StockUnit.piece ? outstanding : outstanding ~/ product.packageSize;
      final extra = product.stockUnit == StockUnit.piece ? 0 : outstanding % product.packageSize;
      prefilled[product.id] = DeliveryDraftLine(
        product: product,
        bottles: whole,
        extraMl: extra,
        unitCost: requestLine.unitCost,
        sourceText: request.shortNumber,
        manuallyCorrected: true,
      );
    }
    setState(() {
      _purchaseRequestId = request.id;
      _supplierId = request.supplierId;
      _lines
        ..clear()
        ..addAll(prefilled);
      _visibleLineLimit = _initialVisibleLimit(prefilled.length);
    });
  }

  Future<void> _addLine({Product? product, bool scanWorkflow = false}) async {
    final initial = product == null ? null : _lines[product.id];
    final line = await legacy.showDeliveryLineDialog(
      context,
      widget.controller.products,
      initial: initial,
      preselectedProduct: product,
      scanWorkflow: scanWorkflow,
    );
    if (line == null || !mounted) return;
    setState(() => _lines[line.product.id] = line);
  }

  Future<void> _editLine(DeliveryDraftLine line) async {
    final edited = await legacy.showDeliveryLineDialog(
      context,
      widget.controller.products,
      initial: line,
      preselectedProduct: line.product,
    );
    if (edited == null || !mounted) return;
    setState(() => _lines[edited.product.id] = edited);
  }

  Future<void> _manualProductCode() async {
    final code = await enterProductCode(context);
    if (!mounted || code == null) return;
    final product = findProductByCode(widget.controller.products, code);
    if (product == null) {
      showErrorSnack(context, 'Код товара ${code.trim()} не привязан ни к одной позиции.');
      return;
    }
    await _addLine(product: product);
  }

  Future<void> _scanProductWorkflow() async {
    while (mounted) {
      final code = await scanProductCode(context);
      if (!mounted || code == null) return;
      final product = findProductByCode(widget.controller.products, code);
      if (product == null) {
        showErrorSnack(context, 'Код товара ${code.trim()} не привязан ни к одной позиции.');
        continue;
      }
      final before = _lines[product.id];
      final line = await legacy.showDeliveryLineDialog(
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
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return widget.controller.products
        .where((p) => '${p.name} ${p.categoryName} ${p.barcode ?? ''}'.toLowerCase().contains(query))
        .take(15)
        .toList(growable: false);
  }

  Future<XFile?> _pickInvoice({required bool camera}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1800,
        maxHeight: 2400,
        requestFullMetadata: false,
      );
    }
    if (camera) return null;
    final typeGroup = Platform.isWindows
        ? const XTypeGroup(label: 'Накладная', extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'tif', 'tiff'])
        : const XTypeGroup(label: 'Накладная', mimeTypes: ['image/jpeg', 'image/png', 'image/webp'], uniformTypeIdentifiers: ['public.image']);
    return openFile(acceptedTypeGroups: [typeGroup]);
  }

  Future<void> _scanInvoice({required bool camera}) async {
    if (_recognizing || _saving) return;
    try {
      final file = await _pickInvoice(camera: camera);
      if (file == null || !mounted) return;
      setState(() => _recognizing = true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final result = await _recognizer.recognize(
        imagePath: file.path,
        products: widget.controller.products,
        supplierLinks: widget.controller.productSuppliers,
        suppliers: widget.controller.suppliers,
      );
      if (!mounted) return;
      final imported = <int, DeliveryDraftLine>{};
      for (final line in result.lines) {
        imported[line.product.id] = line.toDeliveryLine();
      }
      setState(() {
        _invoicePath = file.path;
        _rawOcrText = result.rawText;
        _recognizedDocumentDate = result.documentDate;
        _documentConfidence = result.documentConfidence;
        _lines
          ..clear()
          ..addAll(imported);
        _visibleLineLimit = _initialVisibleLimit(imported.length);
        if (result.supplierId != null) _supplierId = result.supplierId;
        final number = result.documentNumber?.trim();
        if (number != null && number.isNotEmpty) _document.text = number;
      });
      final reviewCount = result.lines.where((line) => line.confidence < .72 || line.unitCost == null).length;
      final supplierHint = result.supplierId == null && result.supplierText?.trim().isNotEmpty == true
          ? ' • поставщик «${result.supplierText}» не найден в списке'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Накладная распознана: ${result.lines.length} поз.${reviewCount > 0 ? ' • проверить: $reviewCount' : ''}$supplierHint'),
      ));
    } on InvoiceNotRecognizedException catch (e) {
      if (mounted) showErrorSnack(context, e.toString());
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Не удалось распознать накладную. $e');
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

  Future<String?> _archiveInvoice() async {
    final path = _invoicePath;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return widget.controller.uploadInvoiceAttachment(
      bytes: bytes,
      fileName: path.split(Platform.pathSeparator).last,
      mimeType: _mimeForPath(path),
    );
  }

  Future<void> _submit() async {
    if (_lines.isEmpty || _saving || _recognizing) return;
    if (_employee.text.trim().isEmpty) {
      showErrorSnack(context, 'Введите ФИО принимающего.');
      return;
    }
    if (_supplierId == null) {
      showErrorSnack(context, 'Выберите поставщика из списка.');
      return;
    }
    if (_locationId == null && widget.controller.locations.any((value) => value.active)) {
      showErrorSnack(context, 'Выберите склад.');
      return;
    }
    final missingPrice = _lines.values.where((line) => line.unitCost == null).length;
    if (missingPrice > 0) {
      showErrorSnack(context, 'У $missingPrice позиций не заполнена закупочная цена.');
      return;
    }
    final doubtful = _lines.values.where((line) => (line.confidence ?? 1) < .55 && !line.manuallyCorrected).length;
    if (doubtful > 0) {
      final checked = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Проверьте распознанные позиции'),
          content: Text('$doubtful позиций имеют низкую уверенность распознавания.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Вернуться')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Я проверил')),
          ],
        ),
      );
      if (checked != true) return;
    }

    setState(() => _saving = true);
    try {
      final attachment = await _archiveInvoice();
      String? scanId;
      if (_rawOcrText?.trim().isNotEmpty == true) {
        scanId = await widget.controller.saveInvoiceScan(
          employee: _employee.text.trim(),
          supplierId: _supplierId,
          documentNumber: _document.text.trim().isEmpty ? null : _document.text.trim(),
          attachmentUrl: attachment,
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
        attachmentUrl: attachment,
        locationId: _locationId,
        metadata: {
          if (scanId?.isNotEmpty == true) 'invoice_scan_id': scanId,
          if (_purchaseRequestId != null) 'purchase_request_id': _purchaseRequestId,
          if (_recognizedDocumentDate != null) 'invoice_date': _recognizedDocumentDate!.toIso8601String(),
          if (_documentConfidence != null) 'invoice_document_confidence': _documentConfidence,
          'ocr_used': _rawOcrText?.trim().isNotEmpty == true,
          'invoice_archived': attachment?.isNotEmpty == true,
        },
      );
      if (!mounted) return;
      final operation = widget.controller.operations.firstOrNull;
      setState(() {
        _lines.clear();
        _rawOcrText = null;
        _invoicePath = null;
        _recognizedDocumentDate = null;
        _documentConfidence = null;
        _purchaseRequestId = null;
        _document.clear();
        _comment.clear();
        _search.clear();
        _visibleLineLimit = 35;
      });
      await _reloadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Поставка принята. Остатки обновлены.'),
        action: operation == null ? null : SnackBarAction(label: 'PDF', onPressed: () => PdfExportService.exportOperation(operation)),
      ));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final products = widget.controller.products;
          final uninitialized = products.where((product) => !product.stockInitialized).length;
          final page = products.isEmpty
              ? const EmptyState(icon: Icons.local_shipping_outlined, title: 'Нет складских позиций', message: 'Сначала добавьте позиции в разделе «Склад».')
              : uninitialized > 0
                  ? EmptyState(icon: Icons.fact_check_outlined, title: 'Сначала проведите первичный переучёт', message: 'У $uninitialized позиций ещё не введён фактический остаток.')
                  : _body();
          return Scaffold(
            appBar: AppBar(title: const Text('Поставка')),
            body: Stack(children: [
              Positioned.fill(child: IgnorePointer(ignoring: _recognizing, child: page)),
              if (_recognizing) Positioned.fill(child: _recognitionOverlay()),
            ]),
          );
        },
      );

  Widget _recognitionOverlay() => Container(
        color: Colors.black.withValues(alpha: .72),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: const Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 38, height: 38, child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(height: 16),
              Text('Распознаю накладную…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              SizedBox(height: 5),
              Text('Проверяю документ, товары, количество и цены.', textAlign: TextAlign.center),
            ]),
          ),
        ),
      );

  Widget _body() {
    final results = _searchResults();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
          children: [
            _header(),
            const SizedBox(height: 10),
            _invoiceCard(),
            const SizedBox(height: 14),
            Text('Позиции поставки', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _saving ? null : _scanProductWorkflow, icon: const BaliNavIcon(kind: BaliNavIconKind.scan, active: true, size: 20), label: const Text('Сканировать товар')),
              OutlinedButton.icon(onPressed: _saving ? null : _manualProductCode, icon: const Icon(Icons.pin_outlined), label: const Text('Ввести код товара')),
              OutlinedButton.icon(onPressed: _saving ? null : () => _addLine(), icon: const Icon(Icons.search), label: const Text('Выбрать товар')),
            ]),
            const SizedBox(height: 9),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'Найти по названию или коду',
                suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _search.clear, icon: const Icon(Icons.clear)),
              ),
            ),
            if (_search.text.trim().isNotEmpty) ...[
              const SizedBox(height: 7),
              Card(
                child: results.isEmpty
                    ? const Padding(padding: EdgeInsets.all(16), child: Text('Совпадений нет.'))
                    : Column(children: [
                        for (var i = 0; i < results.length; i++) ...[
                          ListTile(
                            title: Text(results[i].name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('${results[i].categoryName}${results[i].barcode?.trim().isNotEmpty == true ? ' • код ${results[i].barcode}' : ''}'),
                            trailing: Chip(label: Text(_lines.containsKey(results[i].id) ? 'ДОБАВЛЕНО' : 'ДОБАВИТЬ')),
                            onTap: _saving ? null : () => _addLine(product: results[i]),
                          ),
                          if (i != results.length - 1) const Divider(height: 1),
                        ],
                      ]),
              ),
            ],
            const SizedBox(height: 10),
            _linesCard(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _lines.isEmpty || _saving ? null : _submit,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const BaliNavIcon(kind: BaliNavIconKind.delivery, active: true, size: 20),
              label: const Padding(padding: EdgeInsets.symmetric(vertical: 11), child: Text('ПРОВЕСТИ ПОСТАВКУ', style: TextStyle(fontWeight: FontWeight.w900))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final suppliers = widget.controller.suppliers.where((supplier) => supplier.active).toList(growable: true)
      ..sort((a, b) => a.name.compareTo(b.name));
    final locations = widget.controller.locations.where((location) => location.active).toList(growable: false);
    if (_supplierId != null && !suppliers.any((supplier) => supplier.id == _supplierId)) _supplierId = null;
    if (_locationId == null && locations.isNotEmpty) _locationId = widget.controller.primaryLocation?.id ?? locations.first.id;
    final requests = _requests.where((request) => request.canReceive).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          TextField(controller: _employee, decoration: const InputDecoration(labelText: 'ФИО принимающего *')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _supplierId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Поставщик *'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Выберите поставщика')),
              ...suppliers.map((supplier) => DropdownMenuItem<String?>(value: supplier.id, child: Text(supplier.name))),
            ],
            onChanged: _saving ? null : (value) => setState(() => _supplierId = value),
          ),
          const SizedBox(height: 10),
          if (locations.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _locationId,
              decoration: const InputDecoration(labelText: 'Склад *'),
              items: locations.map((location) => DropdownMenuItem(value: location.id, child: Text(location.isPrimary ? '${location.name} • основной' : location.name))).toList(growable: false),
              onChanged: _saving ? null : (value) => setState(() => _locationId = value),
            ),
          if (locations.isNotEmpty) const SizedBox(height: 10),
          if (requests.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              initialValue: _purchaseRequestId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Заявка на закупку — при наличии'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Без привязки к заявке')),
                ...requests.map((request) => DropdownMenuItem<String?>(
                      value: request.id,
                      child: Text('${request.shortNumber} • ${_supplier(request.supplierId)?.name ?? 'поставщик'}'),
                    )),
              ],
              onChanged: _saving ? null : _selectRequest,
            ),
            const SizedBox(height: 10),
          ],
          TextField(controller: _document, decoration: const InputDecoration(labelText: '№ накладной / ТТН')),
          const SizedBox(height: 10),
          TextField(controller: _comment, maxLines: 2, decoration: const InputDecoration(labelText: 'Комментарий')),
        ]),
      ),
    );
  }

  Widget _invoiceCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Накладная / ТТН', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (Platform.isAndroid || Platform.isIOS)
                FilledButton.tonalIcon(onPressed: _saving ? null : () => _scanInvoice(camera: true), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Сфотографировать')),
              FilledButton.tonalIcon(onPressed: _saving ? null : () => _scanInvoice(camera: false), icon: const Icon(Icons.document_scanner_outlined), label: const Text('Загрузить фото')),
              if (_rawOcrText != null) const Chip(avatar: Icon(Icons.check_circle_outline, size: 18), label: Text('Накладная распознана')),
            ]),
          ]),
        ),
      );

  Widget _linesCard() {
    if (_lines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
        child: const Text('Пока нет позиций.', textAlign: TextAlign.center),
      );
    }
    final values = _lines.values.toList(growable: false)
      ..sort((a, b) {
        final category = a.product.categoryName.compareTo(b.product.categoryName);
        return category == 0 ? a.product.name.compareTo(b.product.name) : category;
      });
    final visible = values.take(_visibleLineLimit).toList(growable: false);
    return Card(
      child: Column(children: [
        for (var i = 0; i < visible.length; i++) ...[
          _lineTile(visible[i]),
          if (i != visible.length - 1) const Divider(height: 1),
        ],
        if (values.length > visible.length)
          ListTile(
            title: Text('Показано ${visible.length} из ${values.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
            trailing: FilledButton.tonal(onPressed: () => setState(() => _visibleLineLimit += 35), child: const Text('Показать ещё')),
          ),
        if (_visibleLineLimit > 35 && values.length > 35)
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => _visibleLineLimit = 35), child: const Text('Свернуть список'))),
      ]),
    );
  }

  Widget _lineTile(DeliveryDraftLine line) {
    final confidence = line.confidence;
    final needsCheck = confidence != null && (confidence < .72 || line.unitCost == null) && !line.manuallyCorrected;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      title: Text(line.product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(line.product.categoryName),
        Text(line.unitCost == null ? 'Цена не распознана — заполните вручную' : 'Цена: ${formatMoney(line.unitCost, line.product.costCurrency)}'),
        if (confidence != null) Text(needsCheck ? 'OCR ${(confidence * 100).round()}% • ПРОВЕРИТЬ' : 'OCR ${(confidence * 100).round()}%'),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 125),
          child: Text(
            '+${formatStockParts(line.addedMl, line.product.packageSize, line.product.stockUnit)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(onPressed: _saving ? null : () => _editLine(line), tooltip: 'Проверить', icon: const Icon(Icons.edit_outlined)),
        IconButton(onPressed: _saving ? null : () => setState(() => _lines.remove(line.product.id)), tooltip: 'Удалить', icon: const Icon(Icons.delete_outline)),
      ]),
    );
  }
}
