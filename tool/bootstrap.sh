#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK не найден в PATH.' >&2
  exit 1
fi

flutter create . --project-name bali_stock --org com.bali.stock --platforms=windows,android,ios
flutter pub get

echo 'BALI STOCK готов к запуску.'
echo 'Android: flutter devices && flutter run -d <device>'
echo 'iOS: flutter run -d <iphone> (только macOS + Xcode)'
echo 'Windows: flutter run -d windows'
