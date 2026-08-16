import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'controller.dart';
import 'screens/delivery_screen.dart';
import 'screens/history_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/stocktake_screen.dart';
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
    // Do not clear the in-memory PIN merely because the user navigated away.
    // StocktakeScreen.dispose() may still be flushing the local draft status
    // to the shared backend. Every new protected entry prompts for PIN anyway,
    // and the value never leaves process memory or gets written to history.
    if (mounted) setState(() => _selectedIndex = index);
  }

  Widget _page() {
    switch (_selectedIndex) {
      case 1:
        return DeliveryScreen(controller: widget.controller);
      case 2:
        return StocktakeScreen(
          controller: widget.controller,
          onCompleted: () {
            widget.controller.clearOperationSessionPin();
            setState(() => _selectedIndex = 0);
          },
        );
      case 3:
        return HistoryScreen(controller: widget.controller);
      case 0:
      default:
        return StockScreen(controller: widget.controller);
    }
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
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _page()),
              ],
            ),
          );
        }

        return Scaffold(
          body: _page(),
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
