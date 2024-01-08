// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import {Addresses} from "../Addresses.sol";

contract AddressesStaging is Addresses {
    address internal constant MULTISIG = 0x541728b0161eEa30606651Cb28Ea8A66652b9e57;

    address internal constant STRUCT_PRICE_ORACLE = 0xBB798bd51fEf68ec33530258a19c3Aeb45302EA0;
    address internal constant STRUCT_DISTRIBUTION_MANAGER = address(0);
    address internal constant GAC = 0x9EEb3d462865818B6189033FAEdd6DB79af70229;
    address internal constant STRUCT_SP_TOKEN = address(0);

    address internal constant GMX_PRODUCT_FACTORY = 0xe7ddd77198924631e65Df9cBE1140C48765d2162;

    address internal constant AUTOPOOL_FACTORY = address(0);
    address payable internal constant AUTOPOOL_PRODUCT_IMPLEMENTATION = payable(address(0));
    address internal constant AVAX_USDC_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant AVAX_BTCB_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant AVAX_WETHE_AUTOPOOL_YIELDSOURCE = address(0);
    address internal constant EUROC_USDC_AUTOPOOL_YIELDSOURCE = address(0);

    address internal constant STRUCT_REWARDER = address(0);
}
