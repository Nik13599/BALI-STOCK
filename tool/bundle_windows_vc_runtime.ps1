$ErrorActionPreference = 'Stop'

$release = Resolve-Path 'build/windows/x64/runner/Release'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found' }

$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio C++ tools not found' }

$redistRoot = Join-Path $vs 'VC\Redist\MSVC'
$crt = Get-ChildItem $redistRoot -Directory | Sort-Object Name -Descending | ForEach-Object {
  $candidate = Join-Path $_.FullName 'x64\Microsoft.VC143.CRT'
  if (Test-Path $candidate) { $candidate }
} | Select-Object -First 1
if (-not $crt) { throw 'Microsoft.VC143.CRT x64 redistributable directory not found' }

Copy-Item (Join-Path $crt '*.dll') -Destination $release -Force
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  if (-not (Test-Path (Join-Path $release $dll))) {
    throw "Required VC runtime DLL missing: $dll"
  }
}

Write-Host "Bundled Microsoft VC++ runtime into $release"
