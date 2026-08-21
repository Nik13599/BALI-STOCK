# BALI STOCK 1.0.7

Кроссплатформенное приложение складского учёта и переучёта для BALI.

## Платформы

- Windows 10/11 x64 — полноценный production-установщик `.exe`.
- Android — production `.apk` с постоянной signing identity для обновлений поверх установленной версии.
- iPhone/iPad — профиль `.mobileconfig`, который устанавливает BALI STOCK как Web Clip на экран Домой.
- Native iOS Flutter build — формируется отдельно без подписи; для установки как обычного `.ipa` требуется Apple signing / provisioning profile.

## Что входит в 1.0.x

- Главная с быстрым поиском товара, QR/штрихкодом и ручным вводом кода.
- Склад в трёх режимах: компактно, подробно и таблица.
- Категории, поставщики, места хранения, закупки, поставки, переучёты, списания, перемещения и корректировки.
- Карточка SKU с фото, закупочной ценой, продажей бутылкой, произвольными порциями, себестоимостью, прибылью, наценкой, маржой и стоимостью остатка.
- Закупочная цена меняется только через фактическую поставку. Поставка без закупочной цены блокируется.
- Полный переучёт с черновиками и фиксацией длительности.
- Точечный переучёт с причиной, ФИО, устройством, `было → разница → стало` и offline-first синхронизацией.
- История операций и история карточек/цен внутри раздела «Настройки / Контроль»; отдельной нижней вкладки «История» нет.
- PDF текущих остатков и операций.
- Общая Supabase-база и локальный SQLite-кэш для автономной работы Flutter-клиентов.
- Пользовательские пароли/PIN не используются.
- iPhone Web Clip сохраняет прежний стабильный Supabase URL и исходный интерфейс 1.0.5. Edge Function переключает его на camera-safe HTTPS-документ только после проверки версии и визуального контракта.
- iPhone-сканер работает в непрерывном live-режиме: достаточно навести камеру на QR-код или товарный штрихкод, снимок и подтверждение не требуются.
- Логотипы, экраны, навигационные значки и UI-модули защищены автоматической проверкой и не изменяются техническим обновлением.
- Кастомные навигационные иконки используются в Flutter-клиентах и iPhone Web Clip.

## Production-установщики

Workflow `Release BALI STOCK Production` формирует стабильные файлы:

- `BALI-STOCK-Windows-Setup.exe`
- `BALI-STOCK-Android.apk`
- `BALI-STOCK-iPhone.mobileconfig`
- `BALI-STOCK-SHA256.txt`

Обычный workflow `Build BALI STOCK` создаёт только CI-артефакты для проверки и не должен использоваться как production-канал установки.

### Windows

Запустите `BALI-STOCK-Windows-Setup.exe`. При следующем production-релизе новый Setup устанавливается поверх предыдущей версии благодаря постоянному AppId.

### Android

Откройте `BALI-STOCK-Android.apk` на устройстве и разрешите установку приложений из выбранного источника, если Android запросит это разрешение. Начиная с production-базы 1.0.0 последующие APK подписываются той же production identity и устанавливаются поверх предыдущей production-версии.

### iPhone / iPad

Откройте `BALI-STOCK-iPhone.mobileconfig` на устройстве. Затем установите загруженный профиль через настройки iOS. Профиль добавит BALI STOCK на экран Домой и будет открывать актуальную Web Clip-версию через прежний стабильный Supabase URL.

Профиль, URL, подпись и значок совпадают с production-версией 1.0.5, поэтому переустанавливать уже установленный профиль из-за этого технического обновления не требуется.

## Проверка качества перед release

Production и PR-gate выполняют:

1. `python tool/code_health_check.py --fail-on-orphans --fail-on-clones`
2. `flutter analyze`
3. `flutter test`
4. release-сборки Android / Windows / iOS
5. проверку постоянной Android production-подписи
6. проверку iPhone runtime, HTTPS `Content-Type`, встроенного сканера и всех JavaScript-блоков
7. проверку защищённого выбора iPhone runtime и отсутствия пользовательских password/PIN flow

Отдельные workflow `iPhone Runtime Smoke` и `iPhone Production Runtime Builder Smoke` проверяют production Web Clip, навигацию, синтаксис встроенного JavaScript, camera-safe runtime, исходный визуальный контракт, встроенную библиотеку сканера и регрессию, при которой `snapshot()` отсутствует в базовом iPhone runtime.

`tool/code_health_check.py` проверяет повторяющиеся импорты, последовательные дубли строк, клоны крупных блоков, хвостовые пробелы, дубли SKU в стартовом каталоге и Dart-файлы, которые больше не достижимы от `lib/main.dart`.

## Основная структура

- `lib/app.dart` — оболочка и навигация приложения.
- `lib/v14_controller.dart` — orchestration и offline-first операции.
- `lib/v14_models.dart` — продажные настройки и экономика SKU.
- `lib/data/` — SQLite, Supabase API, sync/outbox и локальные кэши.
- `lib/screens/` — рабочие экраны склада.
- `ios-web/` — iPhone Web Clip UI и compatibility-модули.
- `tool/generate_mobileconfig.py` — генератор iPhone-профиля.
- `tool/build_ios_production_runtime.py` — сборка самодостаточного iPhone runtime.
- `installer/windows/bali_stock.iss` — Windows installer definition.

## Версия

Текущая release candidate: `1.0.7+107`.
