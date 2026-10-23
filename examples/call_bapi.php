<?php

/*
 * Query data through a BAPI and check its RETURN parameter.
 *
 * Lists all company codes with BAPI_COMPANYCODE_GETLIST and fetches the
 * details of the first one with BAPI_COMPANYCODE_GETDETAIL. Both are
 * standard BAPIs of SAP ERP and S/4HANA (not available on a plain
 * NetWeaver system without the financials component).
 *
 *     php call_bapi.php
 *
 * BAPIs report business errors in their RETURN parameter instead of raising
 * an ABAP exception: invoke() succeeds, and RETURN contains a message of type
 * E (error) or A (abort). Always check it.
 */

use SAPNWRFC\Connection;
use SAPNWRFC\ConnectionException;
use SAPNWRFC\FunctionCallException;

/**
 * Throw if a BAPI RETURN parameter contains an error.
 *
 * Depending on the BAPI, RETURN is a single structure (BAPIRETURN, BAPIRET1)
 * or a table of messages (BAPIRET2). Both shapes are handled.
 *
 * @param array $return The RETURN value from invoke()
 * @return array[] The messages, for logging warnings etc.
 */
function checkBapiReturn(array $return): array
{
    $messages = isset($return['TYPE']) ? [$return] : $return;

    foreach ($messages as $message) {
        if (in_array($message['TYPE'], ['E', 'A'], true)) {
            throw new RuntimeException("BAPI error: {$message['MESSAGE']}");
        }
    }

    // An empty structure (TYPE = '') means success without a message
    return array_values(array_filter($messages, fn ($m) => $m['TYPE'] !== ''));
}

$config = require __DIR__ . '/config.php';

try {
    $connection = new Connection($config);

    // getFunction() looks up the interface once per connection; reuse the
    // returned object for repeated calls instead of looking it up again.
    $getList   = $connection->getFunction('BAPI_COMPANYCODE_GETLIST');
    $getDetail = $connection->getFunction('BAPI_COMPANYCODE_GETDETAIL');

    // rtrim removes the blanks SAP pads CHAR fields with
    $list = $getList->invoke([], ['rtrim' => true]);
    checkBapiReturn($list['RETURN']);

    foreach ($list['COMPANYCODE_LIST'] as $companyCode) {
        printf("%-4s  %s\n", $companyCode['COMP_CODE'], $companyCode['COMP_NAME']);
    }

    if ($list['COMPANYCODE_LIST'] === []) {
        echo "No company codes found.\n";
    } else {
        $first  = $list['COMPANYCODE_LIST'][0]['COMP_CODE'];
        $detail = $getDetail->invoke(['COMPANYCODEID' => $first], ['rtrim' => true]);
        checkBapiReturn($detail['RETURN']);

        $d = $detail['COMPANYCODE_DETAIL'];
        echo "\nDetails for $first:\n";
        printf("  Name     : %s\n", $d['COMP_NAME']);
        printf("  City     : %s\n", $d['CITY']);
        printf("  Country  : %s\n", $d['COUNTRY']);
        printf("  Currency : %s\n", $d['CURRENCY']);
    }

    $connection->close();
} catch (ConnectionException $e) {
    // getMessage() is generic; getErrorInfo() says why, e.g. key
    // RFC_COMMUNICATION_FAILURE (host not reached) or RFC_LOGON_FAILURE
    $info = $e->getErrorInfo();
    fwrite(STDERR, "Connection failed: {$info['key']}\n" . trim($info['message']) . "\n");
    exit(1);
} catch (FunctionCallException $e) {
    // Technical errors: function not found, wrong parameter names or types,
    // missing RFC authorization (S_RFC), communication failures
    $info = $e->getErrorInfo();
    fwrite(STDERR, "RFC call failed: {$info['key']} - " . trim($info['message']) . "\n");
    exit(1);
} catch (RuntimeException $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}
