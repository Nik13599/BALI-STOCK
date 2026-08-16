$ErrorActionPreference = 'Stop'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter SDK не найден в PATH. Установите Flutter и повторите запуск.'
}

flutter create . --project-name bali_stock --org com.bali.stock --platforms=windows,android,ios
flutter pub get

Write-Host 'BALI STOCK готов к запуску.' -ForegroundColor Green
Write-Host 'Windows: flutter run -d windows'
Write-Host 'Android: flutter devices; flutter run -d <device>'
Write-Host 'iOS собирается на macOS с Xcode.'
