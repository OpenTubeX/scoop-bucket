param(
  [Parameter(Mandatory)] [string] $App
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Installs a manifest from this checkout with Scoop, checks the app, and uninstalls it.

$scoop = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
$scoopCommand = Join-Path $scoop 'shims\scoop.cmd'

# Run the installer and Scoop in separate processes so this script's strict mode does not apply to them.
if (-not (Test-Path -LiteralPath $scoopCommand)) {
  # ScoopInstaller/Install, pinned to a reviewed commit.
  $installer = Join-Path ([System.IO.Path]::GetTempPath()) 'install-scoop.ps1'
  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/ScoopInstaller/Install/1e2f334083d609986d8c8bc9e31ae8e87c39fab4/install.ps1' -OutFile $installer
  pwsh -NoProfile -ExecutionPolicy Bypass -File $installer -ScoopDir $scoop -RunAsAdmin
  if ($LASTEXITCODE) {
    throw "Installing Scoop failed with exit code $LASTEXITCODE"
  }
}

function Invoke-Scoop {
  & $scoopCommand @args
  if ($LASTEXITCODE) {
    throw "scoop $args failed with exit code $LASTEXITCODE"
  }
}

Invoke-Scoop install (Join-Path $PSScriptRoot "..\bucket\$App.json")

$appDirectory = Join-Path $scoop "apps\$App\current"
$executable = Join-Path $appDirectory 'OpenTubeX.exe'
$dataDirectory = Join-Path $env:APPDATA 'OpenTubeX'
$protocolCommand = 'HKCU:\Software\Classes\opentubex\shell\open\command'

foreach ($path in $executable, (Join-Path $appDirectory 'resources\app.asar')) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing $path"
  }
}

# The manifest removes the portable mode files so OpenTubeX runs as an installed app.
foreach ($name in 'portable.marker', 'version.dll', '.interposer', 'OpenTubeX-data') {
  if (Test-Path -LiteralPath (Join-Path $appDirectory $name)) {
    throw "Portable mode file was not removed: $name"
  }
}

# Scoop must pick the package that matches the runner.
$expectedMachine = @{ AMD64 = 0x8664; ARM64 = 0xAA64 }[$env:PROCESSOR_ARCHITECTURE]
$bytes = [System.IO.File]::ReadAllBytes($executable)
$machine = [BitConverter]::ToUInt16($bytes, [BitConverter]::ToInt32($bytes, 0x3C) + 4)
if ($machine -ne $expectedMachine) {
  throw ('OpenTubeX.exe targets machine 0x{0:X4}, expected 0x{1:X4}' -f $machine, $expectedMachine)
}

# Leave existing data and link registrations alone when this runs outside CI.
$dataExisted = Test-Path -LiteralPath $dataDirectory
$protocolExisted = Test-Path -LiteralPath $protocolCommand

function Test-Started {
  if (-not (Test-Path -LiteralPath (Join-Path $dataDirectory 'Local State'))) { return $false }
  $command = (Get-ItemProperty -LiteralPath $protocolCommand -ErrorAction Ignore).'(default)'
  return $command -like "*\apps\$App\*"
}

$process = Start-Process -FilePath $executable -PassThru
try {
  $deadline = (Get-Date).AddMinutes(2)
  while (-not (Test-Started)) {
    if ($process.HasExited) {
      throw "OpenTubeX exited early with code $($process.ExitCode)"
    }
    if ((Get-Date) -gt $deadline) {
      throw "OpenTubeX did not store its data in $dataDirectory and register opentubex:// links"
    }
    Start-Sleep -Milliseconds 500
  }
} finally {
  Get-Process -Name OpenTubeX -ErrorAction SilentlyContinue | Stop-Process -Force
  Wait-Process -Name OpenTubeX -Timeout 30 -ErrorAction SilentlyContinue
}

Invoke-Scoop uninstall $App
if (Test-Path -LiteralPath (Join-Path $scoop "apps\$App")) {
  throw "Scoop did not remove $App"
}
if (-not (Test-Path -LiteralPath (Join-Path $dataDirectory 'Local State'))) {
  throw 'Uninstalling removed the OpenTubeX data'
}

if (-not $dataExisted) {
  Remove-Item -LiteralPath $dataDirectory -Recurse -Force
}
if (-not $protocolExisted) {
  Remove-Item -LiteralPath 'HKCU:\Software\Classes\opentubex' -Recurse -Force
}
