# Examples

Small, self-contained scripts that show common tasks with the `sapnwrfc` extension. They only
use standard SAP objects, so they run against any ABAP system you have access to.

| Script | What it shows |
|--------|---------------|
| [`read_table.php`](read_table.php) | Read rows from a table with `RFC_READ_TABLE`: field selection, WHERE condition split into 72-character lines, paging with `ROWSKIPS`/`ROWCOUNT`, parsing fixed-width rows via `FIELDS` offsets |
| [`call_bapi.php`](call_bapi.php) | Query data through BAPIs (`BAPI_COMPANYCODE_GETLIST`, `BAPI_COMPANYCODE_GETDETAIL`) and check the `RETURN` parameter for business errors |

## Running the examples

1. Install the extension and the SAP NW RFC SDK libraries
   (see [`build/build-windows.md`](../build/build-windows.md) for Windows).
2. Copy `config.php.dist` to `config.php` and fill in your connection parameters.
   `config.php` is ignored by git.
3. Run a script from this directory:

```
php read_table.php
php call_bapi.php
```

`read_table.php` needs the `mbstring` extension, because field offsets from SAP are counted in
characters, not bytes.

## Requirements in the SAP system

- An RFC user with authorization object `S_RFC` for the function groups used:
  `SDTX` (`RFC_READ_TABLE`) and `0002` (company code BAPIs).
- For `RFC_READ_TABLE`, read authorization for the table (`S_TABU_DIS` for its
  authorization group, or `S_TABU_NAM` for the table name).
- The company code BAPIs exist in SAP ERP and S/4HANA. A plain NetWeaver system without
  the financials component does not have them.

## Things to keep in mind

- **Errors come in two kinds.** Technical problems (connection lost, function or parameter
  unknown, missing authorization, an ABAP exception such as `NOT_AUTHORIZED`) throw a
  `SAPNWRFC\FunctionCallException` or `SAPNWRFC\ConnectionException`. `getErrorInfo()` returns
  details; for ABAP exceptions its `key` is the exception name. Business errors of a BAPI do not
  throw: they are reported in its `RETURN` parameter and must be checked.
- **CHAR fields are padded with blanks.** Pass `['rtrim' => true]` as second argument to
  `invoke()` to get trimmed values.
- **Internal formats.** Dates come as `YYYYMMDD`, times as `HHMMSS`, packed numbers as strings.
  Keys are often stored with leading zeros (conversion exit `ALPHA`), and language keys in the
  database are one letter (`E`, `D`), not the two-letter ISO code.
- **Reuse function objects.** `Connection::getFunction()` fetches the interface description;
  keep the returned `RemoteFunction` and call `invoke()` on it repeatedly. Leave the connection
  option `use_function_desc_cache` at its default `true`.
- **`RFC_READ_TABLE` has limits.** All selected fields together must fit into 512 characters
  per row (`DATA_BUFFER_EXCEEDED` otherwise), and it is not meant for mass data. For large or
  wide tables, use a BAPI or a dedicated function module.
- **Write BAPIs need a commit.** BAPIs that change data only take effect after
  `BAPI_TRANSACTION_COMMIT` is called on the same connection.
