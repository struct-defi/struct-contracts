// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import {Addresses} from "../Addresses.sol";

contract AddressesDevelop is Addresses {
    address internal constant STRUCT_PRICE_ORACLE = 0x99B67590D71ba003f80e127C9478aE5FD935FaBe;
    address internal constant STRUCT_DISTRIBUTION_MANAGER = 0xEA1f47D21CdE432CB21EAA360Eb98FBE949BB3e0;
    address internal constant GAC = 0xe08E5dD026Ca39067aE648708cF25b27a76A7f9D;
    address internal constant STRUCT_SP_TOKEN = address(0);

    address internal constant GMX_PRODUCT_FACTORY = 0x61d0b5aAC00258CAf31981e3c5e0b61C9ae99A2E;

    address internal constant AUTOPOOL_FACTORY = address(0);
    address payable internal constant AUTOPOOL_PRODUCT_IMPLEMENTATION = payable(address(0));
    address internal constant AVAX_USDC_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant AVAX_BTCB_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant AVAX_WETHE_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant EUROC_USDC_AUTOPOOL_YIELDSOURCE = address(0);

    address[3] internal WHITELISTABLE_ADDRESSES = [
        0x1e90d9909A2B9c2FE75AB4e932241f7c84eFbFe5,
        0x306feC6149922D43C9F82362eF9a063d15e60A44,
        0xe48B5e18Ef29D66228a94543FF70871b8f7d6163
    ];

    address internal constant STRUCT_REWARDER = address(0);
}
