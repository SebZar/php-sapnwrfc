# Building php-sapnwrfc on Windows

## Prerequisites

### 1. Visual Studio with MSVC v143 toolset

Install **Visual Studio 2022** (or newer) with the **"Desktop development with C++"** workload,
and make sure the **MSVC v143 – VS 2022 C++ x64/x86 Build Tools** component is included.
PHP 8.5 Windows binaries are compiled with v143 (vs17); the extension must use the same toolset.

Download: https://visualstudio.microsoft.com/downloads/

### 2. PHP zips (binary + devel)

Place all four zips in the `build\php\` folder:

| File | Purpose |
|------|---------|
| `php-{ver}-Win32-vs17-x64.zip` | TS binary (provides `php.exe`) |
| `php-{ver}-nts-Win32-vs17-x64.zip` | NTS binary |
| `php-{ver}-devel-vs17-x64.zip` | TS devel (provides `phpize` + headers) |
| `php-{ver}-nts-devel-vs17-x64.zip` | NTS devel |

Download from https://windows.php.net/download/ — choose the **zip** packages (not the installer).

### 3. SAP NW RFC SDK

Place the SAP NW RFC SDK zip (e.g. `nwrfc750P_18-70002755.zip`) in the `build\sap\` folder.
Obtain it from the SAP Software Downloads portal (requires SAP account).

Expected layout inside the zip:

```
nwrfcsdk\
  include\   ← header files
  lib\        ← sapnwrfc.lib, libsapucum.lib, *.dll
```

### 4. Git

Required to clone the PHP SDK binary tools. https://git-scm.com/

### 5. Internet access (first run only)

The script clones the PHP SDK binary tools from GitHub (`php/php-sdk-binary-tools`).
All PHP packages are taken from the local `build\php\` folder — no other downloads.

---

## Running the build

Open **PowerShell** and run from the `build\` directory:

```powershell
cd path\to\php-sapnwrfc\build
.\build-windows.ps1
```

The script automatically finds every PHP zip in `.\php\` and builds the extension for each variant.
Output lands in `build\workspace\` (created automatically next to the script).

### Optional parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-WorkspaceDir` | Where extractions and the PHP SDK clone land | `.\workspace` |
| `-Toolset` | Override the MSVC toolset (e.g. `vs17`, `vs18`) | auto-detected from zip name |
| `-SkipPhpSdk` | Skip git pull of PHP SDK tools | — |
| `-RunTests` | Run `nmake test` after each build | — |

Examples:

```powershell
# Force toolset (e.g. when installed VS differs from zip name)
.\build-windows.ps1 -Toolset vs17

# Custom workspace, run tests
.\build-windows.ps1 -WorkspaceDir "D:\build" -RunTests

# Skip PHP SDK re-clone on subsequent runs
.\build-windows.ps1 -SkipPhpSdk
```

### Script execution policy

If you get a script-execution error, allow local scripts for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

## What the script does

1. Scans `.\php\*.zip` to discover PHP variants (TS / NTS, version, toolset, arch).
2. Detects the installed Visual Studio via `vswhere` and warns if it differs from the zip toolset.
3. Extracts the SAP NW RFC SDK from `.\sap\*.zip` into `workspace\nwrfcsdk`.
4. Clones (or updates) the PHP SDK binary tools into `workspace\php-sdk`.
5. For **each** PHP variant:
   a. Extracts the PHP binary zip to `workspace\php-{ver}-{ts|nts}`.
   b. Extracts the matching devel zip from `.\php\` to `workspace\php-{ver}-{nts-}devel-…`.
   c. Runs the build inside the MSVC environment set up by `phpsdk-vs17-x64.bat`:
      ```
      phpize
      configure --with-prefix=<phpDir> --with-sapnwrfc=<nwrfcsdkDir>
      nmake
      ```
   d. Reports the path to the built DLL.
6. Prints a summary of all built DLLs.

---

## Output DLL locations

| Variant | Path relative to repo root |
|---------|---------------------------|
| TS | `x64\Release_TS\php_sapnwrfc.dll` |
| NTS | `x64\Release\php_sapnwrfc.dll` |

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
| No PHP zips found | Place binary zip(s) in `build\php\` with the expected naming pattern |
| No SAP SDK zip found | Place the SAP zip in `build\sap\` |
| Devel package not found | Place the matching `php-{ver}-{nts-}devel-vs17-x64.zip` in `build\php\` |
| `phpize` not found | Devel package not on PATH — check that extraction succeeded in `workspace\` |
| `configure` fails: SDK not found | Verify extracted SDK has `include\` and `lib\` under `workspace\nwrfcsdk` |
| `phpsdk-vs17-x64.bat` not found | PHP SDK not yet cloned — run without `-SkipPhpSdk`; or toolset mismatch — use `-Toolset` |
| VS toolset warning at startup | Installed VS differs from zip toolset — use `-Toolset vs17` to match the PHP 8.5 build |
| Tests fail: module not loaded | Ensure `workspace\nwrfcsdk\lib` is on `PATH` (`-RunTests` does this automatically) |
