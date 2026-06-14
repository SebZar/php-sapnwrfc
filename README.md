
# SAP NW RFC extension for PHP 8

[![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg?logo=paypal)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=WC3SGPNSW2NV4&source=url)

This extension is intended to provide a means for PHP 8 developers to interface with the SAP NetWeaver SDK.

If you find this project useful consider giving me a cup of coffee using the "Donate" button above.

## Supported versions

The extension is tested with PHP 8.1+ using SAP NW RFC SDK version 7.50.

The repository is called `php7-sapnwrfc` for historical reasons only.

## Usage

You can find detailed instructions on how to build and use this extension at https://gkralik.github.io/php7-sapnwrfc.

## Building on Windows

A PowerShell build script is provided for Windows. It handles all PHP variants (TS/NTS, multiple
PHP versions and toolsets) in a single run with no manual VS environment setup.

**Quick start:**

1. Place PHP binary + devel zips, the PHP SDK zip, and the SAP NW RFC SDK zip in `build\php\`
   and `build\sap\` respectively (see [`build/build-windows.md`](build/build-windows.md)).
2. Run from the `build\` directory:

```powershell
.\build-windows.ps1
```

Built DLLs land in `build\output\` with versioned filenames:

```
php_sapnwrfc-2.1.0+php.8.3.31-ts-vs16-x64.sdk.7500.0.13.dll
```

See [`build/build-windows.md`](build/build-windows.md) for full prerequisites and options.

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
