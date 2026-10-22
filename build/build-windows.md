# Building php-sapnwrfc on Windows

## Prerequisites

### 1. Visual Studio 2026 with the required MSVC toolsets

Install **Visual Studio 2026** with the **"Desktop development with C++"** workload.
VS 2026 ships with the v144 (vs18) toolset, which PHP 8.6 is built with. The PHP 8.2 to 8.5
Windows binaries are compiled with older toolsets, which must be added as individual components:

| PHP version | Zip toolset | Required MSVC component |
|-------------|-------------|-------------------------|
| 8.2, 8.3 | vs16 | **MSVC v142 – VS 2019 C++ x64/x86 Build Tools (v14.29–16.11)** |
| 8.4, 8.5 | vs17 | **MSVC v143 – VS 2022 C++ x64/x86 Build Tools** |
| 8.6 | vs18 | none, v144 is part of the VS 2026 workload |

Install the older toolsets via **VS Installer → Modify → Individual Components** and search for
"MSVC v142" and "MSVC v143".

The build script auto-detects which toolset each PHP zip requires and selects the correct compiler
via `vcvarsall.bat -vcvars_ver`. If a required toolset is not installed it exits with a clear
error and installation instructions.

Download VS: https://visualstudio.microsoft.com/downloads/

### 2. PHP zips (binary + devel) and PHP SDK

Place the following files in the `build\php\` folder. For every PHP version you want to build,
you need four zips: TS binary, NTS binary and the two matching devel packs.

| File | Purpose |
|------|---------|
| `php-{ver}-Win32-{toolset}-x64.zip` | TS binary |
| `php-{ver}-nts-Win32-{toolset}-x64.zip` | NTS binary |
| `php-devel-pack-{ver}-Win32-{toolset}-x64.zip` | TS devel (provides `phpize` + headers) |
| `php-devel-pack-{ver}-nts-Win32-{toolset}-x64.zip` | NTS devel |
| `php-sdk-binary-tools-*.zip` | PHP SDK build environment, one file for all versions |

`{toolset}` is `vs16`, `vs17` or `vs18`, see the table above. `{ver}` may carry a pre-release
suffix such as `8.6.0RC4`.

Download stable PHP zips from https://windows.php.net/download/ and release candidates from
https://windows.php.net/qa/. Choose the **zip** packages (not the installer). Download the PHP
SDK zip from https://github.com/php/php-sdk-binary-tools/releases.

The script builds **every** PHP zip directly in `build\php\`. Subfolders are ignored, so move
zips you do not want to build into a subfolder such as `build\php\archive\`.

### 3. SAP NW RFC SDK

Place **exactly one** SAP NW RFC SDK zip (e.g. `nwrfc750P_20-70002755.zip`) in the `build\sap\`
folder. Obtain it from the SAP Software Downloads portal (requires SAP account).

If more than one zip is in `build\sap\`, the script stops. Keep older SDK zips in a subfolder
such as `build\sap\archive\`. When you replace the zip, the script notices it on the next run
and extracts the new SDK into the workspace.

Expected layout inside the zip:

```
nwrfcsdk\
  include\   ← header files
  lib\       ← sapnwrfc.lib, libsapucum.lib, *.dll
```

---

## Folder layout

### Before the first build

Only the files you provide. `php\` and `sap\` are not tracked by git.

```
php-sapnwrfc\
├── sapnwrfc.c, rfc_parameters.c, ...         ← extension sources
├── php_sapnwrfc.h                            ← extension version (PHP_SAPNWRFC_VERSION)
└── build\
    ├── build-windows.ps1
    ├── build-windows.md                      ← this file
    ├── publish-github-release.ps1
    ├── php\
    │   ├── php-8.2.35-Win32-vs16-x64.zip
    │   ├── php-8.2.35-nts-Win32-vs16-x64.zip
    │   ├── php-devel-pack-8.2.35-Win32-vs16-x64.zip
    │   ├── php-devel-pack-8.2.35-nts-Win32-vs16-x64.zip
    │   ├── php-8.3.36-Win32-vs16-x64.zip
    │   ├── php-8.3.36-nts-Win32-vs16-x64.zip
    │   ├── php-devel-pack-8.3.36-Win32-vs16-x64.zip
    │   ├── php-devel-pack-8.3.36-nts-Win32-vs16-x64.zip
    │   ├── php-8.4.27-Win32-vs17-x64.zip
    │   ├── php-8.4.27-nts-Win32-vs17-x64.zip
    │   ├── php-devel-pack-8.4.27-Win32-vs17-x64.zip
    │   ├── php-devel-pack-8.4.27-nts-Win32-vs17-x64.zip
    │   ├── php-8.5.12-Win32-vs17-x64.zip
    │   ├── php-8.5.12-nts-Win32-vs17-x64.zip
    │   ├── php-devel-pack-8.5.12-Win32-vs17-x64.zip
    │   ├── php-devel-pack-8.5.12-nts-Win32-vs17-x64.zip
    │   ├── php-8.6.0RC4-Win32-vs18-x64.zip               ← release candidate, optional
    │   ├── php-8.6.0RC4-nts-Win32-vs18-x64.zip
    │   ├── php-devel-pack-8.6.0RC4-Win32-vs18-x64.zip
    │   ├── php-devel-pack-8.6.0RC4-nts-Win32-vs18-x64.zip
    │   ├── php-sdk-binary-tools-php-sdk-2.7.1.zip
    │   └── archive\                                      ← ignored by the script
    │       └── php-8.5.7-Win32-vs17-x64.zip, ...
    └── sap\
        ├── nwrfc750P_20-70002755.zip                     ← exactly one zip
        └── archive\                                      ← ignored by the script
            └── nwrfc750P_18-70002755.zip
```

### After a build

The script creates `workspace\` and `output\` next to `php\` and `sap\`. Neither is tracked by git.

```
build\
├── php\ ...                                  ← unchanged
├── sap\ ...                                  ← unchanged
├── workspace\                                ← extracted zips, reused on the next run
│   ├── nwrfcsdk\
│   │   ├── include\  (sapnwrfc.h, ...)
│   │   └── lib\      (sapnwrfc.dll, libsapucum.dll, icu*57.dll, *.lib)
│   ├── nwrfcsdk.source.txt                   ← name of the SAP zip nwrfcsdk\ came from
│   ├── php-sdk\                              ← PHP SDK binary tools
│   ├── php-8.5.12-ts-x64\                    ← PHP binary, one folder per variant
│   ├── php-8.5.12-nts-x64\
│   ├── php-devel-pack-8.5.12-Win32-vs17-x64\ ← devel pack, one folder per variant
│   ├── php-devel-pack-8.5.12-nts-Win32-vs17-x64\
│   └── ...                                   ← same for every other PHP version
└── output\                                   ← finished DLLs, one per variant
    ├── php_sapnwrfc-2.2.0+php.8.2.35-nts-vs16-x64.sdk.7540.719.35.dll
    ├── php_sapnwrfc-2.2.0+php.8.2.35-ts-vs16-x64.sdk.7540.719.35.dll
    ├── ...
    ├── php_sapnwrfc-2.2.0+php.8.6.0RC4-nts-vs18-x64.sdk.7540.719.35.dll
    └── php_sapnwrfc-2.2.0+php.8.6.0RC4-ts-vs18-x64.sdk.7540.719.35.dll
```

During the build, `nmake` also writes intermediate files to `x64\Release\` (NTS) and
`x64\Release_TS\` (TS) in the repository root. The script deletes these folders before each
variant, so objects compiled against one PHP version are never reused for another.

`workspace\` can be deleted at any time; the next run extracts everything again. Old versions
are not removed automatically, so after switching PHP versions it fills up over time.

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
4. Checks that `.\sap\` contains exactly one zip. If `workspace\nwrfcsdk` was extracted from a
   different zip (see `workspace\nwrfcsdk.source.txt`), it is removed. The SDK is then extracted
   into `workspace\nwrfcsdk` if needed, and its version is read from `sapnwrfc.dll`.
5. Extracts the PHP SDK binary tools from `.\php\php-sdk-binary-tools-*.zip` into `workspace\php-sdk`.
6. For **each** PHP variant:
   a. Extracts the PHP binary zip to `workspace\php-{ver}-{ts|nts}-{arch}`.
   b. Extracts the matching devel zip to `workspace\php-devel-pack-{ver}[-nts]-Win32-{toolset}-{arch}`.
   c. Deletes the previous build output in `x64\Release` or `x64\Release_TS`.
   d. Sets up the correct MSVC environment (via `phpsdk-{toolset}-{arch}.bat` for same-toolset builds, or `vcvarsall.bat -vcvars_ver` for cross-toolset builds) and runs:
      ```
      phpize
      configure --with-prefix=<phpDir> --with-sapnwrfc=<nwrfcsdkDir>
      nmake
      ```
   e. Copies the built DLL to `.\output\` with a versioned filename.
7. Prints a summary of all built DLLs.

---

## Output

All DLLs land directly in `build\output\` with a filename that encodes every relevant version:

```
php_sapnwrfc-{ext_ver}+php.{php_ver}-{ts|nts}-{toolset}-{arch}.sdk.{sdk_ver}.dll
```

`{sdk_ver}` is the file version of `sapnwrfc.dll` (major.minor.build). Example for SAP NW RFC
SDK 7.50 PL 20:

```
php_sapnwrfc-2.2.0+php.8.5.12-ts-vs17-x64.sdk.7540.719.35.dll
php_sapnwrfc-2.2.0+php.8.5.12-nts-vs17-x64.sdk.7540.719.35.dll
```

Existing DLLs in `output\` are not removed. After switching the SAP SDK or the PHP versions,
delete the old ones before publishing a release, otherwise they are uploaded too.

---

## Installing the built extension

1. Pick the DLL that matches your PHP: same version, TS or NTS (`php -v` shows `ZTS` or `NTS`).
2. Copy it to your PHP `ext\` directory as `php_sapnwrfc.dll`.
3. Add the following to `php.ini`:
   ```ini
   extension=sapnwrfc
   ```
4. Make the SAP NW RFC SDK DLLs from `nwrfcsdk\lib\` (`sapnwrfc.dll`, `libsapucum.dll`,
   `icudt57.dll`, `icuin57.dll`, `icuuc57.dll`) available to PHP. Either copy them next to
   `php.exe` (for a web server, next to its executable) or add `nwrfcsdk\lib\` to the system
   `PATH`.

Example installation:

```
C:\php\
├── php.exe
├── php.ini                    ← contains extension=sapnwrfc
├── sapnwrfc.dll               ← from nwrfcsdk\lib\
├── libsapucum.dll
├── icudt57.dll
├── icuin57.dll
├── icuuc57.dll
└── ext\
    └── php_sapnwrfc.dll       ← renamed from php_sapnwrfc-2.2.0+php.8.5.12-nts-vs17-x64.sdk.7540.719.35.dll
```

Verify with:

```
php -m | findstr sapnwrfc
php -r "echo SAPNWRFC\Connection::rfcVersion();"
```

> **Note:** Windows searches `C:\Windows\System32` before `PATH`. If an older `sapnwrfc.dll`
> lies there, PHP loads that one instead of the SDK on `PATH`. `rfcVersion()` shows which SDK
> was actually loaded. Copying the SDK DLLs next to `php.exe` always takes precedence.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| No PHP zips found | Place binary zips in `build\php\` with the expected naming pattern |
| Unwanted PHP versions are built | Every zip directly in `build\php\` is built — move the others into a subfolder |
| No SAP SDK zip found | Place the SAP zip in `build\sap\` |
| More than one SAP NW RFC SDK zip found | Keep only one zip in `build\sap\`, move the others into a subfolder |
| Devel package not found | Place the matching `php-devel-pack-{ver}[-nts]-Win32-{toolset}-x64.zip` in `build\php\` |
| PHP SDK zip not found | Place `php-sdk-binary-tools-*.zip` in `build\php\` |
| `phpize` not found | Devel package not on PATH — check that extraction succeeded in `workspace\` |
| `configure` fails: SDK not found | Verify extracted SDK has `include\` and `lib\` under `workspace\nwrfcsdk` |
| `phpsdk-vs1X-x64.bat` not found | Toolset mismatch — use `-Toolset` to select an available toolset |
| MSVC toolset not found | Install the required v142/v143 component via VS Installer (see Prerequisites) |
| Tests fail: module not loaded | Ensure `workspace\nwrfcsdk\lib` is on `PATH` (`-RunTests` adds it automatically) |
| `rfcVersion()` shows an unexpected SDK version | An older `sapnwrfc.dll` in `C:\Windows\System32` wins over `PATH` — copy the SDK DLLs next to `php.exe` (this also applies to `-RunTests`) |
