#Requires -Version 5.1
<#
.SYNOPSIS
    Builds the SDS-Remote Windows release bundle and generates the Inno Setup installer.

.DESCRIPTION
    The script performs the complete Windows build chain:
      1. Verifies Flutter and the Visual Studio C++ build tools.
      2. Copies the project to a local NTFS scratch directory.
      3. Resolves Flutter packages and creates local plugin junctions.
      4. Builds the Flutter Windows release bundle.
      5. Adds the Visual C++ runtime DLLs to the bundle.
      6. Publishes the bundle to the project's build output directory.
      7. Compiles windows\runner\resources\sdsremote.iss with Inno Setup.

    A local scratch directory is used because the project drive (Y:) is a
    VirtIO-FS share that does not support the symlinks/junctions required by
    the Flutter Windows toolchain.

.PARAMETER ProjectRoot
    SDS-Remote checkout. Defaults to the parent directory of this script.

.PARAMETER ScratchRoot
    Local NTFS working directory. Defaults to C:\build\sdsremote-build.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows_installer.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$ScratchRoot = 'C:\build\sdsremote-build'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Native commands should be checked via $LASTEXITCODE, not by turning stderr
# into terminating errors.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Remove-Tree {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($fullPath) -or $fullPath -eq $root) {
        throw "Refusing to remove unsafe path: '$fullPath'"
    }

    # Use rd first: it removes directory symlinks/junctions without traversing
    # into their targets. Remove-Item is only a fallback.
    & cmd.exe /d /c "rd /s /q `"$fullPath`"" | Out-Null
    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $fullPath) {
        throw "Could not remove directory: $fullPath"
    }
}

function Copy-Tree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$ExcludeDirectories = @()
    )

    $roboArgs = @(
        $Source,
        $Destination,
        '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1'
    )
    if ($ExcludeDirectories.Count -gt 0) {
        $roboArgs += '/XD'
        $roboArgs += $ExcludeDirectories
    }

    & robocopy @roboArgs | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ge 8) {
        throw "robocopy failed with exit code $exitCode ($Source -> $Destination)"
    }
}

function Get-InnoCompiler {
    $candidates = @()

    $isccCommand = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($isccCommand) {
        $candidates += $isccCommand.Source
    }

    $candidates += @(
        (Join-Path $env:LOCALAPPDATA 'Apps\Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        'C:\Users\klumw\Apps\Inno Setup 6\ISCC.exe'
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Install-InnoSetup {
    $version = '6.7.3'
    $url = "https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-$version.exe"
    $expectedHash = '9C73C3BAE7ED48D44112A0F48E66742C00090BDB5BEF71D9D3C056C66E97B732'
    $download = Join-Path $env:TEMP "innosetup-$version.exe"
    $installDir = Join-Path $env:LOCALAPPDATA 'Apps\Inno Setup 6'

    Write-Step 'Installing Inno Setup'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $download -UseBasicParsing

    $actualHash = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw "Inno Setup download hash mismatch: $actualHash"
    }

    $arguments = "/CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$installDir`""
    $process = Start-Process -FilePath $download -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Inno Setup installer failed with exit code $($process.ExitCode)"
    }

    $iscc = Join-Path $installDir 'ISCC.exe'
    if (-not (Test-Path -LiteralPath $iscc)) {
        throw "Inno Setup was installed but ISCC.exe was not found at $iscc"
    }
    return $iscc
}

function Get-VcRuntimeDirectory {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "vswhere.exe not found. Install Visual Studio with the Desktop development with C++ workload."
    }

    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
        Select-Object -First 1
    if (-not $vsPath) {
        throw 'No Visual Studio installation with the MSVC x64 toolchain was found.'
    }
    $vsPath = $vsPath.Trim()

    $redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
    $crtDirectory = Get-ChildItem -LiteralPath $redistRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d' } |
        Sort-Object Name -Descending |
        ForEach-Object {
            Get-ChildItem -LiteralPath (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue
        } |
        Select-Object -First 1

    if (-not $crtDirectory) {
        throw "Visual C++ runtime directory not found below $redistRoot"
    }
    return $crtDirectory.FullName
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$ScratchRoot = [IO.Path]::GetFullPath($ScratchRoot).TrimEnd('\')

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'pubspec.yaml'))) {
    throw "ProjectRoot does not contain pubspec.yaml: $ProjectRoot"
}
if ($ScratchRoot -eq $ProjectRoot) {
    throw 'ScratchRoot must be different from ProjectRoot.'
}
if ($ScratchRoot.Length -lt 4) {
    throw "Refusing to use unsafe ScratchRoot: $ScratchRoot"
}

$issPath = Join-Path $ProjectRoot 'windows\runner\resources\sdsremote.iss'
if (-not (Test-Path -LiteralPath $issPath)) {
    throw "Inno Setup script not found: $issPath"
}

Write-Step 'Checking prerequisites'
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand) {
    throw 'Flutter was not found on PATH.'
}
$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vsWhere)) {
    throw 'Visual Studio Build Tools were not found.'
}
$vsInstall = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
    Select-Object -First 1
if (-not $vsInstall) {
    throw 'Visual Studio C++ build tools are missing.'
}
Write-Host "Flutter : $($flutterCommand.Source)"
Write-Host "VS      : $($vsInstall.Trim())"

Write-Step "Preparing local scratch directory: $ScratchRoot"
Remove-Tree -Path $ScratchRoot
New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null

# Verify that the scratch volume supports directory junctions. The Flutter
# Windows build needs them for its plugin links.
$probeTarget = Join-Path $ScratchRoot '.junction-target'
$probeLink = Join-Path $ScratchRoot '.junction-link'
New-Item -ItemType Directory -Path $probeTarget -Force | Out-Null
try {
    New-Item -ItemType Junction -Path $probeLink -Target $probeTarget -ErrorAction Stop | Out-Null
} catch {
    throw "ScratchRoot must be on a local NTFS volume that supports junctions: $ScratchRoot"
}
Remove-Item -LiteralPath $probeLink -Force
Remove-Item -LiteralPath $probeTarget -Force

Write-Step 'Copying project to scratch directory'
$ephemeralDirectory = Join-Path $ProjectRoot 'windows\flutter\ephemeral'
foreach ($directory in @('lib', 'assets', 'packages', 'windows')) {
    $source = Join-Path $ProjectRoot $directory
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required project directory is missing: $source"
    }
    Copy-Tree -Source $source -Destination (Join-Path $ScratchRoot $directory) -ExcludeDirectories @($ephemeralDirectory)
}
foreach ($file in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.metadata', 'LICENSE', 'flutter_launcher_icons.yaml')) {
    $source = Join-Path $ProjectRoot $file
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $ScratchRoot $file) -Force
    }
}

Write-Step 'Resolving Flutter packages'
$pubLog = Join-Path $ScratchRoot 'flutter-pub-get.log'
Push-Location $ScratchRoot
try {
    $pubCommand = "flutter pub get > `"$pubLog`" 2>&1"
    & cmd.exe /d /c $pubCommand
    $pubExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
$pubOutput = Get-Content -LiteralPath $pubLog -Raw -ErrorAction SilentlyContinue
if ($pubExitCode -ne 0) {
    if ($pubOutput -match 'symlink support') {
        Write-Warning 'flutter pub get could not create symlinks; continuing with local junctions.'
    } else {
        Get-Content -LiteralPath $pubLog -Tail 80
        throw "flutter pub get failed with exit code $pubExitCode"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $ScratchRoot '.dart_tool\package_config.json'))) {
    throw 'flutter pub get did not create .dart_tool\package_config.json.'
}
if (-not (Test-Path -LiteralPath (Join-Path $ScratchRoot '.flutter-plugins-dependencies'))) {
    throw 'flutter pub get did not create .flutter-plugins-dependencies.'
}

Write-Step 'Creating local plugin junctions'
$dependencyFile = Join-Path $ScratchRoot '.flutter-plugins-dependencies'
$dependencyData = Get-Content -LiteralPath $dependencyFile -Raw | ConvertFrom-Json
$windowsPlugins = @($dependencyData.plugins.windows)
if ($windowsPlugins.Count -eq 0) {
    throw 'No Windows plugins were found in .flutter-plugins-dependencies.'
}

$pluginCache = Join-Path $ScratchRoot '.plugin-cache'
$symlinkDirectory = Join-Path $ScratchRoot 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $pluginCache, $symlinkDirectory -Force | Out-Null

foreach ($plugin in $windowsPlugins) {
    $name = [string]$plugin.name
    $source = [IO.Path]::GetFullPath([string]$plugin.path)
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Plugin source directory is missing for '$name': $source"
    }

    $localPlugin = Join-Path $pluginCache $name
    if (-not (Test-Path -LiteralPath $localPlugin)) {
        Copy-Tree -Source $source -Destination $localPlugin
    }

    $link = Join-Path $symlinkDirectory $name
    if (Test-Path -LiteralPath $link) {
        continue
    }
    try {
        New-Item -ItemType Junction -Path $link -Target $localPlugin -ErrorAction Stop | Out-Null
    } catch {
        throw "Could not create plugin junction for '$name'. ScratchRoot must be local NTFS: $ScratchRoot"
    }
}

Write-Step 'Building Flutter Windows release'
$buildLog = Join-Path $ScratchRoot 'flutter-build.log'
Push-Location $ScratchRoot
try {
    $buildCommand = "flutter build windows --release --no-pub > `"$buildLog`" 2>&1"
    & cmd.exe /d /c $buildCommand
    $buildExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($buildExitCode -ne 0) {
    Get-Content -LiteralPath $buildLog -Tail 100
    throw "flutter build windows failed with exit code $buildExitCode (log: $buildLog)"
}

$releaseDirectory = Join-Path $ScratchRoot 'build\windows\x64\runner\Release'
$builtExe = Join-Path $releaseDirectory 'sdsremote.exe'
if (-not (Test-Path -LiteralPath $builtExe)) {
    throw "Build succeeded but $builtExe was not created."
}

Write-Step 'Bundling Visual C++ runtime'
$crtDirectory = Get-VcRuntimeDirectory
$crtFiles = Get-ChildItem -LiteralPath $crtDirectory -Filter '*.dll' -File
if ($crtFiles.Count -eq 0) {
    throw "No runtime DLLs found in $crtDirectory"
}
$crtFiles | Copy-Item -Destination $releaseDirectory -Force
Write-Host "Runtime DLLs: $($crtFiles.Count) from $crtDirectory"

Write-Step 'Publishing release bundle'
$targetRelease = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$targetRunner = Split-Path -Parent $targetRelease
New-Item -ItemType Directory -Path $targetRunner -Force | Out-Null

& robocopy $releaseDirectory $targetRelease '/MIR' '/NFL' '/NDL' '/NJH' '/NJS' '/NP' '/R:1' '/W:1' | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "Could not publish release bundle to $targetRelease (robocopy exit code $LASTEXITCODE)"
}
if (-not (Test-Path -LiteralPath (Join-Path $targetRelease 'sdsremote.exe'))) {
    throw "Published release bundle is missing sdsremote.exe: $targetRelease"
}

Write-Step 'Compiling Inno Setup installer'
$iscc = Get-InnoCompiler
if (-not $iscc) {
    $iscc = Install-InnoSetup
}
Write-Host "ISCC: $iscc"
& $iscc $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$installer = Join-Path $targetRunner 'sdsremote.exe'
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer was not created at $installer"
}

$installerItem = Get-Item -LiteralPath $installer
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash

Write-Host ''
Write-Host 'Build completed successfully.' -ForegroundColor Green
Write-Host "Installer : $installer"
Write-Host "Size      : $([math]::Round($installerItem.Length / 1MB, 2)) MB"
Write-Host "SHA-256   : $hash"
Write-Host "Scratch   : $ScratchRoot"
