$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Invoke-NativeStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Command
  )
  Write-Host "== $Name =="
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE"
  }
}

Invoke-NativeStep 'Enable Windows desktop' { flutter config --enable-windows-desktop }
Invoke-NativeStep 'Generate Windows platform wrapper' { flutter create . --project-name bali_stock --org com.bali.stock --platforms=windows,android,ios }
Invoke-NativeStep 'Resolve Flutter dependencies' { flutter pub get }
Invoke-NativeStep 'Generate application icons' { dart run flutter_launcher_icons }
Invoke-NativeStep 'Build Windows release' { flutter build windows --release }

& "$PSScriptRoot/bundle_windows_vc_runtime.ps1"
if ($LASTEXITCODE -ne 0) {
  throw "VC++ runtime bundling failed with exit code $LASTEXITCODE"
}
