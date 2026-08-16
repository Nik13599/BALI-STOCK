import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key, required this.controller, required this.onCompleted});

  final WarehouseController controller;
  final VoidCallback onCompleted;

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

enum _DraftAction { resume, restart }

class _StocktakeScreenState extends State<StocktakeScreen> with WidgetsBindingObserver {
  StocktakeDraft? _draft;
  final Map<int, TextEditingController> _whole = {};
  final Map<int, TextEditingController> _extra = {};
  final Map<int, GlobalKey> _rowKeys = {};
  final ValueNotifier<int> _activeSeconds = ValueNotifier<int>(0);
  Timer? _timer;
  Future<void> _saveChain = Future<void>.value();
  bool _preparing = true;
  bool _saving = false;
  bool _sessionRunning = false;

  List<SavedStocktakeLine> get _lines => _draft?.lines ?? const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _pauseSession();
    } else if (state == AppLifecycleState.resumed && _draft != null && !_saving) {
      _resumeSession();
    }
  }

  Future<void> _prepare() async {
    try {
      final lastEmployee = await widget.controller.getLastStocktakeEmployee();
      if (!mounted) return;
      final employee = await _askEmployeeName(lastEmployee);
      if (!mounted) return;
      if (employee == null) {
        widget.onCompleted();
        return;
      }

      var draft = await widget.controller.getActiveStocktakeDraft(employee);
      if (!mounted) return;
      if (draft != null) {
        final action = await _askDraftAction(draft);
        if (!mounted) return;
        if (action == _DraftAction.restart) {
          final restart = await _confirmRestart();
          if (!mounted) return;
          if (restart) {
            await widget.controller.deleteStocktakeDraft(draft.id);
            draft = await widget.controller.createStocktakeDraft(employee);
          }
        }
      } else {
        draft = await widget.controller.createStocktakeDraft(employee);
      }

      draft = await widget.controller.resumeStocktakeDraft(draft.id);
      if (!mounted) return;
      _loadDraft(draft);
      setState(() => _preparing = false);
      _startTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLastPosition());
    } catch (e) {
      if (!mounted) return;
      setState(() => _preparing = false);
      showErrorSnack(context, e);
    }
  }

  Future<String?> _askEmployeeName(String? initialValue) async {
    final controller = TextEditingController(text: initialValue ?? '');
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Кто проводит переучёт?'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'ФИО сотрудника', hintText: 'Иванов Иван Иванович'),
            onSubmitted: (value) {
              final clean = value.trim();
              if (clean.isNotEmpty) Navigator.of(dialogContext).pop(clean);
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final clean = controller.text.trim();
              if (clean.isEmpty) return;
              Navigator.of(dialogContext).pop(clean);
            },
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<_DraftAction> _askDraftAction(StocktakeDraft draft) async {
    return await showDialog<_DraftAction>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.save_outlined, size: 40),
            title: const Text('У вас есть незавершённый переучёт'),
            content: SizedBox(
              width: 470,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Сотрудник: ${draft.employeeName}'),
                  const SizedBox(height: 6),
                  Text('Начат: ${formatDateTime(draft.startedAt)}'),
                  const SizedBox(height: 6),
                  Text('Заполнено: ${draft.filledCount} из ${draft.totalCount} позиций', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: draft.totalCount == 0 ? 0 : draft.filledCount / draft.totalCount),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(_DraftAction.restart),
                child: const Text('Начать сначала'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(_DraftAction.resume),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Продолжить переучёт'),
              ),
            ],
          ),
        ) ??
        _DraftAction.resume;
  }

  Future<bool> _confirmRestart() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Начать переучёт заново?'),
            content: const Text('Все данные текущего черновика будут удалены.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Начать заново'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _loadDraft(StocktakeDraft draft) {
    _draft = draft;
    _activeSeconds.value = draft.activeSeconds;
    for (final line in draft.lines) {
      _whole[line.productId] = TextEditingController(text: line.wholePackages?.toString() ?? '');
      _extra[line.productId] = TextEditingController(text: line.extraAmount?.toString() ?? '');
      _rowKeys[line.productId] = GlobalKey();
    }
  }

  void _scrollToLastPosition() {
    final productId = _draft?.lastProductId;
    if (productId == null) return;
    final rowContext = _rowKeys[productId]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(rowContext, duration: const Duration(milliseconds: 450), alignment: .2);
    }
  }

  void _startTimer() {
    if (_sessionRunning || _draft == null) return;
    _sessionRunning = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _activeSeconds.value = _activeSeconds.value + 1;
      if (_activeSeconds.value % 15 == 0 && _draft != null) {
        unawaited(widget.controller.saveStocktakeActiveSeconds(_draft!.id, _activeSeconds.value));
      }
    });
  }

  Future<void> _resumeSession() async {
    if (_sessionRunning || _draft == null) return;
    try {
      _draft = await widget.controller.resumeStocktakeDraft(_draft!.id);
      _startTimer();
      if (mounted) setState(() {});
    } catch (_) {
      // If the draft was completed/deleted while the app was paused, the normal
      // refresh path will resolve the state when the user returns to the section.
    }
  }

  Future<void> _pauseSession() async {
    if (!_sessionRunning || _draft == null) return;
    _sessionRunning = false;
    _timer?.cancel();
    _timer = null;
    try {
      await _saveChain;
      await widget.controller.pauseStocktakeDraft(_draft!.id, _activeSeconds.value);
    } catch (_) {
      // Draft line autosaves have already been persisted individually.
    }
  }

  bool _filled(SavedStocktakeLine line) {
    final wholeText = _whole[line.productId]?.text ?? '';
    if (wholeText.isEmpty) return false;
    final whole = int.tryParse(wholeText);
    if (whole == null || whole < 0) return false;
    if (line.stockUnit == StockUnit.piece) return true;

    final extraText = _extra[line.productId]?.text ?? '';
    if (extraText.isEmpty) return false;
    final extra = int.tryParse(extraText);
    return extra != null && extra >= 0 && extra < line.packageSize;
  }

  int get _filledCount => _lines.where(_filled).length;
  bool get _complete => _lines.isNotEmpty && _filledCount == _lines.length;

  void _onValueChanged(SavedStocktakeLine line) {
    if (_draft == null) return;
    final wholeText = _whole[line.productId]!.text;
    final extraText = _extra[line.productId]!.text;
    final whole = wholeText.isEmpty ? null : int.tryParse(wholeText);
    final extra = line.stockUnit == StockUnit.piece ? null : (extraText.isEmpty ? null : int.tryParse(extraText));

    setState(() {});
    _saveChain = _saveChain.then((_) => widget.controller.saveStocktakeDraftLine(
          draftId: _draft!.id,
          productId: line.productId,
          wholePackages: whole,
          extraAmount: extra,
        ));
  }

  Future<void> _submit() async {
    if (!_complete || _draft == null) return;
    setState(() => _saving = true);
    _sessionRunning = false;
    _timer?.cancel();
    _timer = null;

    try {
      await _saveChain;
      await widget.controller.saveStocktakeActiveSeconds(_draft!.id, _activeSeconds.value);
      await widget.controller.completeStocktakeDraft(_draft!.id, _activeSeconds.value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Переучёт завершён. Отчёт и время работы сохранены.')));
      _draft = null;
      widget.onCompleted();
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
        setState(() => _saving = false);
        _sessionRunning = false;
        await _resumeSession();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (_sessionRunning && _draft != null) {
      unawaited(widget.controller.pauseStocktakeDraft(_draft!.id, _activeSeconds.value));
    }
    for (final value in _whole.values) {
      value.dispose();
    }
    for (final value in _extra.values) {
      value.dispose();
    }
    _activeSeconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_preparing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Переучёт')),
        body: EmptyState(
          icon: Icons.fact_check_outlined,
          title: 'Переучёт не начат',
          message: 'Не удалось открыть черновик переучёта.',
          action: FilledButton(onPressed: _prepare, child: const Text('Попробовать снова')),
        ),
      );
    }

    final grouped = <String, List<SavedStocktakeLine>>{};
    for (final line in _lines) {
      grouped.putIfAbsent(line.categoryName, () => []).add(line);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Полный переучёт'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(_draft!.employeeName, style: const TextStyle(fontWeight: FontWeight.w700))),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const InfoBanner(
                  icon: Icons.cloud_done_outlined,
                  text: 'Черновик сохраняется автоматически после каждого изменения. Можно выйти из раздела или закрыть приложение и продолжить позже. Для завершения должны быть заполнены абсолютно все позиции.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    Text('Начало: ${formatDateTime(_draft!.startedAt)}'),
                    ValueListenableBuilder<int>(
                      valueListenable: _activeSeconds,
                      builder: (context, seconds, _) => Text('Активное время: ${formatDurationSeconds(seconds)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _activeSeconds,
                      builder: (context, _, __) {
                        final total = DateTime.now().difference(_draft!.startedAt).inSeconds;
                        return Text('Общий период: ${formatDurationSeconds(total)}');
                      },
                    ),
                    const Chip(avatar: Icon(Icons.play_circle_outline, size: 18), label: Text('В процессе')),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(10),
                        value: _filledCount / _lines.length,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text('$_filledCount / ${_lines.length}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                for (final entry in grouped.entries) ...[
                  _CategoryStocktakeCard(
                    title: entry.key,
                    lines: entry.value,
                    whole: _whole,
                    extra: _extra,
                    rowKeys: _rowKeys,
                    isFilled: _filled,
                    enabled: !_saving,
                    onChanged: _onValueChanged,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_complete)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Не заполнено: ${_lines.length - _filledCount} позиций',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _complete && !_saving ? _submit : null,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_outlined),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('ЗАВЕРШИТЬ ПЕРЕУЧЁТ')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStocktakeCard extends StatelessWidget {
  const _CategoryStocktakeCard({
    required this.title,
    required this.lines,
    required this.whole,
    required this.extra,
    required this.rowKeys,
    required this.isFilled,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final List<SavedStocktakeLine> lines;
  final Map<int, TextEditingController> whole;
  final Map<int, TextEditingController> extra;
  final Map<int, GlobalKey> rowKeys;
  final bool Function(SavedStocktakeLine) isFilled;
  final bool enabled;
  final ValueChanged<SavedStocktakeLine> onChanged;

  @override
  Widget build(BuildContext context) {
    final done = lines.where(isFilled).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('$done / ${lines.length}'),
            const SizedBox(width: 8),
            Icon(done == lines.length ? Icons.check_circle : Icons.pending_outlined, color: done == lines.length ? Theme.of(context).colorScheme.primary : null),
          ],
        ),
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            Container(
              key: rowKeys[lines[i].productId],
              child: _ProductStocktakeRow(
                line: lines[i],
                wholeController: whole[lines[i].productId]!,
                extraController: extra[lines[i].productId]!,
                filled: isFilled(lines[i]),
                enabled: enabled,
                onChanged: () => onChanged(lines[i]),
              ),
            ),
            if (i != lines.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ProductStocktakeRow extends StatelessWidget {
  const _ProductStocktakeRow({
    required this.line,
    required this.wholeController,
    required this.extraController,
    required this.filled,
    required this.enabled,
    required this.onChanged,
  });

  final SavedStocktakeLine line;
  final TextEditingController wholeController;
  final TextEditingController extraController;
  final bool filled;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final before = line.beforeInitialized
        ? formatStockParts(line.beforeTotal, line.packageSize, line.stockUnit)
        : 'остаток ещё не был введён';
    final descriptor = switch (line.stockUnit) {
      StockUnit.ml => 'Бутылка ${formatPackageSize(line.packageSize, line.stockUnit)}',
      StockUnit.gram => 'Упаковка ${formatPackageSize(line.packageSize, line.stockUnit)}',
      StockUnit.piece => 'Штучный учёт',
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(line.productName, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Icon(filled ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: filled ? Theme.of(context).colorScheme.primary : null),
                ],
              ),
              const SizedBox(height: 3),
              Text('$descriptor • до переучёта: $before', style: Theme.of(context).textTheme.bodySmall),
            ],
          );

          final wholeLabel = switch (line.stockUnit) {
            StockUnit.ml => 'Целых бутылок',
            StockUnit.gram => 'Целых упаковок',
            StockUnit.piece => 'Количество, шт.',
          };

          final wholeField = TextField(
            controller: wholeController,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(labelText: wholeLabel, hintText: '0'),
          );

          final fields = line.stockUnit == StockUnit.piece
              ? wholeField
              : Row(
                  children: [
                    Expanded(child: wholeField),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: extraController,
                        enabled: enabled,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => onChanged(),
                        decoration: InputDecoration(
                          labelText: line.stockUnit == StockUnit.ml ? 'Остаток, мл' : 'Остаток, г',
                          hintText: '0',
                          helperText: '< ${line.packageSize} ${line.stockUnit.symbol}',
                        ),
                      ),
                    ),
                  ],
                );

          if (compact) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), fields]);
          return Row(children: [Expanded(flex: 4, child: title), const SizedBox(width: 20), Expanded(flex: 3, child: fields)]);
        },
      ),
    );
  }
}
