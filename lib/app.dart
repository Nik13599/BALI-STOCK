import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'controller.dart';
import 'screens/control_screen.dart';
import 'screens/delivery_screen.dart';
import 'screens/history_overview_screen.dart';
import 'screens/stock_overview_screen.dart';
import 'screens/stocktake_v2_screen.dart';
import 'widgets/common.dart';
import 'widgets/pin_value_dialog.dart';

class BaliStockApp extends StatelessWidget {
  const BaliStockApp({super.key, required this.controller});

  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BALI STOCK',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF26A649), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0D0F10),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero, elevation: 0),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        useMaterial3: true,
      ),
      home: BaliStockShell(controller: controller),
    );
  }
}

class BaliStockShell extends StatefulWidget {
  const BaliStockShell({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<BaliStockShell> createState() => _BaliStockShellState();
}

class _BaliStockShellState extends State<BaliStockShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  static const _mobileDestinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Склад'),
    NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Поставка'),
    NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Переучёт'),
    NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_toggle_off), label: 'История'),
    NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Контроль'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.onAppResumed();
    }
  }

  Future<void> _select(int index) async {
    if (index == _selectedIndex) return;
    if (index == 1 || index == 2) {
      final pin = await showOperationPinValueDialog(context);
      if (!mounted || pin == null) return;
      try {
        await widget.controller.setOperationSessionPin(pin);
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, e);
        return;
      }
    }
    if (mounted) setState(() => _selectedIndex = index);
  }

  Widget _page() {
    switch (_selectedIndex) {
      case 1:
        return DeliveryScreen(controller: widget.controller);
      case 2:
        return StocktakeV2Screen(
          controller: widget.controller,
          onCompleted: () {
            widget.controller.clearOperationSessionPin();
            setState(() => _selectedIndex = 0);
          },
        );
      case 3:
        return HistoryOverviewScreen(controller: widget.controller);
      case 4:
        return ControlScreen(controller: widget.controller);
      case 0:
      default:
        return StockOverviewScreen(controller: widget.controller);
    }
  }

  Widget _pageWithSyncStatus() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final warning = widget.controller.syncWarning?.trim();
        final online = widget.controller.sharedOnline;
        final hasWarning = warning != null && warning.isNotEmpty;
        final text = hasWarning
            ? warning
            : online
                ? 'Синхронизировано с общей базой'
                : 'Офлайн — склад доступен локально';
        final color = hasWarning || !online ? const Color(0xFFFFCB5C) : const Color(0xFF39FF6A);
        final icon = hasWarning || !online ? Icons.cloud_off_outlined : Icons.cloud_done_outlined;

        return Column(
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                color: const Color(0xFF111713),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _page()),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    minWidth: 92,
                    extended: constraints.maxWidth >= 1180,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _select,
                    leading: const Padding(
                      padding: EdgeInsets.fromLTRB(12, 14, 12, 24),
                      child: _BrandMark(),
                    ),
                    destinations: const [
                      NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: Text('Склад')),
                      NavigationRailDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: Text('Поставка')),
                      NavigationRailDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: Text('Переучёт')),
                      NavigationRailDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_toggle_off), label: Text('История')),
                      NavigationRailDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: Text('Контроль')),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _pageWithSyncStatus()),
              ],
            ),
          );
        }

        return Scaffold(
          body: _pageWithSyncStatus(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _select,
            destinations: _mobileDestinations,
          ),
        );
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 64,
            height: 64,
            child: SvgPicture.asset(
              'assets/branding/bali_stock_logo.svg',
              fit: BoxFit.cover,
              semanticsLabel: 'BALI STOCK',
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('BALI STOCK', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: .3)),
      ],
    );
  }
}
