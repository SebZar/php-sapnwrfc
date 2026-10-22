
# SAP NW RFC extension for PHP 8

[![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg?logo=paypal)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=WC3SGPNSW2NV4&source=url)

This extension is intended to provide a means for PHP 8 developers to interface with the SAP NetWeaver SDK.

If you find this project useful consider giving me a cup of coffee using the "Donate" button above.

## Supported versions

The extension is tested with PHP 8.1+ using SAP NW RFC SDK version 7.50.

## Usage

You can find detailed instructions on how to build and use this extension at https://gkralik.github.io/php7-sapnwrfc.

## Building on Windows

A PowerShell build script is provided for Windows. It handles all PHP variants (TS/NTS, multiple
PHP versions and toolsets) in a single run with no manual VS environment setup.

**Quick start:**

1. Place the PHP binary + devel zips and the PHP SDK zip in `build\php\`, and exactly one
   SAP NW RFC SDK zip in `build\sap\`:

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
    └── nwrfc750P_20-70002755.zip
```

2. Run from the `build\` directory:

```powershell
.\build-windows.ps1
```

Built DLLs land in `build\output\` with versioned filenames:

```
php_sapnwrfc-2.2.0+php.8.5.12-ts-vs17-x64.sdk.7540.719.35.dll
```

Builds, loads and passes the offline test suite on Windows x64 with PHP 8.2, 8.3, 8.4, 8.5 and
8.6.0RC4 (TS and NTS) and SAP NW RFC SDK 7.50 PL 20.

See [`build/build-windows.md`](build/build-windows.md) for the full folder layout, prerequisites
and options.

## API additions (this fork)

This fork adds the following methods to `SAPNWRFC\Connection`:

| Method | Description |
|--------|-------------|
| `isOpen(): bool` | Returns `true` if the connection handle is currently open |
| `reconnect(): bool` | Closes the current connection and opens a new one using the stored login parameters |

## Contributing

Contribution to the project (be it by reporting/fixing bugs, writing documentation, helping with testing) is very welcome.
Just open up an issue or a PR.

## License

This software is licensed under the MIT license. See [LICENSE](LICENSE) for details.

## Legal notice

SAP and other SAP products and services mentioned herein are trademarks or registered trademarks of SAP SE (or an SAP affiliate company) in Germany and other countries.
