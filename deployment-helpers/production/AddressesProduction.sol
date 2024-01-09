// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import {Addresses} from "../Addresses.sol";

contract AddressesProduction is Addresses {
    address internal constant MULTISIG = 0x0daa96b1127A8792571981917004eCA8be447419;  

    address internal constant STRUCT_PRICE_ORACLE = 0x6F51D8FA3b4F1C65344EBA11d21108fd4a4Fb41E;
    address internal constant STRUCT_DISTRIBUTION_MANAGER = 0xa00c95477be638952C8E11eFEf8260D59d2ee7A3;
    address internal constant GAC = 0xcB4E352825df013D4b827b0E28DE3E996655cb97;
    address internal constant STRUCT_SP_TOKEN = address(0);

    address internal constant GMX_PRODUCT_FACTORY = 0x46f8765781Ac36E5e8F9937658fA311aF9D735d7;

    address internal constant AUTOPOOL_FACTORY = address(0);
    address payable internal constant AUTOPOOL_PRODUCT_IMPLEMENTATION = payable(address(0));
    address internal constant AVAX_USDC_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant AVAX_BTCB_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant AVAX_WETHE_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant EUROC_USDC_AUTOPOOL_YIELDSOURCE = address(0);

    address internal constant STRUCT_REWARDER = address(0);
}
