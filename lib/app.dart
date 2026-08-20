import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'screens/control_hub_v14_screen.dart';
import 'screens/delivery_screen_v15.dart';
import 'screens/home_v14_screen.dart';
import 'screens/purchase_screen.dart';
import 'screens/stock_v14_screen.dart';
import 'screens/stocktake_v2_screen.dart';
import 'security.dart';
import 'v14_controller.dart';
import 'widgets/bali_nav_icon.dart';
import 'widgets/common.dart';

class BaliStockApp extends StatelessWidget {
  const BaliStockApp({super.key, required this.controller});

  final V14WarehouseController controller;

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

  final V14WarehouseController controller;

  @override
  State<BaliStockShell> createState() => _BaliStockShellState();
}

class _BaliStockShellState extends State<BaliStockShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  static const _mobileDestinations = <NavigationDestination>[
    NavigationDestination(
      icon: BaliNavIcon(kind: BaliNavIconKind.home),
      selectedIcon: BaliNavIcon(kind: BaliNavIconKind.home, active: true),
      label: 'Главная',
    ),
    NavigationDestination(
      icon: BaliNavIcon(kind: BaliNavIconKind.stock),
      selectedIcon: BaliNavIcon(kind: BaliNavIconKind.stock, active: true),
      label: 'Склад',
    ),
    NavigationDestination(
      icon: BaliNavIcon(kind: BaliNavIconKind.stocktake),
      selectedIcon: BaliNavIcon(kind: BaliNavIconKind.stocktake, active: true),
      label: 'Переучёт',
    ),
    NavigationDestination(
      icon: BaliNavIcon(kind: BaliNavIconKind.purchases),
      selectedIcon: BaliNavIcon(kind: BaliNavIconKind.purchases, active: true),
      label: 'Закупки',
    ),
    NavigationDestination(
      icon: BaliNavIcon(kind: BaliNavIconKind.delivery),
      selectedIcon: BaliNavIcon(kind: BaliNavIconKind.delivery, active: true),
      label: 'Поставка',
    ),
    NavigationDestination(
      icon: BaliNavIcon(kind: BaliNavIconKind.settings),
      selectedIcon: BaliNavIcon(kind: BaliNavIconKind.settings, active: true),
      label: 'Настройки',
    ),
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
    if (state == AppLifecycleState.resumed) widget.controller.onAppResumed();
  }

  void _select(int index) {
    if (index == _selectedIndex) return;

    // Navigation must never wait for Supabase/SQLite. Paint the selected
    // section first, then refresh the automatic operation session in the
    // background. This is especially important on Windows, where waiting for
    // a full snapshot made Stocktake and Delivery feel unresponsive.
    setState(() => _selectedIndex = index);

    if (index == 2 || index == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_prepareOperationSession());
      });
    }
  }

  Future<void> _prepareOperationSession() async {
    try {
      await widget.controller.setOperationSessionPin(operationSessionCredential);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Widget _page() {
    switch (_selectedIndex) {
      case 1:
        return StockV14Screen(controller: widget.controller);
      case 2:
        return StocktakeV2Screen(
          controller: widget.controller,
          onCompleted: () {
            widget.controller.clearOperationSessionPin();
            setState(() => _selectedIndex = 0);
          },
        );
      case 3:
        return PurchaseScreen(controller: widget.controller);
      case 4:
        return DeliveryScreenV15(controller: widget.controller);
      case 5:
        return ControlHubV14Screen(controller: widget.controller);
      case 0:
      default:
        return HomeV14Screen(controller: widget.controller);
    }
  }

  Widget _pageWithSyncStatus() {
    return AnimatedBuilder(
      animation: widget.controller,
      child: _page(),
      builder: (context, page) {
        final warning = widget.controller.syncWarning?.trim();
        final online = widget.controller.sharedOnline;
        final hasWarning = warning != null && warning.isNotEmpty;
        final pending = widget.controller.pendingSyncCount;
        final text = hasWarning
            ? warning
            : pending > 0
                ? 'Ожидает синхронизации: $pending'
                : online
                    ? 'Синхронизировано с общей базой'
                    : 'Офлайн — склад доступен локально';
        final color = hasWarning || !online || pending > 0 ? const Color(0xFFFFCB5C) : const Color(0xFF39FF6A);

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
                    BaliNavIcon(kind: BaliNavIconKind.sync, active: online && !hasWarning && pending == 0, size: 16),
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
            Expanded(child: page!),
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
                      NavigationRailDestination(
                        icon: BaliNavIcon(kind: BaliNavIconKind.home),
                        selectedIcon: BaliNavIcon(kind: BaliNavIconKind.home, active: true),
                        label: Text('Главная'),
                      ),
                      NavigationRailDestination(
                        icon: BaliNavIcon(kind: BaliNavIconKind.stock),
                        selectedIcon: BaliNavIcon(kind: BaliNavIconKind.stock, active: true),
                        label: Text('Склад'),
                      ),
                      NavigationRailDestination(
                        icon: BaliNavIcon(kind: BaliNavIconKind.stocktake),
                        selectedIcon: BaliNavIcon(kind: BaliNavIconKind.stocktake, active: true),
                        label: Text('Переучёт'),
                      ),
                      NavigationRailDestination(
                        icon: BaliNavIcon(kind: BaliNavIconKind.purchases),
                        selectedIcon: BaliNavIcon(kind: BaliNavIconKind.purchases, active: true),
                        label: Text('Закупки'),
                      ),
                      NavigationRailDestination(
                        icon: BaliNavIcon(kind: BaliNavIconKind.delivery),
                        selectedIcon: BaliNavIcon(kind: BaliNavIconKind.delivery, active: true),
                        label: Text('Поставка'),
                      ),
                      NavigationRailDestination(
                        icon: BaliNavIcon(kind: BaliNavIconKind.settings),
                        selectedIcon: BaliNavIcon(kind: BaliNavIconKind.settings, active: true),
                        label: Text('Настройки'),
                      ),
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
