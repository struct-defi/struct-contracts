// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Constants library
 *
 * @author Struct Finance
 */
library Constants {
    /// @dev All the percentage values are 6 decimals so it is used to perform the calculation.
    uint256 public constant DECIMAL_FACTOR = 10 ** 6;

    /// @dev Used in calculations
    uint256 public constant WAD = 10 ** 18;
    uint256 public constant DAYS_IN_YEAR = 365;
    uint256 public constant YEAR_IN_SECONDS = 31536000;

    ///@dev The price maximum deviation allowed between struct price oracle and the AMM
    uint256 public constant MAX_DEVIATION = 50000; //5%

    /// @dev Slippage settings
    uint256 public constant DEFAULT_SLIPPAGE = 30000; //3%
    uint256 public constant MAX_SLIPPAGE = 500000; //50%

    /// @dev GMX prices are scaled to 10**30. This is required to descale them to 10**18
    uint256 public constant GMX_PRICE_DIVISOR = 10 ** 12;
}
