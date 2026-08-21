from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_flutter() -> None:
    path = ROOT / 'lib/screens/stocktake_v2_screen.dart'
    text = path.read_text(encoding='utf-8')
    if 'final compactMobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS;' not in text:
        old = '    final complete = filled == draft.totalCount;\n\n    return Scaffold('
        new = (
            '    final complete = filled == draft.totalCount;\n'
            '    final platform = Theme.of(context).platform;\n'
            '    final compactMobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS;\n\n'
            '    return Scaffold('
        )
        if old not in text:
            raise SystemExit('Stocktake build marker not found')
        text = text.replace(old, new, 1)

    text = text.replace(
        '            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),',
        '            padding: EdgeInsets.fromLTRB(compactMobile ? 10 : 16, compactMobile ? 7 : 12, compactMobile ? 10 : 16, compactMobile ? 6 : 10),',
        1,
    )

    start_marker = '''                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _submitting ? null : _scanWorkflow,
'''
    end_marker = '''                    ChoiceChip(
                      selected: _listFilter == _StocktakeListFilter.filled,
                      onSelected: (_) => setState(() => _listFilter = _StocktakeListFilter.filled),
                      avatar: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text('Введено • $filled'),
                    ),
                  ],
                ),
'''
    if start_marker in text:
        start = text.index(start_marker)
        end = text.index(end_marker, start) + len(end_marker)
        replacement = '''                const SizedBox(height: 7),
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
                              prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
                              hintText: 'Поиск',
                              contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        SizedBox(
                          height: 42,
                          child: FilledButton.tonalIcon(
                            onPressed: _submitting ? null : _scanWorkflow,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 9),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const BaliNavIcon(kind: BaliNavIconKind.scan, active: true, size: 18),
                            label: const Text('Скан', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
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
                        icon: const BaliNavIcon(kind: BaliNavIconKind.scan, active: true, size: 20),
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
                          onSelected: (_) => setState(() => _listFilter = _StocktakeListFilter.all),
                          label: Text('Все ${draft.totalCount}', style: const TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 5),
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          selected: _listFilter == _StocktakeListFilter.unfilled,
                          onSelected: (_) => setState(() => _listFilter = _StocktakeListFilter.unfilled),
                          label: Text('Не введено ${draft.totalCount - filled}', style: const TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 5),
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          selected: _listFilter == _StocktakeListFilter.filled,
                          onSelected: (_) => setState(() => _listFilter = _StocktakeListFilter.filled),
                          label: Text('Введено $filled', style: const TextStyle(fontSize: 11)),
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
                        onSelected: (_) => setState(() => _listFilter = _StocktakeListFilter.all),
                        avatar: const Icon(Icons.view_list_outlined, size: 18),
                        label: Text('Все • ${draft.totalCount}'),
                      ),
                      ChoiceChip(
                        selected: _listFilter == _StocktakeListFilter.unfilled,
                        onSelected: (_) => setState(() => _listFilter = _StocktakeListFilter.unfilled),
                        avatar: const Icon(Icons.pending_actions, size: 18),
                        label: Text('Не введено • ${draft.totalCount - filled}'),
                      ),
                      ChoiceChip(
                        selected: _listFilter == _StocktakeListFilter.filled,
                        onSelected: (_) => setState(() => _listFilter = _StocktakeListFilter.filled),
                        avatar: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text('Введено • $filled'),
                      ),
                    ],
                  ),
'''
        text = text[:start] + replacement + text[end:]
    elif "label: const Text('Скан', style: TextStyle(fontSize: 12" not in text:
        raise SystemExit('Stocktake toolbar block not found')

    path.write_text(text, encoding='utf-8')


def patch_ios_builder() -> None:
    path = ROOT / 'tool/build_ios_production_runtime.py'
    text = path.read_text(encoding='utf-8')
    text = text.replace(
        'RUNTIME_URL = "https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-ios-runtime"',
        'RUNTIME_URL = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime/production/bali-stock.html"',
        1,
    )
    constant = "MOBILE_STOCKTAKE_MODULE = ROOT / \"ios-web\" / \"mobile-stocktake-compact-v105.js\"\n"
    if constant not in text:
        text = text.replace('MODULES = {', constant + 'MODULES = {', 1)
    injection = '''    mobile_source = MOBILE_STOCKTAKE_MODULE.read_text(encoding="utf-8").replace("</script", "<\\\\/script")
    mobile_script = f'<script id="bali-mobile-stocktake-compact-v105">{mobile_source}</script>'
    html = re.sub(r'<script\\s+id=["\\\']bali-mobile-stocktake-compact-v105["\\\'][^>]*>[\\s\\S]*?</script>', '', html, count=1, flags=re.I)
    html = html.replace("</body>", mobile_script + "</body>", 1)

'''
    marker = '    html = re.sub(\n        r"window\\.__BALI_STOCK_SUPABASE_RUNTIME__'
    if 'mobile_script = f\'<script id="bali-mobile-stocktake-compact-v105">' not in text:
        pos = text.find(marker)
        if pos < 0:
            raise SystemExit('iPhone builder insertion marker not found')
        text = text[:pos] + injection + text[pos:]
    if '"__BALI_STOCK_MOBILE_STOCKTAKE_COMPACT__",' not in text:
        text = text.replace(
            '        "__BALI_STOCK_V16_CATALOG_HISTORY__",',
            '        "__BALI_STOCK_V16_CATALOG_HISTORY__",\n        "__BALI_STOCK_MOBILE_STOCKTAKE_COMPACT__",',
            1,
        )
    path.write_text(text, encoding='utf-8')


def bump_version() -> None:
    path = ROOT / 'pubspec.yaml'
    text = path.read_text(encoding='utf-8')
    text, count = re.subn(r'^version:\s*1\.0\.4\+104\s*$', 'version: 1.0.5+105', text, count=1, flags=re.M)
    if count != 1 and 'version: 1.0.5+105' not in text:
        raise SystemExit('Version bump marker not found')
    path.write_text(text, encoding='utf-8')


def verify() -> None:
    flutter = (ROOT / 'lib/screens/stocktake_v2_screen.dart').read_text(encoding='utf-8')
    builder = (ROOT / 'tool/build_ios_production_runtime.py').read_text(encoding='utf-8')
    pubspec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    module = (ROOT / 'ios-web/mobile-stocktake-compact-v105.js').read_text(encoding='utf-8')
    assert 'compactMobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS' in flutter
    assert "label: const Text('Скан'" in flutter
    assert "hintText: 'Поиск'" in flutter
    assert 'bali-mobile-stocktake-compact-v105' in builder
    assert '__BALI_STOCK_MOBILE_STOCKTAKE_COMPACT__' in module
    assert 'version: 1.0.5+105' in pubspec


if __name__ == '__main__':
    patch_flutter()
    patch_ios_builder()
    bump_version()
    verify()
    print('mobile stocktake compact patch: OK')
