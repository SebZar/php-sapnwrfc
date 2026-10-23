<?php

/*
 * Read rows from an SAP table with RFC_READ_TABLE.
 *
 * Reads country names from the standard table T005T, which exists in every
 * ABAP system, and prints them page by page.
 *
 *     php read_table.php
 *
 * RFC_READ_TABLE is convenient for small lookups, but has limits:
 * - All selected fields together must fit into 512 characters per row
 *   (exception DATA_BUFFER_EXCEEDED). Select only the fields you need.
 * - The WHERE clause is passed as lines of at most 72 characters.
 * - The caller needs read authorization for the table (S_TABU_DIS/S_TABU_NAM).
 * For large or wide tables a dedicated BAPI or a custom function module is
 * usually the better choice.
 */

use SAPNWRFC\Connection;
use SAPNWRFC\ConnectionException;
use SAPNWRFC\FunctionCallException;
use SAPNWRFC\RemoteFunction;

/**
 * Read rows from a table, one page at a time.
 *
 * @param RemoteFunction $readTable Function object for RFC_READ_TABLE
 * @param string   $table    Table name, e.g. 'T005T'
 * @param string[] $fields   Field names to read
 * @param string   $where    Open SQL WHERE condition without "WHERE", or ''
 * @param int      $pageSize Rows per call
 * @return Generator<int, array<string, string>> Rows as field => value
 */
function readTable(RemoteFunction $readTable, string $table, array $fields, string $where = '', int $pageSize = 500): Generator
{
    $options = [];
    foreach (splitWhere($where) as $line) {
        $options[] = ['TEXT' => $line];
    }

    $skip = 0;
    do {
        $result = $readTable->invoke([
            'QUERY_TABLE' => $table,
            'FIELDS'      => array_map(fn ($name) => ['FIELDNAME' => $name], $fields),
            'OPTIONS'     => $options,
            'ROWSKIPS'    => $skip,
            'ROWCOUNT'    => $pageSize,
        ], ['rtrim' => true]);

        // Without a DELIMITER, every row in DATA is one fixed-width line. FIELDS
        // returns where each field starts (OFFSET) and how long it is (LENGTH),
        // in characters. Slicing by offset also works when a value contains
        // the character you would otherwise use as delimiter.
        foreach ($result['DATA'] as $row) {
            $line   = $row['WA'];
            $record = [];
            foreach ($result['FIELDS'] as $field) {
                $value = mb_substr($line, (int) $field['OFFSET'], (int) $field['LENGTH'], 'UTF-8');
                $record[$field['FIELDNAME']] = rtrim($value);
            }
            yield $record;
        }

        $skip += $pageSize;
    } while (count($result['DATA']) === $pageSize);
}

/**
 * Split a WHERE condition into lines of at most 72 characters, breaking only
 * between tokens so that no field name or literal is cut in half. A literal
 * in single quotes ('New Zealand', 'O''Brien') stays one token, including
 * its spaces.
 *
 * @return string[]
 */
function splitWhere(string $where, int $width = 72): array
{
    preg_match_all("/'(?:[^']|'')*'|[^\s']+/u", $where, $matches);

    $lines = [];
    $line  = '';
    foreach ($matches[0] as $word) {
        if (mb_strlen($word, 'UTF-8') > $width) {
            throw new InvalidArgumentException("WHERE token longer than $width characters: $word");
        }
        $candidate = $line === '' ? $word : "$line $word";
        if (mb_strlen($candidate, 'UTF-8') > $width) {
            $lines[] = $line;
            $candidate = $word;
        }
        $line = $candidate;
    }
    if ($line !== '') {
        $lines[] = $line;
    }

    return $lines;
}

$config = require __DIR__ . '/config.php';

try {
    $connection = new Connection($config);

    $readTable = $connection->getFunction('RFC_READ_TABLE');

    // SPRAS holds the internal one-letter language key: 'E' = English, 'D' = German.
    // Literals in the condition are quoted with single quotes, like in ABAP.
    $rows = readTable(
        $readTable,
        'T005T',
        ['LAND1', 'LANDX50'],
        "SPRAS = 'E' AND LAND1 LIKE 'A%'",
        pageSize: 20
    );

    foreach ($rows as $row) {
        printf("%-3s  %s\n", $row['LAND1'], $row['LANDX50']);
    }

    $connection->close();
} catch (ConnectionException $e) {
    // getMessage() is generic; getErrorInfo() says why, e.g. key
    // RFC_COMMUNICATION_FAILURE (host not reached) or RFC_LOGON_FAILURE
    $info = $e->getErrorInfo();
    fwrite(STDERR, "Connection failed: {$info['key']}\n" . trim($info['message']) . "\n");
    exit(1);
} catch (FunctionCallException $e) {
    // For ABAP exceptions, 'key' holds the exception name, e.g.
    // TABLE_NOT_AVAILABLE, NOT_AUTHORIZED, OPTION_NOT_VALID or DATA_BUFFER_EXCEEDED.
    $info = $e->getErrorInfo();
    fwrite(STDERR, "RFC_READ_TABLE failed: {$info['key']} - " . trim($info['message']) . "\n");
    exit(1);
}
