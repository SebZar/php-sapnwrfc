#Requires -Version 5.1
<#
.SYNOPSIS
    Builds the php-sapnwrfc extension on Windows for every PHP variant found in .\php\.

.DESCRIPTION
    Picks up PHP binary zips from .\php\ (TS and/or NTS), the matching devel packs,
    the PHP SDK binary-tools zip, and the SAP NW RFC SDK zip - all from local disk,
    no internet access required. Extracts everything into WorkspaceDir and builds the
    extension for each variant using the correct MSVC toolset.

    --- Required files ---

    Place in .\php\
      TS binary : php-{ver}-Win32-{toolset}-{arch}.zip
      NTS binary: php-{ver}-nts-Win32-{toolset}-{arch}.zip
      Devel pack: php-devel-pack-{ver}[-nts]-Win32-{toolset}-{arch}.zip
      PHP SDK   : php-sdk-binary-tools-*.zip
                  (download from github.com/php/php-sdk-binary-tools/releases)

    Place in .\sap\
      SAP NW RFC SDK: any single *.zip
                      (the zip must contain a top-level "nwrfcsdk" folder)

    --- Toolset handling ---

    The MSVC toolset (vs17, vs18, ...) is read from the PHP zip filenames and used for
    both devel pack lookup and compiler selection. When the installed Visual Studio is a
    different generation than the zip toolset (e.g. VS 2026 with vs17 PHP zips), the
    script automatically selects the matching older MSVC toolset via vcvarsall
    -vcvars_ver. This requires the older toolset to be installed as a VS component.

    Toolset generations and their MSVC version ranges:
      vs16 = VS 2019, MSVC 14.20-14.29
      vs17 = VS 2022, MSVC 14.30-14.43
      vs18 = VS 2026, MSVC 14.44+

    If the required toolset is not installed the script exits with a clear error and
    installation instructions. Use -Toolset only as an explicit override.

    --- Visual Studio setup ---

    The installed VS is detected automatically via vswhere at startup. When the zip
    toolset matches the installed VS, the standard phpsdk bat is used to set up the
    build environment. When they differ, vcvarsall.bat is called directly with the
    appropriate -vcvars_ver value so the correct compiler is selected.

    Note: vcvarsall.bat may print a harmless "vswhere.exe not found" warning to stderr
    when vswhere is not on PATH - this does not affect the build.

.PARAMETER WorkspaceDir
    Directory for extracted PHP binaries, devel packs, PHP SDK, and SAP NW RFC SDK.
    Default: ".\workspace" (subfolder next to this script).
    Re-running the script skips already-extracted content.

.PARAMETER OutputDir
    Directory where built DLLs are collected after each successful build.
    Default: ".\output" (subfolder next to this script).
    Each variant gets its own subfolder: php-{ver}-{ts|nts}-{arch}\.

.PARAMETER Toolset
    Override the MSVC toolset for all variants (e.g. "vs17", "vs18").
    Overrides only the compiler selection; devel pack lookup still uses the zip toolset.
    Normally not needed - the script auto-selects the correct toolset.

.PARAMETER RunTests
    Run "nmake test" after each successful build.

.EXAMPLE
    .\build-windows.ps1
    Build all variants. Toolset is read from zip filenames; cross-toolset builds
    (e.g. vs17 zips on a VS 2026 host) are handled automatically.
    DLLs are collected in .\output\.

.EXAMPLE
    .\build-windows.ps1 -Toolset vs18
    Force vs18 compiler for all variants regardless of zip toolset labels.

.EXAMPLE
    .\build-windows.ps1 -WorkspaceDir "D:\build" -OutputDir "D:\dist" -RunTests
    Build into a custom workspace, collect DLLs into D:\dist\, and run tests after each build.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceDir = "",
    [string]$OutputDir    = "",
    [string]$Toolset      = "",          # e.g. "vs18" — overrides zip-detected value
    [switch]$RunTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail([string]$msg) { Write-Error $msg; exit 1 }

# Returns [PSCustomObject]@{Toolset="vsXX"; InstallPath="..."} or $null
function Get-VsToolset {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $null }
    $ver  = & $vswhere -latest -property installationVersion 2>$null
    $path = & $vswhere -latest -property installationPath 2>$null
    if (-not $ver) { return $null }
    $major = [int]($ver -split '\.')[0]
    return [PSCustomObject]@{ Toolset = "vs$major"; InstallPath = $path }
}

$ExtSourceDir = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $WorkspaceDir) { $WorkspaceDir = Join-Path $PSScriptRoot "workspace" }
if (-not $OutputDir)    { $OutputDir    = Join-Path $PSScriptRoot "output" }
$PhpSdkDir    = Join-Path $WorkspaceDir "php-sdk"

# ---------------------------------------------------------------------------
# Discover PHP variants from .\php\*.zip
# ---------------------------------------------------------------------------
Step "Discovering PHP variants"

$phpZipDir = Join-Path $PSScriptRoot "php"
$phpZips   = @(Get-ChildItem -Path $phpZipDir -Filter "php-*.zip" -ErrorAction SilentlyContinue)

if ($phpZips.Count -eq 0) { Fail "No PHP zip files found in $phpZipDir" }

$variants = @()
foreach ($zip in $phpZips) {
    # Skip devel packages and the SDK zip — consumed separately
    if ($zip.BaseName -match '-devel-') { continue }
    if ($zip.BaseName -match '^php-sdk-binary-tools-') { continue }

    # php-{ver}[-nts]-Win32-{toolset}-{arch}
    if ($zip.BaseName -match '^php-(\d+\.\d+\.\d+)(-nts)?-Win32-(vs\d+)-(x64|x86)$') {
        $isNts = $Matches[2] -eq '-nts'
        $variants += [PSCustomObject]@{
            ZipPath      = $zip.FullName
            Version      = $Matches[1]
            IsNts        = $isNts
            Toolset      = $Matches[3]   # toolset in the zip filename — used for devel pack lookup
            BuildToolset = $Matches[3]   # toolset used for building — may be overridden by -Toolset
            Arch         = $Matches[4]
            Label        = if ($isNts) { 'NTS' } else { 'TS' }
        }
        Write-Host "  Found: PHP $($Matches[1]) $(if ($isNts) {'NTS'} else {'TS'}) [$($Matches[3])-$($Matches[4])]"
    } else {
        Write-Warning "Skipping unrecognized zip: $($zip.Name)"
    }
}

if ($variants.Count -eq 0) { Fail "No recognizable PHP zips found in $phpZipDir" }

# --- Report installed Visual Studio ---
$vsInfo          = Get-VsToolset
$detectedToolset = if ($vsInfo) { $vsInfo.Toolset } else { $null }
if ($vsInfo) {
    Write-Host "  Installed VS  : $($vsInfo.Toolset) at $($vsInfo.InstallPath)"
} else {
    Write-Warning "vswhere not found - cannot detect installed Visual Studio"
}

# MSVC minor-version ranges per toolset generation (second component of "14.XX.YYYYY"):
#   vs16 = VS 2019  = MSVC 14.20-14.29
#   vs17 = VS 2022  = MSVC 14.30-14.43  (17.0 shipped 14.30, 17.13 shipped 14.43)
#   vs18 = VS 2026  = MSVC 14.44+
$ToolsetMinorRange = @{
    'vs16' = @{ Min = 20; Max = 29 }
    'vs17' = @{ Min = 30; Max = 43 }
    'vs18' = @{ Min = 44; Max = 99 }
}

# --- Apply -Toolset override ---
# -Toolset overrides the compiler (BuildToolset) but not the devel pack lookup (Toolset).
if ($Toolset) {
    Write-Host "  Toolset override: $Toolset (from -Toolset parameter) - devel pack lookup still uses zip toolset"
    $variants = @($variants | ForEach-Object { $_.BuildToolset = $Toolset; $_ })
}

# ---------------------------------------------------------------------------
# Extract SAP NW RFC SDK from .\sap\*.zip
# ---------------------------------------------------------------------------
Step "Preparing SAP NW RFC SDK"

$sapZipDir = Join-Path $PSScriptRoot "sap"
$sapZip    = Get-ChildItem -Path $sapZipDir -Filter "*.zip" -ErrorAction SilentlyContinue |
             Select-Object -First 1

if (-not $sapZip) { Fail "No SAP NW RFC SDK zip found in $sapZipDir" }

New-Item -ItemType Directory -Force $WorkspaceDir | Out-Null
$NwRfcSdkDir = Join-Path $WorkspaceDir "nwrfcsdk"

if (-not (Test-Path $NwRfcSdkDir)) {
    Write-Host "  Extracting $($sapZip.Name) ..."
    $sapTemp = Join-Path $WorkspaceDir "_sap_tmp"
    Expand-Archive -Path $sapZip.FullName -DestinationPath $sapTemp -Force

    # SAP zips sometimes nest the sdk inside a nwrfcsdk sub-folder
    $nested = Get-ChildItem -Path $sapTemp -Filter "nwrfcsdk" -Recurse -Directory |
              Select-Object -First 1
    if ($nested) {
        Move-Item $nested.FullName $NwRfcSdkDir
        Remove-Item $sapTemp -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Move-Item $sapTemp $NwRfcSdkDir
    }
} else {
    Write-Host "  Already present: $NwRfcSdkDir"
}

if (-not (Test-Path (Join-Path $NwRfcSdkDir "include"))) {
    Fail "SAP NW RFC SDK 'include' dir not found under $NwRfcSdkDir - check zip structure"
}

Write-Host "  SAP NW RFC SDK: $NwRfcSdkDir"

# ---------------------------------------------------------------------------
# PHP SDK binary tools — extract from .\php\php-sdk-binary-tools-*.zip
# ---------------------------------------------------------------------------
Step "Preparing PHP SDK binary tools"

$phpSdkZip = Get-ChildItem -Path $phpZipDir -Filter "php-sdk-binary-tools-*.zip" -ErrorAction SilentlyContinue |
             Select-Object -First 1

if (-not $phpSdkZip) {
    Fail "PHP SDK zip not found in $phpZipDir`n  Place php-sdk-binary-tools-*.zip there (download from github.com/php/php-sdk-binary-tools/releases) and re-run."
}

if (-not (Test-Path $PhpSdkDir)) {
    Write-Host "  Extracting $($phpSdkZip.Name) ..."
    $sdkTemp = Join-Path $WorkspaceDir "_sdk_tmp"
    Expand-Archive -Path $phpSdkZip.FullName -DestinationPath $sdkTemp -Force

    # GitHub release archives have a single top-level folder; move its contents up
    $topLevel = Get-ChildItem -Path $sdkTemp -Directory | Select-Object -First 1
    if ($topLevel) {
        Move-Item $topLevel.FullName $PhpSdkDir
        Remove-Item $sdkTemp -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Move-Item $sdkTemp $PhpSdkDir
    }
    Write-Host "  PHP SDK: $PhpSdkDir"
} else {
    Write-Host "  PHP SDK already at $PhpSdkDir"
}

# ---------------------------------------------------------------------------
# Helper: run build commands via phpsdk -t inner.bat so the VS environment
# is fully configured before phpize/configure/nmake execute.
# ---------------------------------------------------------------------------
function Invoke-BuildBat([string]$content, [string]$PhpSdkBat, [string]$VsEnvLines = "") {
    $innerBat = Join-Path $env:TEMP "sapnwrfc_inner_$([System.IO.Path]::GetRandomFileName().Replace('.',''))_.bat"
    $outerBat = Join-Path $env:TEMP "sapnwrfc_outer_$([System.IO.Path]::GetRandomFileName().Replace('.',''))_.bat"
    $exitFile = Join-Path $env:TEMP "sapnwrfc_exit_$([System.IO.Path]::GetRandomFileName().Replace('.',''))_.txt"

    # Inner bat: the actual build steps + exit-code capture
    Set-Content -Path $innerBat -Value ($content + "`necho %ERRORLEVEL% > `"$exitFile`"") -Encoding ASCII

    # Outer bat: sets up VS env then runs the inner bat.
    # $VsEnvLines: when set, VS env is established via vcvarsall directly (cross-toolset builds).
    # Otherwise phpsdk bat is used (sets up VS env + php-sdk paths in one shot).
    if ($VsEnvLines) {
        Set-Content -Path $outerBat -Value ("@echo off`r`n" + $VsEnvLines + "`r`ncall `"$innerBat`"") -Encoding ASCII
    } else {
        Set-Content -Path $outerBat -Value "@echo off`r`ncall `"$PhpSdkBat`" -t `"$innerBat`"" -Encoding ASCII
    }

    try {
        & cmd.exe /c "`"$outerBat`"" | Out-Host
        if (Test-Path $exitFile) {
            return [int](Get-Content $exitFile).Trim()
        }
        return $LASTEXITCODE
    } finally {
        Remove-Item $innerBat -Force -ErrorAction SilentlyContinue
        Remove-Item $outerBat -Force -ErrorAction SilentlyContinue
        Remove-Item $exitFile -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Build each variant
# ---------------------------------------------------------------------------
$results = [System.Collections.Generic.List[object]]::new()

foreach ($v in $variants) {
    $buildLabel = if ($v.BuildToolset -ne $v.Toolset) { "$($v.Toolset)->$($v.BuildToolset)" } else { $v.Toolset }
    Step "Building PHP $($v.Version) $($v.Label) ($buildLabel-$($v.Arch))"

    # --- PHP SDK batch for this toolset ---
    $phpsdk_bat = Join-Path $PhpSdkDir "phpsdk-$($v.BuildToolset)-$($v.Arch).bat"
    if (-not (Test-Path $phpsdk_bat)) {
        Write-Warning "PHP SDK batch not found: $phpsdk_bat"
        $available = @(Get-ChildItem -Path $PhpSdkDir -Filter "phpsdk-vs*-$($v.Arch).bat" -ErrorAction SilentlyContinue)
        if ($available) {
            $names = ($available | ForEach-Object { $_.BaseName -replace "^phpsdk-|-$($v.Arch)$" }) -join ', '
            Write-Warning "Available toolsets in PHP SDK: $names - use -Toolset <value> to select one"
        } else {
            Write-Warning "No phpsdk-vs*-$($v.Arch).bat found in $PhpSdkDir"
        }
        $results.Add([PSCustomObject]@{ Variant = $v; Success = $false; Dll = $null })
        continue
    }

    # --- Extract PHP binary (provides php.exe for --with-prefix) ---
    $phpDir = Join-Path $WorkspaceDir "php-$($v.Version)-$($v.Label.ToLower())-$($v.Arch)"
    if (-not (Test-Path $phpDir)) {
        Write-Host "  Extracting PHP $($v.Label) binary ..."
        Expand-Archive -Path $v.ZipPath -DestinationPath $phpDir
    } else {
        Write-Host "  PHP $($v.Label) binary already at $phpDir"
    }

    # --- Locate PHP devel package (provides phpize + headers) ---
    $ntsPart  = if ($v.IsNts) { '-nts' } else { '' }
    $develPkg = "php-devel-pack-$($v.Version)$($ntsPart)-Win32-$($v.Toolset)-$($v.Arch)"
    $develDir = Join-Path $WorkspaceDir $develPkg
    $localDevelZip = Join-Path $phpZipDir "$develPkg.zip"

    if (-not (Test-Path $localDevelZip)) {
        Fail "Devel package not found: $localDevelZip`n  Place $develPkg.zip in $phpZipDir and re-run."
    }

    if (-not (Test-Path $develDir)) {
        Write-Host "  Extracting $develPkg.zip ..."
        $develTemp = Join-Path $WorkspaceDir "_devel_tmp"
        Expand-Archive -Path $localDevelZip -DestinationPath $develTemp
        $topDir = Get-ChildItem -Path $develTemp -Directory | Select-Object -First 1
        if ($topDir -and -not (Get-ChildItem -Path $develTemp -File)) {
            Move-Item $topDir.FullName $develDir
            Remove-Item $develTemp -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Move-Item $develTemp $develDir
        }
    } else {
        Write-Host "  Devel package already extracted at $develDir"
    }

    # --- Build ---
    # phpsdk -t sets up the full VS environment; inner bat only needs the devel pack on PATH
    $buildBat = @"
@echo off
set "PATH=%PATH%;$develDir"
cd /d "$ExtSourceDir"
call phpize || exit /b 1
call "$ExtSourceDir\configure.bat" --with-prefix="$phpDir" --with-sapnwrfc="$NwRfcSdkDir" || exit /b 1
nmake || exit /b 1
"@

    # --- VS environment setup ---
    # When BuildToolset matches the installed VS, use the phpsdk bat (sets up everything).
    # When they differ (e.g. vs17 ZIP on VS 2026), call vcvarsall directly with -vcvars_ver
    # so the correct MSVC toolset is selected. Fails if that toolset is not installed.
    $vsEnvLines = ""
    if ($v.BuildToolset -ne $detectedToolset -and $vsInfo) {
        $range = $ToolsetMinorRange[$v.BuildToolset]
        if (-not $range) {
            Fail "No minor-version range defined for toolset '$($v.BuildToolset)' - add it to `$ToolsetMinorRange"
        }
        # Find the latest installed MSVC dir that falls in the expected minor range
        $msvcRoot     = Join-Path $vsInfo.InstallPath "VC\Tools\MSVC"
        $toolsetDir   = Get-ChildItem $msvcRoot -Directory -ErrorAction SilentlyContinue |
                        Where-Object {
                            $minor = [int](($_.Name -split '\.')[1])
                            $minor -ge $range.Min -and $minor -le $range.Max
                        } |
                        Sort-Object Name -Descending |
                        Select-Object -First 1
        if (-not $toolsetDir) {
            Fail ("MSVC toolset $($v.BuildToolset) (minor $($range.Min)-$($range.Max)) not found in $msvcRoot.`n" +
                  "  Install it via VS Installer -> Modify -> Individual Components`n" +
                  "  -> 'MSVC v1XX - VS 20XX C++ x64/x86 build tools (Latest)'")
        }
        # Use "major.minor" as -vcvars_ver (e.g. "14.43" selects 14.43.xxxxx)
        $parts      = $toolsetDir.Name -split '\.'
        $vcvarsVer  = "$($parts[0]).$($parts[1])"
        $vcvarsall  = Join-Path $vsInfo.InstallPath "VC\Auxiliary\Build\vcvarsall.bat"
        $vcvarsArch = if ($v.Arch -eq 'x64') { 'amd64' } else { 'x86' }
        $vsEnvLines = "call `"$vcvarsall`" $vcvarsArch -vcvars_ver=$vcvarsVer`r`n" +
                      "if %ERRORLEVEL% neq 0 exit /b 1`r`n" +
                      "call `"$PhpSdkDir\bin\phpsdk_setvars.bat`"`r`n" +
                      "if %ERRORLEVEL% neq 0 exit /b 1"
        Write-Host "  VS env: vcvarsall -vcvars_ver=$vcvarsVer ($($toolsetDir.Name)) zip=$($v.Toolset) host=$detectedToolset"
    }

    $buildExit = Invoke-BuildBat $buildBat $phpsdk_bat $vsEnvLines
    if ($buildExit -ne 0) {
        Write-Warning "Build FAILED for PHP $($v.Label) (exit $buildExit)"
        $results.Add([PSCustomObject]@{ Variant = $v; Success = $false; Dll = $null })
        continue
    }

    # TS builds output to Release_TS, NTS to Release
    $releaseDir  = if ($v.IsNts) { "$($v.Arch)\Release" } else { "$($v.Arch)\Release_TS" }
    $builtDll    = Join-Path $ExtSourceDir "$releaseDir\php_sapnwrfc.dll"
    $variantSlug = "php-$($v.Version)-$($v.Label.ToLower())-$($v.Arch)"
    $destDir     = Join-Path $OutputDir $variantSlug
    $destDll     = Join-Path $destDir "php_sapnwrfc.dll"

    if (Test-Path $builtDll) {
        New-Item -ItemType Directory -Force $destDir | Out-Null
        Copy-Item -Path $builtDll -Destination $destDll -Force
        Write-Host "  Built ($($v.Label)): $destDll" -ForegroundColor Green
        $results.Add([PSCustomObject]@{ Variant = $v; Success = $true; Dll = $destDll })
    } else {
        Write-Warning "DLL not found at expected path: $builtDll"
        $results.Add([PSCustomObject]@{ Variant = $v; Success = $true; Dll = $null })
    }

    # --- Optional tests ---
    if ($RunTests) {
        Step "Running tests for PHP $($v.Label)"

        $testBat = @"
@echo off
set "PATH=%PATH%;$develDir;$NwRfcSdkDir\lib"
cd /d "$ExtSourceDir"
nmake test || exit /b 1
"@
        $testExit = Invoke-BuildBat $testBat $phpsdk_bat
        if ($testExit -ne 0) {
            Write-Warning "Tests reported failures for $($v.Label) (exit $testExit)"
        } else {
            Write-Host "  Tests passed ($($v.Label))" -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Step "Summary"
foreach ($r in $results) {
    $tag = "[$($r.Variant.Label)]"
    if ($r.Success -and $r.Dll) {
        Write-Host "  $tag OK  ->  $($r.Dll)" -ForegroundColor Green
    } elseif ($r.Success) {
        $releaseSubDir = if ($r.Variant.IsNts) { 'Release' } else { 'Release_TS' }
        Write-Host "  $tag Build succeeded but DLL location unknown - check $($r.Variant.Arch)\$releaseSubDir" -ForegroundColor Yellow
    } else {
        Write-Host "  $tag FAILED" -ForegroundColor Red
    }
}

$anyOk = $results | Where-Object { $_.Success -and $_.Dll }
if ($anyOk) {
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    1. Copy the DLL(s) from $OutputDir\<variant>\ to your PHP ext\ directory"
    Write-Host "    2. Add  extension=sapnwrfc  to php.ini"
    Write-Host "    3. Ensure $NwRfcSdkDir\lib is on PATH so PHP can load the SAP DLLs"
}
