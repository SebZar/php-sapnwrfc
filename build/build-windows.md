# Building php-sapnwrfc on Windows

## Prerequisites

### 1. Visual Studio 2026 with the required MSVC toolsets

Install **Visual Studio 2026** with the **"Desktop development with C++"** workload.
VS 2026 ships with the v144 (vs18) toolset, but the current PHP Windows binaries are compiled
with older toolsets. Both must be added as individual components:

| PHP version | Zip toolset | Required MSVC component |
|-------------|-------------|-------------------------|
| 8.2, 8.3 | vs16 | **MSVC v142 – VS 2019 C++ x64/x86 Build Tools (v14.29–16.11)** |
| 8.4, 8.5 | vs17 | **MSVC v143 – VS 2022 C++ x64/x86 Build Tools** |

Install both via **VS Installer → Modify → Individual Components** and search for "MSVC v142"
and "MSVC v143".

The build script auto-detects which toolset each PHP zip requires and selects the correct compiler
via `vcvarsall.bat -vcvars_ver`. If a required toolset is not installed it exits with a clear
error and installation instructions.

Download VS: https://visualstudio.microsoft.com/downloads/

### 2. PHP zips (binary + devel) and PHP SDK

Place the following files in the `build\php\` folder.

**PHP 8.2 and 8.3** (toolset vs16):

| File | Purpose |
|------|---------|
| `php-{ver}-Win32-vs16-x64.zip` | TS binary |
| `php-{ver}-nts-Win32-vs16-x64.zip` | NTS binary |
| `php-devel-pack-{ver}-Win32-vs16-x64.zip` | TS devel (provides `phpize` + headers) |
| `php-devel-pack-{ver}-nts-Win32-vs16-x64.zip` | NTS devel |

**PHP 8.4 and 8.5** (toolset vs17):

| File | Purpose |
|------|---------|
| `php-{ver}-Win32-vs17-x64.zip` | TS binary |
| `php-{ver}-nts-Win32-vs17-x64.zip` | NTS binary |
| `php-devel-pack-{ver}-Win32-vs17-x64.zip` | TS devel |
| `php-devel-pack-{ver}-nts-Win32-vs17-x64.zip` | NTS devel |

**PHP SDK binary tools** (one file, any PHP version):

| File | Purpose |
|------|---------|
| `php-sdk-binary-tools-*.zip` | Build environment setup scripts |

Download PHP zips from https://windows.php.net/download/ — choose the **zip** packages (not the
installer). Download the PHP SDK zip from https://github.com/php/php-sdk-binary-tools/releases.

### 3. SAP NW RFC SDK

Place the SAP NW RFC SDK zip (e.g. `nwrfc750P_18-70002755.zip`) in the `build\sap\` folder.
Obtain it from the SAP Software Downloads portal (requires SAP account).

Expected layout inside the zip:

```
nwrfcsdk\
  include\   ← header files
  lib\        ← sapnwrfc.lib, libsapucum.lib, *.dll
```

---

## Running the build

Open **PowerShell** and run from the `build\` directory:

```powershell
cd path\to\php-sapnwrfc\build
.\build-windows.ps1
```

The script automatically finds every PHP zip in `.\php\` and builds the extension for each variant.

### Optional parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-WorkspaceDir` | Where extracted PHP binaries, devel packs, PHP SDK, and SAP SDK land | `.\workspace` |
| `-OutputDir` | Where built DLLs are collected | `.\output` |
| `-Toolset` | Override the MSVC toolset for all variants (e.g. `vs17`, `vs18`) | auto-detected from zip name |
| `-RunTests` | Run `nmake test` after each build | — |

Examples:

```powershell
# Build all variants (normal case)
.\build-windows.ps1

# Custom workspace and output directories, run tests after each build
.\build-windows.ps1 -WorkspaceDir "D:\build" -OutputDir "D:\dist" -RunTests

# Force a specific compiler toolset
.\build-windows.ps1 -Toolset vs17
```

### Script execution policy

If you get a script-execution error, allow local scripts for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

## What the script does

1. Reads the extension version from `php_sapnwrfc.h`.
2. Scans `.\php\*.zip` to discover PHP variants (TS / NTS, version, toolset, arch).
3. Detects the installed Visual Studio via `vswhere`.
4. Extracts the SAP NW RFC SDK from `.\sap\*.zip` into `workspace\nwrfcsdk` and reads its version from `sapnwrfc.dll`.
5. Extracts the PHP SDK binary tools from `.\php\php-sdk-binary-tools-*.zip` into `workspace\php-sdk`.
6. For **each** PHP variant:
   a. Extracts the PHP binary zip to `workspace\php-{ver}-{ts|nts}-{arch}`.
   b. Extracts the matching devel zip to `workspace\php-devel-pack-{ver}[-nts]-Win32-{toolset}-{arch}`.
   c. Sets up the correct MSVC environment (via `phpsdk-{toolset}-{arch}.bat` for same-toolset builds, or `vcvarsall.bat -vcvars_ver` for cross-toolset builds) and runs:
      ```
      phpize
      configure --with-prefix=<phpDir> --with-sapnwrfc=<nwrfcsdkDir>
      nmake
      ```
   d. Copies the built DLL to `.\output\` with a versioned filename.
7. Prints a summary of all built DLLs.

---

## Output

All DLLs land directly in `build\output\` with a filename that encodes every relevant version:

```
php_sapnwrfc-{ext_ver}+php.{php_ver}-{ts|nts}-{toolset}-{arch}.sdk.{sdk_ver}.dll
```

Example:

```
php_sapnwrfc-2.1.0+php.8.3.31-ts-vs16-x64.sdk.7500.0.13.dll
php_sapnwrfc-2.1.0+php.8.3.31-nts-vs16-x64.sdk.7500.0.13.dll
```

---

## Installing the built extension

1. Copy the appropriate DLL to your PHP `ext\` directory.
2. Add the following to `php.ini`:
   ```ini
   extension=sapnwrfc
   ```
3. Add the SAP NW RFC SDK `lib\` directory to the system `PATH` so PHP can load the SAP DLLs at runtime.

Verify with:

```
php -m | findstr sapnwrfc
```

---

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| No PHP zips found | Place binary zips in `build\php\` with the expected naming pattern |
| No SAP SDK zip found | Place the SAP zip in `build\sap\` |
| Devel package not found | Place the matching `php-devel-pack-{ver}[-nts]-Win32-{toolset}-x64.zip` in `build\php\` |
| PHP SDK zip not found | Place `php-sdk-binary-tools-*.zip` in `build\php\` |
| `phpize` not found | Devel package not on PATH — check that extraction succeeded in `workspace\` |
| `configure` fails: SDK not found | Verify extracted SDK has `include\` and `lib\` under `workspace\nwrfcsdk` |
| `phpsdk-vs1X-x64.bat` not found | Toolset mismatch — use `-Toolset` to select an available toolset |
| MSVC toolset not found | Install the required v142/v143 component via VS Installer (see Prerequisites) |
| Tests fail: module not loaded | Ensure `workspace\nwrfcsdk\lib` is on `PATH` (`-RunTests` adds it automatically) |
