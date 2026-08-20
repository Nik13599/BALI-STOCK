# BALI STOCK 1.0.1

Кроссплатформенное приложение складского учёта и переучёта для BALI.

## Платформы

- Windows 10/11 x64 — полноценный установщик `.exe`.
- Android — универсальный установочный `.apk`.
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
- iPhone Web Clip использует стабильный Supabase runtime без зависимости от GitHub Pages/raw GitHub и имеет защитный fallback обновления складского снимка, чтобы отсутствие `snapshot()` не блокировало интерфейс.
- Кастомные навигационные иконки используются в Flutter-клиентах и iPhone Web Clip.

## Установщики

GitHub Actions workflow `Build BALI STOCK` формирует следующие артефакты:

- `BALI-STOCK-Windows-Installer` → `BALI-STOCK-Windows-v14-Setup.exe`.
- `BALI-STOCK-Android-Installer` → `BALI-STOCK-Android-v14.apk`.
- `BALI-STOCK-iPhone-WebClip` → `BALI-STOCK-iPhone.mobileconfig`.
- `BALI-STOCK-iOS-unsigned` → архив нативного `Runner.app` без Apple-подписи.

### Windows

Запустите `BALI-STOCK-Windows-v14-Setup.exe`. По умолчанию приложение устанавливается в профиль текущего пользователя и не требует установки Flutter или Visual C++ вручную.

### Android

Откройте `BALI-STOCK-Android-v14.apk` на устройстве и разрешите установку приложений из выбранного источника, если Android запросит это разрешение.

### iPhone / iPad

Откройте `BALI-STOCK-iPhone.mobileconfig` на устройстве. Затем установите загруженный профиль через настройки iOS. Профиль добавит BALI STOCK на экран Домой и будет открывать актуальную серверную Web Clip-версию через стабильный Supabase runtime.

Повторно устанавливать профиль для обычных обновлений интерфейса не требуется: production runtime обновляется за тем же URL.

## Проверка качества перед сборкой

Релизный workflow обязательно выполняет:

1. `python tool/code_health_check.py --fail-on-orphans`
2. `flutter analyze`
3. `flutter test`
4. release-сборки Android / Windows / iOS

Отдельный workflow `iPhone Runtime Smoke` проверяет production Web Clip, отсутствие GitHub runtime-зависимостей, навигацию, синтаксис встроенного JavaScript и регрессию, при которой `snapshot()` отсутствует в базовом iPhone runtime.

`tool/code_health_check.py` проверяет повторяющиеся импорты, последовательные дубли строк, хвостовые пробелы, дубли SKU в стартовом каталоге и Dart-файлы, которые больше не достижимы от `lib/main.dart`.

## Основная структура

- `lib/app.dart` — оболочка и навигация приложения.
- `lib/v14_controller.dart` — orchestration и offline-first операции.
- `lib/v14_models.dart` — продажные настройки и экономика SKU.
- `lib/data/` — SQLite, Supabase API, sync/outbox и локальные кэши.
- `lib/screens/` — рабочие экраны склада.
- `ios-web/` — iPhone Web Clip UI и compatibility-модули.
- `tool/generate_mobileconfig.py` — генератор iPhone-профиля.
- `installer/windows/bali_stock.iss` — Windows installer definition.

## Версия

Текущая версия приложения: `1.0.1+101`.
