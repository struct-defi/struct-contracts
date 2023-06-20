// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/**
 * @title Errors library [Inspired from AAVE ;)]
 * @notice Defines the error messages emitted by the different contracts of the Struct Finance protocol
 * @dev Error messages prefix glossary:
 *  - VE = Validation Error
 *  - PFE = Price feed Error
 *  - AE = Address Error
 *  - PE = Path Error
 *  - ACE = Access Control Error
 *
 * @author Struct Finance
 */
library Errors {
    string public constant AE_NATIVE_TOKEN = "1";
    /// "Invalid native token address"
    string public constant AE_REWARD1 = "2";
    /// "Invalid Reward 1 token address"
    string public constant AE_REWARD2 = "3";
    /// "Invalid Reward 2 token address"
    string public constant AE_ROUTER = "4";
    /// "Invalid Router token address"
    string public constant PE_SR_TO_JR_1 = "5";
    /// "Invalid Senior token address in Senior to Junior Path"
    string public constant PE_SR_TO_JR_2 = "6";
    /// "Invalid Junior token address in Senior to Junior Path"
    string public constant PE_JR_TO_SR_1 = "7";
    /// "Invalid Junior token address in Junior to Senior Path"
    string public constant PE_JR_TO_SR_2 = "8";
    /// "Invalid Senior token address in Junior to Junior Path"
    string public constant PE_NATIVE_TO_SR_1 = "9";
    /// "Invalid Native token address in Native to Senior Path"
    string public constant PE_NATIVE_TO_SR_2 = "10";
    /// "Invalid Senior token address in Native to Senior Path"
    string public constant PE_NATIVE_TO_JR_1 = "11";
    /// "Invalid Native token address in Native to Junior Path"
    string public constant PE_NATIVE_TO_JR_2 = "12"; //// "Invalid Junior token address in Native to Junior Path"
    string public constant PE_REWARD1_TO_NATIVE_1 = "13";
    /// "Invalid Reward1 token address in Reward1 to Native Path"
    string public constant PE_REWARD1_TO_NATIVE_2 = "14";
    /// "Invalid Native token address in Reward1 to Native Path"
    string public constant PE_REWARD2_TO_NATIVE_1 = "15";
    /// "Invalid Reward2 token address in Reward2 to Native Path"
    string public constant PE_REWARD2_TO_NATIVE_2 = "16";
    /// "Invalid Native token address in Reward2 to Native Path"
    string public constant VE_DEPOSITS_CLOSED = "17"; // `Deposits are closed`
    string public constant VE_DEPOSITS_NOT_STARTED = "18"; // `Deposits are not started yet`
    string public constant VE_AMOUNT_EXCEEDS_CAP = "19"; // `Trying to deposit more than the max capacity of the tranche`
    string public constant VE_INSUFFICIENT_BAL = "20"; // `Insufficient token balance`
    string public constant VE_INSUFFICIENT_ALLOWANCE = "21"; // `Insufficent token allowance`
    string public constant VE_INVALID_STATE = "22";
    /// "Invalid current state for the operation"
    string public constant VE_TRANCHE_NOT_STARTED = "23";
    /// "Tranche is not started yet to add LP"
    string public constant VE_NOT_MATURED = "24";
    /// "Tranche is not matured for removing liquidity from LP"
    string public constant PFE_INVALID_SR_PRICE = "25";
    /// "Senior tranche token price fluctuation is higher or the price is invalid"
    string public constant PFE_INVALID_JR_PRICE = "26";
    /// "Junior tranche token price fluctuation is higher or the price is invalid"
    string public constant VE_ALREADY_CLAIMED = "27";
    /// "Already claimed the excess tokens"
    string public constant VE_NO_EXCESS = "28";
    /// "No excess tokens to claim"
    string public constant ACE_INVALID_ACCESS = "29";
    /// "The caller is not allowed"
    string public constant ACE_HASH_MISMATCH = "30";
    /// "Role string and role do not match"
    string public constant ACE_GLOBAL_PAUSED = "31";
    /// "Interactions paused - protocol-level"
    string public constant ACE_LOCAL_PAUSED = "32";
    /// "Interactions paused - contract-level"
    string public constant ACE_INITIALIZER = "33";
    /// "Contract is initialized more than once"
    string public constant VE_ALREADY_WITHDRAWN = "34";
    /// "User has already withdrawn funds from the tranche"
    string public constant VE_CANNOT_WITHDRAW_YET = "35";
    /// "Cannot withdraw less than 3 weeks from tranche end time"
    string public constant VE_INVALID_LENGTH = "36";
    /// "Invalid swap path length"
    string public constant VE_NOT_CLAIMED_YET = "37";
    /// "The excess are not claimed to withdraw from tranche"
    string public constant VE_NO_FARM = "38";
    /// "There is no farm for the yield farming"

    string public constant VE_INVALID_ALLOCATION = "100";

    /// "Allocation cannot be zero"
    string public constant VE_INVALID_DISTRIBUTION_TOKEN = "101";
    /// "Invalid Struct token distribution amount"
    string public constant VE_DISTRIBUTION_NOT_STARTED = "103";
    /// "Distribution not started"
    string public constant VE_INVALID_INDEX = "105";
    /// "Invalid index"
    string public constant VE_NO_RECIPIENTS = "106";
    /// "Must have recipients to distribute to"
    string public constant VE_INVALID_REWARD_RATE = "107";
    /// "Reward rate too high"
    string public constant AE_ZERO_ADDRESS = "108";
    /// "Address cannot be a zero address"
    string public constant VE_NO_WITHDRAW_OR_EXCESS = "109";
    /// User must have an excess and/or withdrawal to claim
    string public constant VE_INVALID_DISTRIBUTION_FEE = "110";
    /// "Invalid native token distribution amount"

    string public constant VE_INVALID_TRANCHE_CAP = "200";

    /// "Invalid min capacity for the given tranche"
    string public constant VE_INVALID_STATUS = "202";
    /// "Invalid status arg. The status should be either 1 or 2"
    string public constant VE_INVALID_POOL = "203";
    /// "Pool doesn't exist"
    string public constant VE_TRANCHE_CAPS_EXCEEDS_DEVIATION = "204";
    /// "Tranche caps exceed MAX_DEVIATION"
    string public constant VE_TOKEN_INACTIVE = "205";
    /// "Token is not active"
    string public constant VE_EXCEEDS_TRANCHE_MAXCAP = "206";
    /// "Given tranche capacity is more than the allowed max cap"
    string public constant VE_BELOW_TRANCHE_MINCAP = "207";
    ///  "Given tranche capacity is less than the allowed min cap"
    string public constant VE_INVALID_RATE = "209";
    ///  "Fixed rate is more than the threshold or equal to zero"
    string public constant VE_INVALID_DEPOSIT_START_TIME = "210";
    ///  "Deposit start time is not a future timestamp"
    string public constant VE_INVALID_TRANCHE_START_TIME = "211";
    ///  "Tranche start time is not greater than the deposit start time"
    string public constant VE_INVALID_TRANCHE_END_TIME = "212";
    ///  "Tranche end time is not greater than the tranche start time"
    string public constant VE_INVALID_TRANCHE_DURATION = "213";
    ///  "Tranche duration is not greater than the minimum duration specified"
    string public constant VE_INVALID_LEV_MIN = "214";
    ///  "Invalid Leverage threshold min"
    string public constant VE_INVALID_LEV_MAX = "215";
    ///  "Invalid Leverage threshold max"
    string public constant VE_INVALID_FARM = "217";
    ///  "Invalid Farm (PoolId)"
    string public constant VE_INVALID_SLIPPAGE = "218";
    ///  "Slippage exceeds limit"
    string public constant VE_LEV_MAX_GT_LEV_MIN = "219";
    ///  "Invalid leverage threshold limits (levMax must be > levMax)"
    string public constant VE_INVALID_TRANSFER_AMOUNT = "220";
    ///  "Amount received is less than mentioned"
    string public constant VE_MIN_DEPOSIT_VALUE = "221";
    ///  "Minimum deposit value is not > 0 and < trancheCapacityUSD"
    string public constant VE_INVALID_YS_INPUTS = "222";
    ///  "Length of LP tokens array and yield sources array are not the same"
    string public constant VE_INVALID_INPUT_AMOUNT = "223";
    /// "Input amount is not equal to msg.value"
    string public constant VE_INVALID_TOKEN = "224";
    /// "Token cannot be zero address"
    string public constant VE_INVALID_YS_ADDRESS = "225";
    ///  "LP token and yield source cannot be zero addresses"
    string public constant VE_INVALID_ZERO_ADDRESS = "226"; // New address cannot be set to zero address
    string public constant VE_INVALID_ZERO_VALUE = "227"; // New value cannot be set to zero
    string public constant VE_INVALID_LEV_THRESH_MAX = "228"; // New leverageThresholdMaxCap value cannot be greater than leverageThresholdMinCap
    string public constant VE_INVALID_LEV_THRESH_MIN = "229"; // // New leverageThresholdMinCap value cannot be less than leverageThresholdMaxCap
    string public constant AVAX_TRANSFER_FAILED = "230";
    /// "Failed to transfer AVAX"
    string public constant VE_YIELD_SOURCE_ALREADY_SET = "231";
    /// "Yield source already set on Factory"
    string public constant VE_INVALID_TRANCHE_DURATION_MAX = "232";
    ///  "Tranche duration max is lesser than tranche duration min"
    string public constant VE_INVALID_NATIVE_TOKEN_DEPOSIT = "233";
    /// "Native token deposit is not allowed for non-wAVAX tranches"
    string public constant VE_INVALID_TRANCHE_DURATION_MIN = "234";
    ///  "Tranche duration min is greater than tranche duration max"
}
