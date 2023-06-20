// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Modified from Solmate:v6 (https://github.com/transmissions11/solmate/blob/a9e3ea26a2dc73bfa87f0cb189687d029028e0c5/src/utils/FixedPointMathLib.sol)
library WadMath {
    error DivideByZero();

    error Overflow();

    /*///////////////////////////////////////////////////////////////
                            COMMON BASE UNITS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant WAD = 1e18;

    /*///////////////////////////////////////////////////////////////
                         FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function wadMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(x == 0 || (x * y) / x == y)
            if iszero(or(iszero(x), eq(div(z, x), y))) { revert(0, 0) }

            z := div(z, WAD)
        }
    }

    function wadDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            // Store x * WAD in z for now.
            z := mul(x, WAD)

            // Equivalent to require(y != 0 && (x == 0 || (x * WAD) / x == WAD))
            if iszero(and(iszero(iszero(y)), or(iszero(x), eq(div(z, x), WAD)))) { revert(0, 0) }

            // We ensure y is not zero above, so there is never division by zero here.
            z := div(z, y)
        }
    }

    /// @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result
    /// @dev See https://2π.com/21/muldiv
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            if (denominator == 0) {
                revert DivideByZero();
            }
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        if (denominator <= prod1) {
            if (denominator == 0) {
                revert DivideByZero();
            }
            revert Overflow();
        }
    }
}
