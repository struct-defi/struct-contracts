// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

contract Addresses {
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address internal constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address internal constant BTCB = 0x152b9d0FdC40C096757F570A51E494bd4b943E50;

    address internal MULTISIG;
    address internal AUTO_AVAX;

    address internal constant PRICE_FEED_AVAX = 0x0A77230d17318075983913bC2145DB16C7366156;
    address internal constant PRICE_FEED_USDC = 0xF096872672F44d6EBA71458D74fe67F9a77a23B9;

    address internal STRUCT_PRICE_ORACLE;
    address internal STRUCT_DISTRIBUTION_MANAGER;

    address[] internal WHITELISTABLE_ADDRESSES = [0x0000000000000000000000000000000000000000];

    address internal GAC;
    address internal GMX_PRODUCT_FACTORY;
}
