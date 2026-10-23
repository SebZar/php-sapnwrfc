# php-sapnwrfc

A PHP extension for the SAP NetWeaver RFC SDK. It lets PHP 8 call remote-enabled ABAP function
modules (RFC and BAPI) on SAP systems.

```php
$connection = new SAPNWRFC\Connection([
    'ashost' => 'sap.example.com',
    'sysnr'  => '00',
    'client' => '100',
    'user'   => 'RFC_USER',
    'passwd' => 'secret',
]);

$result = $connection->getFunction('STFC_CONNECTION')->invoke(['REQUTEXT' => 'Hello SAP']);

echo $result['ECHOTEXT'];   // Hello SAP
```

## Contents

- [Features](#features)
- [Supported versions](#supported-versions)
- [Installation on Windows](#installation-on-windows)
- [Building from source](#building-from-source)
- [Usage](#usage)
- [API overview](#api-overview)
- [Type mapping](#type-mapping)
- [Testing](#testing)
- [Changelog, license, origin](#changelog-license-origin)

## Features

- Connect directly to an application server, via message server and logon group, or through a
  SAProuter; or use a `sapnwrfc.ini` file
- Call any remote-enabled function module with import, export, changing and table parameters
- Automatic conversion between ABAP and PHP types, including structures and tables
- UTF-8 on the PHP side, SAP Unicode on the SAP side
- Exceptions with the full RFC error information (`getErrorInfo()`)
- Function descriptions, parameter activation, SSO tickets, tracing
- Prebuilt Windows DLLs for PHP 8.2 to 8.5, TS and NTS

## Supported versions

| | |
|---|---|
| PHP | 8.2, 8.3, 8.4, 8.5; 8.6 from source (built against 8.6.0RC4) |
| SAP NW RFC SDK | 7.50 (built with patch level 20) |
| Platforms | Windows x64 (prebuilt DLLs), Linux x64 (build from source) |

The Windows builds are compiled for every version above, load in their PHP, and pass the
offline test suite. Tests against a live SAP system need your own system, see [Testing](#testing).

## Installation on Windows

### 1. Download the extension

Download the zip for your PHP version from the
[releases](https://github.com/SebZar/php-sapnwrfc/releases), e.g.
`php_sapnwrfc-2.2.0+php.8.5.12-vs17-x64.zip`. Each zip contains two DLLs:

| DLL | For |
|-----|-----|
| `...-ts-...dll` | Thread-safe PHP (Apache `mod_php`) |
| `...-nts-...dll` | Non-thread-safe PHP (PHP-FPM, FastCGI, IIS, CLI) |

`php -v` shows which one you have: `ZTS` means TS, `NTS` means NTS. The DLL must match the PHP
minor version (8.5 for 8.5.x); the patch version may differ.

### 2. Get the SAP NW RFC SDK

The SDK is not included and must be downloaded from SAP (SAP account required): search for
"SAP NW RFC SDK 7.50" in the [SAP Software Center](https://me.sap.com/softwarecenter).

### 3. Install

```
C:\php\
├── php.exe
├── php.ini                    ← add: extension=sapnwrfc
├── sapnwrfc.dll               ┐
├── libsapucum.dll             │
├── icudt57.dll                │ from the SDK's lib\ folder
├── icuin57.dll                │
├── icuuc57.dll                ┘
└── ext\
    └── php_sapnwrfc.dll       ← the matching DLL from the zip, renamed
```

Instead of copying the SDK DLLs next to `php.exe` (or next to your web server's executable),
you can add the SDK's `lib\` folder to the system `PATH`.

> **Note:** Windows looks in `C:\Windows\System32` before `PATH`. An old `sapnwrfc.dll` there
> takes precedence over the one on `PATH`. Copying the SDK DLLs next to `php.exe` always wins.

### 4. Verify

```
php -m | findstr sapnwrfc
php -r "echo SAPNWRFC\Connection::version(), ' / SDK ', SAPNWRFC\Connection::rfcVersion();"
```

## Building from source

### Linux

Install the SDK, e.g. to `/usr/local/sap/nwrfcsdk`, then:

```bash
phpize
./configure --with-sapnwrfc=/usr/local/sap/nwrfcsdk
make
sudo make install
```

Without a path, `configure` searches `/usr/sap/nwrfcsdk`, `/usr/local/sap/nwrfcsdk`,
`/usr/local/nwrfcsdk` and `/opt/nwrfcsdk`. Add `extension=sapnwrfc` to your `php.ini` and make
sure the SDK's `lib` directory is known to the dynamic linker (e.g. via `/etc/ld.so.conf.d/`
and `ldconfig`).

### Windows

A PowerShell script builds the extension for every PHP version and TS/NTS variant in one run,
with the matching Visual Studio toolset for each:

```
build\
├── php\
│   ├── php-8.5.12-Win32-vs17-x64.zip
│   ├── php-8.5.12-nts-Win32-vs17-x64.zip
│   ├── php-devel-pack-8.5.12-Win32-vs17-x64.zip
│   ├── php-devel-pack-8.5.12-nts-Win32-vs17-x64.zip
│   ├── ...                                   ← same four zips for every other PHP version
│   └── php-sdk-binary-tools-php-sdk-2.7.1.zip
└── sap\
    └── nwrfc750P_20-70002755.zip             ← exactly one SAP NW RFC SDK zip
```

```powershell
cd build
.\build-windows.ps1
```

The DLLs land in `build\output\`, e.g.
`php_sapnwrfc-2.2.0+php.8.5.12-ts-vs17-x64.sdk.7540.719.35.dll`.
[`build/build-windows.md`](build/build-windows.md) describes the prerequisites, the full folder
layout and all options; [`build/publish-github-release.md`](build/publish-github-release.md)
describes how the DLLs are published as a release.

## Usage

### Connecting

```php
use SAPNWRFC\Connection;

$connection = new Connection([
    'ashost' => 'sap.example.com',   // application server
    'sysnr'  => '00',
    'client' => '100',
    'user'   => 'RFC_USER',
    'passwd' => 'secret',
    'lang'   => 'EN',
    // load balancing instead of ashost/sysnr:
    // 'mshost' => 'sap-ms.example.com', 'sysid' => 'PRD', 'group' => 'PUBLIC',
    // through a SAProuter:
    // 'saprouter' => '/H/saprouter.example.com/H/',
]);

// ...

$connection->close();
```

Any parameter of the `sapnwrfc.ini` file can be passed. To read the parameters from a
`sapnwrfc.ini` instead, use `Connection::setIniPath()` and pass `['dest' => '<name>']`.

### Calling a function module

```php
$function = $connection->getFunction('BAPI_COMPANYCODE_GETDETAIL');

$result = $function->invoke(
    ['COMPANYCODEID' => '1000'],    // import, changing and table parameters
    ['rtrim' => true]               // remove the blanks SAP pads CHAR fields with
);

echo $result['COMPANYCODE_DETAIL']['COMP_NAME'];
```

`invoke()` returns all export, changing and table parameters as an array. Structures become
associative arrays, tables become lists of associative arrays. Keep the `RemoteFunction` object
and call `invoke()` on it repeatedly instead of calling `getFunction()` again.

### Handling errors

```php
use SAPNWRFC\ConnectionException;
use SAPNWRFC\FunctionCallException;

try {
    $result = $function->invoke($parameters);
} catch (ConnectionException $e) {
    // Logon failed, host not reachable, connection lost
} catch (FunctionCallException $e) {
    // Function or parameter unknown, wrong type, missing authorization, ABAP exception
    $info = $e->getErrorInfo();   // code, key, message, abapMsgClass, abapMsgNumber, ...
}
```

For an ABAP exception, `getErrorInfo()['key']` is the exception name, e.g. `NOT_AUTHORIZED`.
BAPIs usually do not throw: they report errors in their `RETURN` parameter, which you have to
check yourself.

### Examples

[`examples/`](examples/) contains runnable scripts for common tasks:

- [`read_table.php`](examples/read_table.php): read a table with `RFC_READ_TABLE`, with WHERE
  condition, paging and parsing of the fixed-width rows
- [`call_bapi.php`](examples/call_bapi.php): query data through BAPIs and check `RETURN`

## API overview

All classes are in the `SAPNWRFC` namespace. [`docs/sapnwrfc.stubs.php`](docs/sapnwrfc.stubs.php)
contains the full signatures with doc comments for your IDE.

**`Connection`**

| Method | Description |
|--------|-------------|
| `__construct(array $parameters, array $options = [])` | Open a connection |
| `getFunction(string $name, bool $invalidateCache = false): RemoteFunction` | Look up a function module |
| `getAttributes(): array` | Connection details (system ID, client, user, host, release, ...) |
| `ping(): bool` | Check the connection with a round trip |
| `isOpen(): bool` | Check whether the connection is open, without a round trip |
| `reconnect(): bool` | Close and reopen the connection with the same parameters |
| `close(): bool` | Close the connection |
| `getSSOTicket(): string` | SSO ticket of the connection (requires `GETSSO2=1`) |
| `static setIniPath(string $path)`, `static reloadIniFile()` | Use a `sapnwrfc.ini` file |
| `static setTraceDir(string $path)`, `static setTraceLevel(int $level)` | RFC trace (`TRACE_LEVEL_OFF` ... `TRACE_LEVEL_FULL`) |
| `static setGlobalLogonTimeout(int $seconds)` | Logon timeout, 1–3600 s |
| `static version()`, `static rfcVersion()` | Extension and SDK version |

**`RemoteFunction`**

| Method | Description |
|--------|-------------|
| `invoke(array $parameters = [], array $options = []): array` | Call the function module |
| `getName(): string` | Name of the function module |
| `getFunctionDescription(): array` | Parameters with type, direction, length and field definitions |
| `setParameterActive(string $name, bool $active)`, `isParameterActive(string $name)` | Leave out parameters you do not need |

**Exceptions:** `Exception` (extends `RuntimeException`, adds `getErrorInfo()`), with the
subclasses `ConnectionException` and `FunctionCallException`.

**Options**

| Option | Where | Description |
|--------|-------|-------------|
| `rtrim` | `invoke()` | Right-trim CHAR values. Default `false` |
| `use_function_desc_cache` | `Connection` | Default `true`. Leave it on: with `false`, the description is deleted and fetched again on every `getFunction()`, and older `RemoteFunction` objects for the same function must not be used anymore |

The function description cache can also be cleared for a single function with
`SAPNWRFC\clearFunctionDescCache($name, $sysId)`.

## Type mapping

| ABAP type | PHP type | Notes |
|-----------|----------|-------|
| C (CHAR) | string | Padded with blanks, see `rtrim` |
| N (NUMC) | string | Digits, often with leading zeros |
| D (DATE) | string | `YYYYMMDD` |
| T (TIME) | string | `HHMMSS` |
| STRING | string | |
| X, XSTRING | string | Hexadecimal; `hex2bin()` for binary |
| I, INT1, INT2, INT8 | int | Passing a value outside the ABAP type's range throws |
| F (FLOAT) | float | |
| P (packed), DECFLOAT16/34 | string | Strings avoid rounding errors |
| Structure | array | Field name ⇒ value |
| Table | array | List of structures |

## Testing

Tests use PHP's PHPT format:

```bash
make test                       # Linux
nmake test                      # Windows, or build-windows.ps1 -RunTests
```

Without further setup only the offline tests run. For the tests against an SAP system, copy
`tests/sapnwrfc.config.inc.dist` to `tests/sapnwrfc.config.inc`, fill in your connection and
set `SAPNWRFC_ONLINE=1`. Tests that need custom ABAP function modules additionally require
`SAPNWRFC_CUSTOM=1`.

## Changelog, license, origin

- Changes per version: [`CHANGELOG.md`](CHANGELOG.md)
- License: MIT, see [`LICENSE`](LICENSE)
- Contributions are welcome. Open an issue or a pull request.

This project is a fork of [gkralik/php7-sapnwrfc](https://github.com/gkralik/php7-sapnwrfc) by
Gregor Kralik, which in turn is a rewrite of Piers Harding's
[php-sapnwrfc](https://github.com/piersharding/php-sapnwrfc) for PHP 5. See
[`CREDITS.md`](CREDITS.md).

SAP and other SAP products and services mentioned herein are trademarks or registered trademarks
of SAP SE (or an SAP affiliate company) in Germany and other countries.
