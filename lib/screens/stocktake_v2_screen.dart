import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../services/stocktake_note_store.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';
import '../widgets/product_code_actions.dart';

class StocktakeV2Screen extends StatefulWidget {
  const StocktakeV2Screen({
    super.key,
    required this.controller,
    required this.onCompleted,
  });

  final WarehouseController controller;
  final VoidCallback onCompleted;

  @override
  State<StocktakeV2Screen> createState() => _StocktakeV2ScreenState();
}

class _StocktakeV2ScreenState extends State<StocktakeV2Screen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _noteStore = StocktakeNoteStore();
  final Map<int, _CountEntry> _entries = {};
  final Map<int, Timer> _saveTimers = {};
  final Map<int, String> _comments = {};
  final Set<int> _rechecked = {};

  StocktakeDraft? _draft;
  Timer? _clock;
  bool _loading = true;
  bool _submitting = false;
  _StocktakeListFilter _listFilter = _StocktakeListFilter.all;
  int _activeSeconds = 0;
  int _lastPersistedSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_refreshSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.removeListener(_refreshSearch);
    _search.dispose();
    _clock?.cancel();
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    for (final entry in _entries.values) {
      entry.dispose();
    }
    final draft = _draft;
    if (draft != null) {
      widget.controller.pauseStocktakeDraft(draft.id, _activeSeconds);
      _noteStore.save(draft.id, comments: _comments, rechecked: _rechecked);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final draft = _draft;
    if (draft == null) return;
    if (state == AppLifecycleState.resumed) {
      _startClock();
      widget.controller.resumeStocktakeDraft(draft.id);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _pauseClock();
      widget.controller.pauseStocktakeDraft(draft.id, _activeSeconds);
      _noteStore.save(draft.id, comments: _comments, rechecked: _rechecked);
    }
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    try {
      final employee = await _askEmployee();
      if (!mounted) return;
      if (employee == null) {
        widget.onCompleted();
        return;
      }
      var draft = await widget.controller.getActiveStocktakeDraft(employee);
      if (draft != null && mounted) {
        final action = await _draftChoice(draft);
        if (!mounted) return;
        if (action == _DraftAction.cancel) {
          widget.onCompleted();
          return;
        }
        if (action == _DraftAction.restart) {
          final confirmed = await _confirmRestart();
          if (!mounted) return;
          if (!confirmed) {
            draft = await widget.controller.resumeStocktakeDraft(draft.id);
          } else {
            await widget.controller.deleteStocktakeDraft(draft.id);
            await _noteStore.clear(draft.id);
            draft = await widget.controller.createStocktakeDraft(employee);
          }
        } else {
          draft = await widget.controller.resumeStocktakeDraft(draft.id);
        }
      } else {
        draft = await widget.controller.createStocktakeDraft(employee);
      }
      await _loadDraft(draft);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showErrorSnack(context, e);
      }
    }
  }

  Future<String?> _askEmployee() async {
    final last = await widget.controller.getLastStocktakeEmployee();
    final field = TextEditingController(text: last ?? '');
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Кто проводит переучёт?'),
        content: SizedBox(
          width: 430,
          child: TextField(
            controller: field,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'ФИО сотрудника'),
            onSubmitted: (_) {
              final value = field.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () {
              final value = field.text.trim();
              if (value.isEmpty) {
                showErrorSnack(dialogContext, 'Введите ФИО');
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    field.dispose();
    return result;
  }

  Future<_DraftAction> _draftChoice(StocktakeDraft draft) async {
    return await showDialog<_DraftAction>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('У вас есть незавершённый переучёт'),
            content: Text(
              'Начат: ${formatDateTime(draft.startedAt)}\n'
              'Заполнено: ${draft.filledCount} из ${draft.totalCount} позиций\n'
              'Активное время: ${formatDurationSeconds(draft.activeSeconds)}',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _DraftAction.cancel),
                child: const Text('Назад'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _DraftAction.restart),
                child: const Text('Начать сначала'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _DraftAction.resume),
                child: const Text('Продолжить переучёт'),
              ),
            ],
          ),
        ) ??
        _DraftAction.cancel;
  }

  Future<bool> _confirmRestart() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Начать переучёт заново?'),
            content: const Text('Все данные текущего черновика будут удалены.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Начать заново'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _loadDraft(StocktakeDraft draft) async {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    for (final line in draft.lines) {
      _entries[line.productId] = _CountEntry(
        whole: line.wholePackages == null ? '' : '${line.wholePackages}',
        extra: line.stockUnit == StockUnit.piece
            ? '0'
            : (line.extraAmount == null ? '' : '${line.extraAmount}'),
      );
    }
    final local = await _noteStore.load(draft.id);
    _comments
      ..clear()
      ..addAll(local.comments);
    _rechecked
      ..clear()
      ..addAll(local.rechecked);
    _draft = draft;
    _activeSeconds = draft.activeSeconds;
    _lastPersistedSeconds = draft.activeSeconds;
    if (mounted) setState(() => _loading = false);
    _startClock();
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _draft == null || _submitting) return;
      setState(() => _activeSeconds++);
      if (_activeSeconds - _lastPersistedSeconds >= 15) {
        _lastPersistedSeconds = _activeSeconds;
        widget.controller.saveStocktakeActiveSeconds(
          _draft!.id,
          _activeSeconds,
        );
      }
    });
  }

  void _pauseClock() {
    _clock?.cancel();
    _clock = null;
  }

  bool _isFilled(SavedStocktakeLine line) {
    final entry = _entries[line.productId];
    if (entry == null) return false;
    final whole = int.tryParse(entry.whole.text);
    if (whole == null || whole < 0) return false;
    if (line.stockUnit == StockUnit.piece) return true;
    final extra = int.tryParse(entry.extra.text);
    return extra != null && extra >= 0 && extra < line.packageSize;
  }

  int? _actualTotal(SavedStocktakeLine line) {
    if (!_isFilled(line)) return null;
    final entry = _entries[line.productId]!;
    final whole = int.parse(entry.whole.text);
    if (line.stockUnit == StockUnit.piece) return whole;
    return whole * line.packageSize + int.parse(entry.extra.text);
  }

  int get _filledCount {
    final draft = _draft;
    if (draft == null) return 0;
    return draft.lines.where(_isFilled).length;
  }

  void _changed(SavedStocktakeLine line) {
    _rechecked.remove(line.productId);
    final draft = _draft;
    if (draft == null) return;
    _saveTimers.remove(line.productId)?.cancel();
    _saveTimers[line.productId] = Timer(
      const Duration(milliseconds: 250),
      () async {
        final entry = _entries[line.productId]!;
        await widget.controller.saveStocktakeDraftLine(
          draftId: draft.id,
          productId: line.productId,
          wholePackages: int.tryParse(entry.whole.text),
          extraAmount: line.stockUnit == StockUnit.piece
              ? 0
              : int.tryParse(entry.extra.text),
        );
        await _noteStore.save(
          draft.id,
          comments: _comments,
          rechecked: _rechecked,
        );
        if (mounted) setState(() {});
      },
    );
    setState(() {});
  }

  void _commentChanged(int productId, String value) {
    if (value.trim().isEmpty) {
      _comments.remove(productId);
    } else {
      _comments[productId] = value;
    }
    final draft = _draft;
    if (draft != null) {
      _saveTimers.remove(-productId)?.cancel();
      _saveTimers[-productId] = Timer(
        const Duration(milliseconds: 400),
        () => _noteStore.save(
          draft.id,
          comments: _comments,
          rechecked: _rechecked,
        ),
      );
    }
  }

  Product? _productFor(SavedStocktakeLine line) {
    for (final product in widget.controller.products) {
      if (product.id == line.productId ||
          product.name.toLowerCase() == line.productName.toLowerCase())
        return product;
    }
    return null;
  }

  SavedStocktakeLine? _lineForProduct(Product product) {
    final draft = _draft;
    if (draft == null) return null;
    for (final line in draft.lines) {
      if (line.productId == product.id ||
          line.productName.toLowerCase() == product.name.toLowerCase())
        return line;
    }
    return null;
  }

  bool _isSuspicious(SavedStocktakeLine line) {
    final actual = _actualTotal(line);
    if (actual == null || !line.beforeInitialized) return false;
    final product = _productFor(line);
    final diff = (actual - line.beforeTotal).abs();
    final configured = product?.varianceRecheckAmount ?? 0;
    if (configured > 0 && diff >= configured) return true;
    final package = math.max(line.packageSize, 1);
    if (diff >= package * 10) return true;
    if (line.beforeTotal > 0 &&
        actual > line.beforeTotal * 5 &&
        actual - line.beforeTotal >= package * 3)
      return true;
    return false;
  }

  Future<void> _manualCode() async {
    final code = await enterProductCode(context);
    if (!mounted || code == null) return;
    final product = await resolveProductCode(
      context,
      controller: widget.controller,
      rawCode: code,
    );
    if (!mounted || product == null) return;
    final line = _lineForProduct(product);
    if (line == null) {
      showErrorSnack(context, 'Товар не входит в текущий переучёт.');
      return;
    }
    await _showQuickCount(line, allowNextScan: false);
  }

  Future<void> _scanWorkflow() async {
    while (mounted) {
      final code = await scanProductCode(context);
      if (!mounted || code == null) return;
      final product = await resolveProductCode(
        context,
        controller: widget.controller,
        rawCode: code,
      );
      if (!mounted || product == null) return;
      final line = _lineForProduct(product);
      if (line == null) {
        showErrorSnack(
          context,
          'Товар ${product.name} не входит в текущий переучёт.',
        );
        continue;
      }
      final result = await _showQuickCount(line, allowNextScan: true);
      if (!mounted || result == null || result == _QuickCountResult.saved)
        return;
    }
  }

  Future<_QuickCountResult?> _showQuickCount(
    SavedStocktakeLine line, {
    required bool allowNextScan,
  }) async {
    final current = _entries[line.productId]!;
    final whole = TextEditingController(text: current.whole.text);
    final extra = TextEditingController(
      text: line.stockUnit == StockUnit.piece ? '0' : current.extra.text,
    );
    final comment = TextEditingController(
      text: _comments[line.productId] ?? '',
    );
    final key = GlobalKey<FormState>();
    var saving = false;

    final result = await showDialog<_QuickCountResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              const BaliNavIcon(
                kind: BaliNavIconKind.stocktake,
                active: true,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(line.productName)),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoBanner(
                      icon: _isFilled(line)
                          ? Icons.check_circle_outline
                          : Icons.pending_actions,
                      text: _isFilled(line)
                          ? 'По этой позиции данные уже были введены. Можно пересчитать и заменить значение.'
                          : 'Введите фактическое наличие. После сохранения позиция будет отмечена как «Данные введены».',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      line.beforeInitialized
                          ? 'Расчётный остаток до переучёта: ${formatStockParts(line.beforeTotal, line.packageSize, line.stockUnit)}'
                          : 'Первичная инвентаризация — предыдущий остаток не задан',
                    ),
                    const SizedBox(height: 12),
                    if (line.stockUnit == StockUnit.piece)
                      IntegerField(
                        controller: whole,
                        label: 'Фактически, шт.',
                        min: 0,
                      )
                    else
                      TwoFields(
                        first: IntegerField(
                          controller: whole,
                          label: line.stockUnit == StockUnit.ml
                              ? 'Целых бутылок'
                              : 'Целых упаковок',
                          min: 0,
                        ),
                        second: IntegerField(
                          controller: extra,
                          label: 'Доп. остаток, ${line.stockUnit.symbol}',
                          min: 0,
                          validator: (value) {
                            final base = integerValidator(value, min: 0);
                            if (base != null) return base;
                            final parsed = int.tryParse(value ?? '');
                            return parsed != null && parsed >= line.packageSize
                                ? 'Меньше ${line.packageSize}'
                                : null;
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: comment,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Комментарий (необязательно)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(key.currentState?.validate() ?? false)) return;
                      final wholeValue = int.tryParse(whole.text);
                      final extraValue = line.stockUnit == StockUnit.piece
                          ? 0
                          : int.tryParse(extra.text);
                      if (wholeValue == null ||
                          wholeValue < 0 ||
                          extraValue == null ||
                          extraValue < 0 ||
                          (line.stockUnit != StockUnit.piece &&
                              extraValue >= line.packageSize)) {
                        showErrorSnack(dialogContext, 'Проверьте количество');
                        return;
                      }
                      setState(() => saving = true);
                      try {
                        current.whole.text = '$wholeValue';
                        current.extra.text = '$extraValue';
                        final note = comment.text.trim();
                        if (note.isEmpty) {
                          _comments.remove(line.productId);
                        } else {
                          _comments[line.productId] = note;
                        }
                        _rechecked.remove(line.productId);
                        await widget.controller.saveStocktakeDraftLine(
                          draftId: _draft!.id,
                          productId: line.productId,
                          wholePackages: wholeValue,
                          extraAmount: extraValue,
                        );
                        await _noteStore.save(
                          _draft!.id,
                          comments: _comments,
                          rechecked: _rechecked,
                        );
                        if (mounted) setState(() {});
                        if (dialogContext.mounted) {
                          Navigator.pop(
                            dialogContext,
                            allowNextScan
                                ? _QuickCountResult.savedAndScanNext
                                : _QuickCountResult.saved,
                          );
                        }
                      } catch (e) {
                        if (dialogContext.mounted)
                          showErrorSnack(dialogContext, e);
                        setState(() => saving = false);
                      }
                    },
              icon: allowNextScan
                  ? const BaliNavIcon(
                      kind: BaliNavIconKind.scan,
                      active: true,
                      size: 19,
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                allowNextScan ? 'Сохранить → следующий скан' : 'Сохранить',
              ),
            ),
          ],
        ),
      ),
    );
    whole.dispose();
    extra.dispose();
    comment.dispose();
    return result;
  }

  List<SavedStocktakeLine> _visibleLines() {
    final draft = _draft;
    if (draft == null) return const [];
    final q = _search.text.trim().toLowerCase();
    return draft.lines
        .where((line) {
          final filled = _isFilled(line);
          if (_listFilter == _StocktakeListFilter.unfilled && filled)
            return false;
          if (_listFilter == _StocktakeListFilter.filled && !filled)
            return false;
          if (q.isEmpty) return true;
          final barcode = _productFor(line)?.barcode ?? '';
          return '${line.productName} ${line.categoryName} $barcode'
              .toLowerCase()
              .contains(q);
        })
        .toList(growable: false);
  }

  Future<bool> _performMandatoryRechecks() async {
    final draft = _draft!;
    final flagged = draft.lines
        .where(
          (line) => _isSuspicious(line) && !_rechecked.contains(line.productId),
        )
        .toList(growable: false);
    for (final line in flagged) {
      if (!mounted) return false;
      final second = await _showRecheck(line);
      if (second == null) return false;
      final current = _actualTotal(line)!;
      if (second != current) {
        final entry = _entries[line.productId]!;
        if (line.stockUnit == StockUnit.piece) {
          entry.whole.text = '$second';
        } else {
          entry.whole.text = '${second ~/ line.packageSize}';
          entry.extra.text = '${second % line.packageSize}';
        }
        _changed(line);
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Результаты пересчёта отличаются'),
              content: Text(
                '${line.productName}: первое значение и повторный пересчёт не совпали. В карточку подставлен результат повторного пересчёта. Пересчитайте позицию ещё раз и затем снова завершите переучёт.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Понятно'),
                ),
              ],
            ),
          );
        }
        return false;
      }
      _rechecked.add(line.productId);
      await _noteStore.save(
        draft.id,
        comments: _comments,
        rechecked: _rechecked,
      );
      if (mounted) setState(() {});
    }
    return true;
  }

  Future<int?> _showRecheck(SavedStocktakeLine line) async {
    final whole = TextEditingController();
    final extra = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final before = formatStockParts(
            line.beforeTotal,
            line.packageSize,
            line.stockUnit,
          );
          final actual = _actualTotal(line)!;
          final diff = actual - line.beforeTotal;
          return AlertDialog(
            title: Text('Повторный пересчёт: ${line.productName}'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoBanner(
                    icon: Icons.warning_amber_rounded,
                    text:
                        'Обнаружено существенное расхождение. Расчётно было $before, первый пересчёт дал ${formatStockParts(actual, line.packageSize, line.stockUnit)} (${diff >= 0 ? '+' : '−'}${formatTotalAmount(diff.abs(), line.stockUnit)}). Введите результат повторного физического пересчёта заново.',
                  ),
                  const SizedBox(height: 14),
                  if (line.stockUnit == StockUnit.piece)
                    IntegerField(
                      controller: whole,
                      label: 'Повторно пересчитано, шт.',
                      min: 0,
                    )
                  else
                    TwoFields(
                      first: IntegerField(
                        controller: whole,
                        label: line.stockUnit == StockUnit.ml
                            ? 'Бутылок повторно'
                            : 'Упаковок повторно',
                        min: 0,
                      ),
                      second: IntegerField(
                        controller: extra,
                        label: 'Доп. ${line.stockUnit.symbol}',
                        min: 0,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final w = int.tryParse(whole.text);
                  if (w == null || w < 0) {
                    showErrorSnack(dialogContext, 'Введите количество');
                    return;
                  }
                  if (line.stockUnit == StockUnit.piece) {
                    Navigator.pop(dialogContext, w);
                    return;
                  }
                  final e = int.tryParse(extra.text);
                  if (e == null || e < 0 || e >= line.packageSize) {
                    showErrorSnack(
                      dialogContext,
                      'Дополнительный остаток должен быть от 0 до ${line.packageSize - 1} ${line.stockUnit.symbol}',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, w * line.packageSize + e);
                },
                child: const Text('Подтвердить повторный пересчёт'),
              ),
            ],
          );
        },
      ),
    );
    whole.dispose();
    extra.dispose();
    return result;
  }

  Future<List<List<double>>?> _confirmationSignature() async {
    final pad = _SignatureController();
    var confirmed = false;
    final result = await showDialog<List<List<double>>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Подтвердить результаты переучёта'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сотрудник: ${_draft!.employeeName}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Пересчитано: ${_draft!.totalCount} из ${_draft!.totalCount} позиций',
                  ),
                  Text(
                    'Активное время: ${formatDurationSeconds(_activeSeconds)}',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: (value) =>
                        setState(() => confirmed = value == true),
                    title: const Text(
                      'Подтверждаю, что все позиции физически пересчитаны, а введённые значения соответствуют фактическому наличию.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Подпись сотрудника',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  AnimatedBuilder(
                    animation: pad,
                    builder: (context, _) => Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: GestureDetector(
                        onPanStart: (details) =>
                            pad.start(details.localPosition),
                        onPanUpdate: (details) =>
                            pad.add(details.localPosition),
                        onPanEnd: (_) => pad.endStroke(),
                        child: CustomPaint(
                          painter: _SignaturePainter(pad.points),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: pad.clear,
                      icon: const Icon(Icons.clear),
                      label: const Text('Очистить подпись'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (!confirmed) {
                  showErrorSnack(
                    dialogContext,
                    'Подтвердите результаты переучёта',
                  );
                  return;
                }
                if (pad.serialized.length < 4) {
                  showErrorSnack(dialogContext, 'Поставьте подпись');
                  return;
                }
                Navigator.pop(dialogContext, pad.serialized);
              },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Завершить переучёт'),
            ),
          ],
        ),
      ),
    );
    pad.dispose();
    return result;
  }

  Future<void> _submit() async {
    final draft = _draft;
    if (draft == null || _submitting) return;
    if (_filledCount != draft.totalCount) {
      setState(() => _listFilter = _StocktakeListFilter.unfilled);
      showErrorSnack(
        context,
        'Не заполнено ${draft.totalCount - _filledCount} позиций. Для завершения нужно пересчитать весь склад.',
      );
      return;
    }
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    for (final line in draft.lines) {
      final entry = _entries[line.productId]!;
      await widget.controller.saveStocktakeDraftLine(
        draftId: draft.id,
        productId: line.productId,
        wholePackages: int.tryParse(entry.whole.text),
        extraAmount: line.stockUnit == StockUnit.piece
            ? 0
            : int.tryParse(entry.extra.text),
      );
    }
    if (!await _performMandatoryRechecks()) return;
    if (!mounted) return;
    final signature = await _confirmationSignature();
    if (!mounted || signature == null) return;

    setState(() => _submitting = true);
    _pauseClock();
    try {
      await _noteStore.save(
        draft.id,
        comments: _comments,
        rechecked: _rechecked,
      );
      final operationId = await widget.controller.completeStocktakeDraft(
        draft.id,
        _activeSeconds,
        comments: _comments,
        recheckedProductIds: _rechecked,
        signaturePoints: signature,
      );
      await _noteStore.clear(draft.id);
      if (!mounted) return;
      StockOperation? operation;
      for (final item in widget.controller.operations) {
        if (item.id == operationId) {
          operation = item;
          break;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Переучёт завершён. Остатки и история обновлены у всех устройств.',
          ),
          action: operation == null
              ? null
              : SnackBarAction(
                  label: 'PDF',
                  onPressed: () => PdfExportService.exportOperation(operation!),
                ),
        ),
      );
      widget.onCompleted();
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
        setState(() => _submitting = false);
        _startClock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final draft = _draft;
    if (draft == null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Переучёт не открыт',
          message: 'Вернитесь назад и откройте раздел ещё раз.',
          action: FilledButton(
            onPressed: widget.onCompleted,
            child: const Text('Назад'),
          ),
        ),
      );
    }
    final visible = _visibleLines();
    final grouped = <String, List<SavedStocktakeLine>>{};
    for (final line in visible) {
      grouped.putIfAbsent(line.categoryName, () => []).add(line);
    }
    final filled = _filledCount;
    final complete = filled == draft.totalCount;
    final platform = Theme.of(context).platform;
    final compactMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(
        title: Text('Переучёт • ${draft.employeeName}'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                formatDurationSeconds(_activeSeconds),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              compactMobile ? 10 : 16,
              compactMobile ? 7 : 12,
              compactMobile ? 10 : 16,
              compactMobile ? 6 : 10,
            ),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: draft.totalCount == 0
                            ? 0
                            : filled / draft.totalCount,
                        minHeight: 9,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$filled / ${draft.totalCount}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                if (compactMobile)
                  SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.search, size: 18),
                              prefixIconConstraints: BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              hintText: 'Поиск',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        SizedBox(
                          height: 42,
                          child: FilledButton.tonalIcon(
                            onPressed: _submitting ? null : _scanWorkflow,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const BaliNavIcon(
                              kind: BaliNavIconKind.scan,
                              active: true,
                              size: 18,
                            ),
                            label: const Text(
                              'Скан',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _submitting ? null : _scanWorkflow,
                        icon: const BaliNavIcon(
                          kind: BaliNavIconKind.scan,
                          active: true,
                          size: 20,
                        ),
                        label: const Text('Сканировать товар'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _manualCode,
                        icon: const Icon(Icons.pin_outlined),
                        label: const Text('Ввести код товара'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Название / категория / код товара',
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                if (compactMobile)
                  SizedBox(
                    height: 33,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          selected: _listFilter == _StocktakeListFilter.all,
                          onSelected: (_) => setState(
                            () => _listFilter = _StocktakeListFilter.all,
                          ),
                          label: Text(
                            'Все ${draft.totalCount}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 5),
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          selected:
                              _listFilter == _StocktakeListFilter.unfilled,
                          onSelected: (_) => setState(
                            () => _listFilter = _StocktakeListFilter.unfilled,
                          ),
                          label: Text(
                            'Не введено ${draft.totalCount - filled}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 5),
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          selected: _listFilter == _StocktakeListFilter.filled,
                          onSelected: (_) => setState(
                            () => _listFilter = _StocktakeListFilter.filled,
                          ),
                          label: Text(
                            'Введено $filled',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        selected: _listFilter == _StocktakeListFilter.all,
                        onSelected: (_) => setState(
                          () => _listFilter = _StocktakeListFilter.all,
                        ),
                        avatar: const Icon(Icons.view_list_outlined, size: 18),
                        label: Text('Все • ${draft.totalCount}'),
                      ),
                      ChoiceChip(
                        selected: _listFilter == _StocktakeListFilter.unfilled,
                        onSelected: (_) => setState(
                          () => _listFilter = _StocktakeListFilter.unfilled,
                        ),
                        avatar: const Icon(Icons.pending_actions, size: 18),
                        label: Text(
                          'Не введено • ${draft.totalCount - filled}',
                        ),
                      ),
                      ChoiceChip(
                        selected: _listFilter == _StocktakeListFilter.filled,
                        onSelected: (_) => setState(
                          () => _listFilter = _StocktakeListFilter.filled,
                        ),
                        avatar: const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                        ),
                        label: Text('Введено • $filled'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (widget.controller.syncWarning != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: InfoBanner(
                icon: Icons.cloud_off,
                text: widget.controller.syncWarning!,
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Ничего не найдено',
                    message: 'Измените поиск или выберите другой фильтр.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                    children: [
                      for (final group in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                          child: Text(
                            group.key.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF39FF6A),
                              letterSpacing: .5,
                            ),
                          ),
                        ),
                        for (final line in group.value) ...[
                          _lineCard(line),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
      bottomSheet: Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    complete
                        ? 'Все ${draft.totalCount} позиций заполнены. Перед завершением система проверит крупные расхождения.'
                        : 'Осталось заполнить: ${draft.totalCount - filled}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: complete
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: complete && !_submitting ? _submit : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('ЗАВЕРШИТЬ ПЕРЕУЧЁТ'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lineCard(SavedStocktakeLine line) {
    final entry = _entries[line.productId]!;
    final filled = _isFilled(line);
    final actual = _actualTotal(line);
    final diff = actual == null || !line.beforeInitialized
        ? null
        : actual - line.beforeTotal;
    final suspicious = _isSuspicious(line);
    final wasRechecked = _rechecked.contains(line.productId);
    final comment = _comments[line.productId] ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.productName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (wasRechecked)
                  const Chip(
                    avatar: Icon(Icons.verified, size: 17),
                    label: Text('перепроверено'),
                  ),
                if (suspicious && !wasRechecked)
                  Chip(
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: const Text('нужен повторный пересчёт'),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: Icon(
                  filled ? Icons.check_circle : Icons.pending_actions,
                  size: 18,
                ),
                label: Text(filled ? 'ДАННЫЕ ВВЕДЕНЫ' : 'НЕ ВВЕДЕНО'),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              line.beforeInitialized
                  ? 'Расчётный остаток до переучёта: ${formatStockParts(line.beforeTotal, line.packageSize, line.stockUnit)}'
                  : 'Первичная инвентаризация — предыдущий остаток не задан',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (line.stockUnit == StockUnit.piece)
              IntegerField(
                controller: entry.whole,
                label: 'Фактически, шт.',
                min: 0,
                onChanged: (_) => _changed(line),
              )
            else
              TwoFields(
                first: IntegerField(
                  controller: entry.whole,
                  label: line.stockUnit == StockUnit.ml
                      ? 'Целых бутылок'
                      : 'Целых упаковок',
                  min: 0,
                  onChanged: (_) => _changed(line),
                ),
                second: IntegerField(
                  controller: entry.extra,
                  label: 'Доп. остаток, ${line.stockUnit.symbol}',
                  min: 0,
                  validator: (value) {
                    final base = integerValidator(value, min: 0);
                    if (base != null) return base;
                    final parsed = int.tryParse(value ?? '');
                    return parsed != null && parsed >= line.packageSize
                        ? 'Меньше ${line.packageSize}'
                        : null;
                  },
                  onChanged: (_) => _changed(line),
                ),
              ),
            if (diff != null) ...[
              const SizedBox(height: 8),
              Text(
                'Расхождение: ${diff >= 0 ? '+' : '−'}${formatTotalAmount(diff.abs(), line.stockUnit)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: diff == 0
                      ? Theme.of(context).colorScheme.primary
                      : (diff < 0
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.tertiary),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              initialValue: comment,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Комментарий к позиции (необязательно)',
                hintText: 'Например: бой, две открытые бутылки, найдено на втором баре',
              ),
              onChanged: (value) => _commentChanged(line.productId, value),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DraftAction { resume, restart, cancel }

enum _StocktakeListFilter { all, unfilled, filled }

enum _QuickCountResult { saved, savedAndScanNext }

class _CountEntry {
  _CountEntry({required String whole, required String extra})
    : whole = TextEditingController(text: whole),
      extra = TextEditingController(text: extra);

  final TextEditingController whole;
  final TextEditingController extra;

  void dispose() {
    whole.dispose();
    extra.dispose();
  }
}

class _SignatureController extends ChangeNotifier {
  final List<Offset?> points = [];

  void start(Offset value) {
    points.add(value);
    notifyListeners();
  }

  void add(Offset value) {
    points.add(value);
    notifyListeners();
  }

  void endStroke() {
    points.add(null);
    notifyListeners();
  }

  void clear() {
    points.clear();
    notifyListeners();
  }

  List<List<double>> get serialized => points
      .whereType<Offset>()
      .map((point) => <double>[point.dx, point.dy])
      .toList(growable: false);
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.points);
  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.points.length != points.length;
}
