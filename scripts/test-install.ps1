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
$persistDirectory = Join-Path $scoop "persist\$App\OpenTubeX-data"
$executable = Join-Path $appDirectory 'OpenTubeX.exe'

foreach ($path in $executable, (Join-Path $appDirectory 'portable.marker'), (Join-Path $appDirectory 'resources\app.asar')) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing $path"
  }
}

# Scoop must pick the package that matches the runner.
$expectedMachine = @{ AMD64 = 0x8664; ARM64 = 0xAA64 }[$env:PROCESSOR_ARCHITECTURE]
$bytes = [System.IO.File]::ReadAllBytes($executable)
$machine = [BitConverter]::ToUInt16($bytes, [BitConverter]::ToInt32($bytes, 0x3C) + 4)
if ($machine -ne $expectedMachine) {
  throw ('OpenTubeX.exe targets machine 0x{0:X4}, expected 0x{1:X4}' -f $machine, $expectedMachine)
}

$data = Get-Item -LiteralPath (Join-Path $appDirectory 'OpenTubeX-data')
if ($data.LinkType -ne 'Junction' -or @($data.Target)[0] -ne $persistDirectory) {
  throw "OpenTubeX-data is not linked to $persistDirectory"
}

$process = Start-Process -FilePath $executable -PassThru
try {
  $deadline = (Get-Date).AddMinutes(2)
  while (-not (Test-Path -LiteralPath (Join-Path $persistDirectory 'Local State'))) {
    if ($process.HasExited) {
      throw "OpenTubeX exited early with code $($process.ExitCode)"
    }
    if ((Get-Date) -gt $deadline) {
      throw 'OpenTubeX did not write its data to the persisted directory'
    }
    Start-Sleep -Milliseconds 500
  }
} finally {
  Get-Process -Name OpenTubeX -ErrorAction SilentlyContinue | Stop-Process -Force
  Wait-Process -Name OpenTubeX -Timeout 30 -ErrorAction SilentlyContinue
}

foreach ($path in (Join-Path $env:APPDATA 'OpenTubeX'), (Join-Path $env:LOCALAPPDATA 'OpenTubeX')) {
  if (Test-Path -LiteralPath $path) {
    throw "OpenTubeX wrote data outside its portable directory: $path"
  }
}

Invoke-Scoop uninstall $App --purge
if (Test-Path -LiteralPath (Join-Path $scoop "apps\$App")) {
  throw "Scoop did not remove $App"
}
