// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@mocks/MockERC20.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IStructPriceOracle.sol";
import "@interfaces/IFEYFactory.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";

import "../../../common/fey-factory/gmx/FEYFactoryBaseTestSetup.sol";

contract FGMXFCreateProductTest is FEYFactoryBaseTestSetup {
    uint256 internal initialDepositAmount = 100e18;
    uint256 internal avaxValue = 100e18;
    uint256 private usdcValueDecimalsScalingFactor = 10 ** 12;

    event Deposited(
        DataTypes.Tranche _tranche,
        uint256 _trancheDepositedAmount,
        address indexed _user,
        uint256 _trancheDepositedTotal
    );

    event PoolStatusUpdated(address indexed lpAddress, uint256 status, address indexed tokenA, address indexed tokenB);

    event ProductCreated(
        address indexed productAddress,
        uint256 fixedRate,
        uint256 startTimeDeposit,
        uint256 startTimeTranche,
        uint256 endTimeTranche
    );

    function onSetup() public virtual override {
        factoryTestsFixture();
        sut.setMinimumDepositValueUSD(100e18);
    }

    function testCreateProduct_ERC20_EmitDeposited() public {
        console.log("Deposited event should be emitted if user deposits wrapped AVAX from Factory contract");
        setupFactoryState();
        deal(address(wavax), address(user1), initialDepositAmount);
        user1.increaseAllowance(address(wavax), initialDepositAmount);
        vm.expectEmit(true, false, false, false);
        emit Deposited(SENIOR_TRANCHE, initialDepositAmount, address(user1), initialDepositAmount);
        user1.createProductAndDeposit(address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_ERC20_RevertInsufficientAllowance() public {
        console.log("ID: Fa_CP_49");
        console.log("deposit wrapped AVAX to Senior tranche");
        console.log("should revert when the creator doesn`t have sufficient allowance for initial deposit");
        setupFactoryState();
        deal(address(wavax), address(user1), initialDepositAmount);

        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed"));
        user1.createProductAndDeposit(address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_ERC20_RevertInsufficientBalance() public {
        console.log("ID: Fa_CP_50");
        console.log("deposit wrapped AVAX to Senior tranche");
        console.log("should revert when the creator doesn`t have sufficient balance for initial deposit");
        setupFactoryState();
        uint256 userBalance = 1e2;
        deal(address(wavax), address(user1), userBalance);
        user1.increaseAllowance(address(wavax), initialDepositAmount);

        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed"));
        user1.createProductAndDeposit(address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_EmitDeposited() public {
        console.log("deposit AVAX to Senior tranche");
        console.log("Deposited event should be emitted if user deposits AVAX from Factory contract");
        setupFactoryState();
        deal(address(user1), initialDepositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposited(SENIOR_TRANCHE, initialDepositAmount, address(user1), initialDepositAmount);
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_InvestorDepositedNative() public {
        console.log("deposit AVAX to Senior tranche");
        console.log("investor.depositedNative should be true if user deposits AVAX from Factory contract");
        setupFactoryState();
        deal(address(user1), initialDepositAmount);

        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
        address newProduct = user1.getFirstProduct();
        user1.setFEYProduct(newProduct);
        DataTypes.Investor memory investor1 = user1.getInvestorDetails(SENIOR_TRANCHE);
        assertEq(investor1.depositedNative, true);
    }

    function testCreateProduct_RevertInvalidDepositAmountUnder() public {
        console.log("ID: Fa_CP_51");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_INPUT_AMOUNT if msg.value < initialDepositAmount when depositing AVAX"
        );
        setupFactoryState();
        deal(address(user1), initialDepositAmount);
        avaxValue = 1e2;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_INPUT_AMOUNT));
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidDepositAmountOver() public {
        console.log("ID: Fa_CP_52");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_INPUT_AMOUNT if msg.value > initialDepositAmount when depositing AVAX"
        );
        setupFactoryState();
        avaxValue = 1000e18;
        deal(address(user1), avaxValue);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_INPUT_AMOUNT));
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testFailCreateProduct_RevertInvalidTrancheDeposit() public {
        console.log("ID: Fa_CP_43");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with generic error if invalid value passed to _tranche param");
        setupFactoryState();
        deal(address(user1), initialDepositAmount);

        uint8 INVALID_TRANCHE = 3;
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), DataTypes.Tranche(INVALID_TRANCHE), initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertWhenLocalPaused() public {
        console.log("ID: Fa_CP_54");

        console.log("should revert when the contract is paused locally");
        setupFactoryState();
        deal(address(user1), initialDepositAmount);
        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_RevertWhenGlobalPaused() public {
        console.log("ID: Fa_CP_55");
        console.log("should revert when the contract is paused globally");

        setupFactoryState();
        deal(address(user1), initialDepositAmount);

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Fa_CP_56");

        console.log("should revert with a different error message when the contract is unpaused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_POOL));
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Fa_CP_57");

        console.log("should revert with a different error message when the contract is unpaused globally");

        pauser.globalPause();
        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_POOL));
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_Success_SufficientDeposit_UserNotWhitelisted() public {
        console.log("ID: Fa_CP_44");
        console.log("USDC Deposit to Junior tranche");
        console.log("should succeed if non-whitelisted user deposits amount over minimumInitialDepositUSD");
        uint256 _minimumInitialDepositUSD = sut.minimumInitialDepositUSD();
        // divide minDepositAmountUSD by token price, multiply by 10 ^ token decimals to get wei val, add 1 so it's over min
        uint256 _depositAmount =
            (_minimumInitialDepositUSD / PRICE_USDC) * 10 ** IERC20Metadata(address(usdc)).decimals() + 1;

        deal(address(usdc), address(user3), _depositAmount);
        user3.increaseAllowance(address(usdc), _depositAmount);
        setupFactoryState();

        user3.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, _depositAmount);
        address newProduct = user1.getFirstProduct();
        user3.setFEYProduct(newProduct);
        DataTypes.TrancheInfo memory _trancheInfoJunior = user3.getTrancheInfo(JUNIOR_TRANCHE);
        assertEq(_trancheInfoJunior.tokensDeposited, (_depositAmount * usdcValueDecimalsScalingFactor));
    }

    function testCreateProduct_Success_NoDeposit_UserWhitelisted() public {
        console.log("ID: Fa_CP_45");
        console.log("do not deposit to Junior tranche");
        console.log("should succeed if user does not deposit any tokens but is whitelisted");
        initialDepositAmount = 0;
        setupFactoryState();

        uint256 fixedRate = 5000;
        uint256 startTimeDeposit = 1;
        uint256 startTimeTranche = block.timestamp + 1000 hours;
        console.log(startTimeTranche);
        uint256 endTimeTranche = block.timestamp + 2000 hours;
        console.log(endTimeTranche);
        vm.expectEmit(false, false, false, true);
        // first arg is product address, but we don't have it until after
        // we call createProduct, so we use a zero address and it passes because
        // productAddress is indexed as a topic, but we are only checking for data
        emit ProductCreated(address(0), fixedRate, startTimeDeposit, startTimeTranche, endTimeTranche);
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);
        address newProduct = user1.getFirstProduct();
        user1.setFEYProduct(newProduct);
        DataTypes.TrancheInfo memory _trancheInfoJunior = user1.getTrancheInfo(JUNIOR_TRANCHE);
        assertEq(_trancheInfoJunior.tokensDeposited, 0);
    }

    function testCreateProduct_RevertInvalidAccess() public {
        console.log("ID: Fa_CP_46");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error ACE_INVALID_ACCESS if user is not whitelisted and initialDepositAmount less than minimumInitialDepositUSD"
        );
        initialDepositAmount = 1e18;
        avaxValue = 1e18;
        setupFactoryState();
        deal(address(user3), initialDepositAmount);

        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user3.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertAmountExceedsCap_Senior() public {
        console.log("ID: Fa_CP_47");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_AMOUNT_EXCEEDS_CAP if initialDepositAmount is more than minimumDepositValue and more than the capacity of the tranche"
        );
        uint256 _trancheCapacityUSD = user1.trancheCapacityUSD();
        initialDepositAmount = _trancheCapacityUSD + 1;
        avaxValue = initialDepositAmount;
        setupFactoryState();
        deal(address(user1), initialDepositAmount);

        vm.expectRevert(abi.encodePacked(Errors.VE_AMOUNT_EXCEEDS_CAP));
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertAmountExceedsCapJunior() public {
        console.log("ID: Fa_CP_48");
        console.log("deposit USDC to Junior tranche");
        console.log(
            "should revert with error VE_AMOUNT_EXCEEDS_CAP if initialDepositAmount is more than minimumDepositValue and more than the capacity of the tranche"
        );
        uint256 _trancheCapacityUSD = user1.trancheCapacityUSD();
        initialDepositAmount = _trancheCapacityUSD + 1;
        setupFactoryState();
        deal(address(usdc), address(user1), initialDepositAmount);
        user1.increaseAllowance(address(usdc), initialDepositAmount);

        vm.expectRevert(abi.encodePacked(Errors.VE_AMOUNT_EXCEEDS_CAP));
        user1.createProductAndDeposit(address(wavax), address(usdc), JUNIOR_TRANCHE, initialDepositAmount);
    }

    function testCreateProduct_RevertTokenInactive_Senior() public {
        console.log("ID: Fa_CP_3");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with error VE_TOKEN_INACTIVE if Senior token is not whitelisted");
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(true));
        sut.setPoolStatus(address(wavax), address(usdc), 1);
        sut.setTokenStatus(address(usdc), 1);
        deal(address(user1), initialDepositAmount);

        vm.expectRevert(abi.encodePacked(Errors.VE_TOKEN_INACTIVE));
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertTokenInactive_Junior() public {
        console.log("ID: Fa_CP_4");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with error VE_TOKEN_INACTIVE if Junior token is not whitelisted");
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(true));
        sut.setPoolStatus(address(wavax), address(usdc), 1);
        sut.setTokenStatus(address(wavax), 1);
        deal(address(user1), initialDepositAmount);

        vm.expectRevert(abi.encodePacked(Errors.VE_TOKEN_INACTIVE));
        user1.createProductAndDepositAVAX(
            address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_Success_Override_Tranche_TokenDecimals() public {
        console.log("ID: Fa_CP_7");
        console.log("ID: Fa_CP_8");
        console.log("deposit AVAX to Senior tranche");
        console.log("should successfully override incorrect _configTrancheSr decimals.");
        console.log("should successfully override incorrect _configTrancheJr decimals.");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        trancheConfigSenior.decimals = 1;
        trancheConfigJunior.decimals = 1;
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
        address newProduct = user1.getFirstProduct();
        user1.setFEYProduct(newProduct);
        (uint256 _srDecimals, uint256 _jrDecimals) = user1.tokenDecimals();
        assertEq(_srDecimals, IERC20Metadata(address(wavax)).decimals(), "seniorTokenDecimals");
        assertEq(_jrDecimals, IERC20Metadata(usdc).decimals(), "juniorTokenDecimals");
    }

    function testCreateProduct_Success_Override_Tranche_SPTokenId() public {
        console.log("ID: Fa_CP_9");
        console.log("ID: Fa_CP_10");
        console.log("deposit AVAX to Senior tranche");
        console.log("should successfully override incorrect _configTrancheSr spTokenId.");
        console.log("should successfully override incorrect _configTrancheJr spTokenId.");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        trancheConfigSenior.spTokenId = 10000;
        trancheConfigJunior.spTokenId = 10000;
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
        address newProduct = user1.getFirstProduct();
        user1.setFEYProduct(newProduct);
        // latestSpTokenId starts at zero, then increments to 1 for jr tranche and 2 for senior tranche
        uint256 expectedSpTokenIdJr = 1;
        uint256 expectedSpTokenIdSr = 2;
        address _product1 = user1.productTokenId(expectedSpTokenIdSr);
        address _product2 = user1.productTokenId(expectedSpTokenIdJr);
        assertEq(_product1, newProduct);
        assertEq(_product2, newProduct);
    }

    function testCreateProduct_Success_Override_Tranche_Capacity() public {
        console.log("ID: Fa_CP_11");
        console.log("ID: Fa_CP_12");
        console.log("deposit AVAX to Senior tranche");
        console.log("should successfully override incorrect _configTrancheSr capacity.");
        console.log("should successfully override incorrect _configTrancheJr capacity.");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        trancheConfigSenior.capacity = 1;
        trancheConfigJunior.capacity = 1;
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );

        address newProduct = user1.getFirstProduct();
        user1.setFEYProduct(newProduct);

        uint256 trancheCapacity = user1.trancheCapacityUSD();
        uint256 tokenCapacityExpectedSr = trancheCapacity / PRICE_WAVAX;
        uint256 tokenCapacityExpectedJr = trancheCapacity / PRICE_USDC;

        DataTypes.TrancheConfig memory trancheConfigSr = user1.trancheConfig(SENIOR_TRANCHE);
        DataTypes.TrancheConfig memory trancheConfigJr = user1.trancheConfig(JUNIOR_TRANCHE);

        uint256 tokenDecimals = 10 ** 18;

        uint256 tokenCapacityActualSr = trancheConfigSr.capacity / tokenDecimals;
        uint256 tokenCapacityActualJr = trancheConfigJr.capacity / tokenDecimals;

        assertEq(tokenCapacityActualSr, tokenCapacityExpectedSr);
        assertEq(tokenCapacityActualJr, tokenCapacityExpectedJr);
    }

    function testCreateProduct_RevertInvalidRate_Zero() public {
        console.log("ID: Fa_CP_15");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with error VE_INVALID_RATE if fixedRate is zero");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        productConfig.fixedRate = 0; // 0%

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_RATE));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidRate_Over() public {
        console.log("ID: Fa_CP_16");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with error VE_INVALID_RATE if fixedRate is above 75%");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        productConfig.fixedRate = 1e6; // 100%

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_RATE));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_Success_UnderNewMaxFixedRate() public {
        console.log("ID: Fa_CP_17");
        console.log("deposit AVAX to Senior tranche");
        console.log("should succeed when maxFixedRate is adjusted to 900000, _productConfig fixedRate input is 800000");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        uint256 _newFixedRateMax = 9e5; // 90%
        admin.setMaxFixedRate(_newFixedRateMax);
        productConfig.fixedRate = 8e5; // 80%

        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
        address newProduct = user1.getFirstProduct();
        user1.setFEYProduct(newProduct);
        DataTypes.ProductConfig memory _productConfig = user1.getProductConfig();
        assertEq(_productConfig.fixedRate, productConfig.fixedRate);
    }

    function testCreateProduct_Revert_OverNewMaxFixedRate() public {
        console.log("ID: Fa_CP_18");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with VE_INVALID_RATE when maxFixedRate is adjusted to 900000, _productConfig fixedRate input is 950000"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        uint256 _newFixedRateMax = 9e5; // 90%
        admin.setMaxFixedRate(_newFixedRateMax);
        productConfig.fixedRate = 95e4; // 95%

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_RATE));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidTrancheStartTime() public {
        console.log("ID: Fa_CP_23");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_TRANCHE_START_TIME if startTimeTranche is less than or equal to startTimeDeposit"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // startTimeTranche is before startTimeDeposit
        productConfig.startTimeTranche = 1;
        productConfig.endTimeTranche = block.timestamp + 2000 hours;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_START_TIME));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidTrancheEndTime() public {
        console.log("ID: Fa_CP_22");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with error VE_INVALID_TRANCHE_END_TIME if endTimeTranche is before startTimeTranche");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // startTimeTranche is after endTimeTranche
        productConfig.startTimeTranche = block.timestamp + 2000 hours;
        productConfig.endTimeTranche = block.timestamp;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_END_TIME));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidTrancheStartTime_UnderBlockTimeStamp() public {
        console.log("ID: Fa_CP_23");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_TRANCHE_START_TIME if startTimeTranche is before block timestamp"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // startTimeTranche is before block.timestamp
        productConfig.startTimeTranche = 1;
        productConfig.endTimeTranche = block.timestamp;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_START_TIME));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidTrancheEndTime_UnderBlockTimeStamp() public {
        console.log("ID: Fa_CP_24");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with error VE_INVALID_TRANCHE_END_TIME if endTimeTranche is before block timestamp");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        productConfig.startTimeTranche = block.timestamp + 1000 hours;
        // endTimeTranche is before block.timestamp
        productConfig.endTimeTranche = 1;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_END_TIME));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidTrancheDuration_Max() public {
        console.log("ID: Fa_CP_25");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_TRANCHE_DURATION if time between startTimeTranche and endTimeTranche is greater than trancheDurationMax"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // trancheDurationMax currently set to 200 * 24 * 60 * 60; (~6.5 months)
        // tranche duration is 20,000 hours (~27 months)
        productConfig.startTimeTranche = block.timestamp + 1 hours;
        productConfig.endTimeTranche = block.timestamp + 20001 hours;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_DURATION));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_Success_IncreaseTrancheDurationMax() public {
        console.log("ID: Fa_CP_26");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "trancheDurationMax is updated to be 400 days. _productConfig endTimeTranche input is greater than startTimeTranche by 300 days"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();
        uint256 _newMaxTrancheDuration = 400 days;
        admin.setMaximumTrancheDuration(_newMaxTrancheDuration);

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        productConfig.startTimeTranche = block.timestamp + 1 minutes;
        uint256 endTimeTranche = block.timestamp + 300 days + 1 minutes;
        productConfig.endTimeTranche = endTimeTranche;

        vm.expectEmit(true, true, true, true);
        emit Deposited(SENIOR_TRANCHE, initialDepositAmount, address(user1), initialDepositAmount);
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidTrancheDuration_Min() public {
        console.log("ID: Fa_CP_27");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_TRANCHE_DURATION if time between startTimeTranche and endTimeTranche is less than trancheDurationMin"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));

        uint256 trancheDuration = sut.trancheDurationMin();
        productConfig.startTimeTranche = block.timestamp + trancheDuration - 1;
        productConfig.endTimeTranche = block.timestamp + trancheDuration;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_DURATION));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_Success_DecreaseTrancheDurationMin() public {
        console.log("ID: Fa_CP_28");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "trancheDurationMin is updated to be 1 day. _productConfig endTimeTranche input is greater than startTimeTranche by 3 days"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();
        uint256 _newMinTrancheDuration = 1 days;
        admin.setMinimumTrancheDuration(_newMinTrancheDuration);

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        productConfig.startTimeTranche = block.timestamp + 1 minutes;
        uint256 endTimeTranche = block.timestamp + 3 days + 1 minutes;
        productConfig.endTimeTranche = endTimeTranche;

        vm.expectEmit(true, true, true, true);
        emit Deposited(SENIOR_TRANCHE, initialDepositAmount, address(user1), initialDepositAmount);
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidLeverageThresholds() public {
        console.log("ID: Fa_CP_29");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_LEV_MAX_GT_LEV_MIN if the leverageThresholdMax is greater than the leverageThresholdMin"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // thresholds are flipped
        productConfig.leverageThresholdMin = 750000;
        productConfig.leverageThresholdMax = 1250000;

        vm.expectRevert(abi.encodePacked(Errors.VE_LEV_MAX_GT_LEV_MIN));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidLeverageThresholdMin() public {
        console.log("ID: Fa_CP_30");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_LEV_MIN if the leverageThresholdMin is greater than the leverageThresholdMinCap"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // leverageThresholdMinCap currently set to 1500000 (150%)
        productConfig.leverageThresholdMin = 1500001;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_LEV_MIN));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidLeverageThresholdMin_AdjustedLeverageThresholdMinCap() public {
        console.log("ID: Fa_CP_31");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_LEV_MIN if the leverageThresholdMinCap is set to 1250000 and is greater than the leverageThresholdMin"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // leverageThresholdMin set to 1250000 (125%)
        uint256 newMinCap = 1250000;
        admin.setLeverageThresholdMinCap(newMinCap);
        productConfig.leverageThresholdMin = 1400001;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_LEV_MIN));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidLeverageThresholdMax() public {
        console.log("ID: Fa_CP_32");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_LEV_MAX if the leverageThresholdMax is less than the leverageThresholdMaxCap"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // leverageThresholdMaxCap currently set to 500000 (50%)
        productConfig.leverageThresholdMax = 490000;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_LEV_MAX));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInvalidLeverageThresholdMax_AdjustedLeverageThresholdMaxCap() public {
        console.log("ID: Fa_CP_33");
        console.log("deposit AVAX to Senior tranche");
        console.log(
            "should revert with error VE_INVALID_LEV_MAX if the leverageThresholdMaxCap is set to 900000 and is less than the leverageThresholdMax"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        // leverageThresholdMax set to 900000 (90%)
        uint256 newMaxCap = 900000;
        admin.setLeverageThresholdMaxCap(newMaxCap);
        productConfig.leverageThresholdMax = 800000;

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_LEV_MAX));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_Success_EqualLeverageThresholdMinMax() public {
        console.log("ID: Fa_CP_34");
        console.log("deposit AVAX to Senior tranche");
        console.log("should succeed if leverageThresholdMin and leverageThresholdMax are equal");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();

        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));

        productConfig.leverageThresholdMin = 1000000;
        productConfig.leverageThresholdMax = 1000000;
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, SENIOR_TRANCHE, initialDepositAmount, avaxValue
        );
        address newProduct = user1.getFirstProduct();
        user1.setFEYProduct(newProduct);
        DataTypes.ProductConfig memory _productConfig = user1.getProductConfig();
        assertEq(_productConfig.leverageThresholdMax, _productConfig.leverageThresholdMin);
    }

    function testCreateProduct_ERC20_SetFEYGMXProductInfoOnYS() public {
        console.log("ID: GMX_Fa_CP_1");
        console.log("deposit wrapped AVAX to Senior tranche");
        console.log("Yield Source contract's productInfo mapping contains details of the new product");
        setupFactoryState();
        deal(address(wavax), address(user1), initialDepositAmount);
        user1.increaseAllowance(address(wavax), initialDepositAmount);
        user1.createProductAndDeposit(address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount);
        address newProduct = user1.getFirstProduct();
        DataTypes.FEYGMXProductInfo memory _productInfo = yieldSource.getFEYGMXProductInfo(newProduct);
        assertEq(_productInfo.tokenA, address(wavax));
        assertEq(_productInfo.tokenADecimals, IERC20Metadata(address(wavax)).decimals());
        assertEq(_productInfo.tokenB, address(usdc));
        assertEq(_productInfo.tokenBDecimals, IERC20Metadata(address(usdc)).decimals());
        assertEq(_productInfo.fsGLPReceived, 0);
        assertEq(_productInfo.shares, 0);
    }

    function testCreateProduct_ERC20_SameTokenForBothTranches() public {
        console.log("ID: GMX_Fa_CP_2");
        console.log("deposit wrapped AVAX to Senior tranche");
        console.log("Creates a product with the same whitelisted token for both tranches");
        setupFactoryState();
        sut.setPoolStatus(address(wavax), address(wavax), 1);
        deal(address(wavax), address(user1), initialDepositAmount);
        user1.increaseAllowance(address(wavax), initialDepositAmount);
        user1.createProductAndDeposit(address(wavax), address(wavax), SENIOR_TRANCHE, initialDepositAmount);
        address newProduct = user1.getFirstProduct();
        DataTypes.FEYGMXProductInfo memory _productInfo = yieldSource.getFEYGMXProductInfo(newProduct);
        assertEq(_productInfo.tokenA, address(wavax));
        assertEq(_productInfo.tokenADecimals, IERC20Metadata(address(wavax)).decimals());
        assertEq(_productInfo.tokenB, address(wavax));
        assertEq(_productInfo.tokenBDecimals, IERC20Metadata(address(wavax)).decimals());
        assertEq(_productInfo.fsGLPReceived, 0);
        assertEq(_productInfo.shares, 0);
    }

    function testCreateProduct_DepositAVAX_RevertInvalidNativeTokenDeposit() public {
        console.log("ID: Fa_CP_35");
        console.log("deposit AVAX to Junior tranche (USDC)");
        console.log(
            "should revert with error VE_INVALID_NATIVE_TOKEN_DEPOSIT if user attempts to deposit AVAX into non-wAVAX tranche"
        );
        deal(address(user1), initialDepositAmount);
        setupFactoryState();
        (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfig
        ) = user1.constructProductParams(address(wavax), address(usdc));
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_NATIVE_TOKEN_DEPOSIT));
        user1.createProductAndDepositAVAXCustom(
            trancheConfigSenior, trancheConfigJunior, productConfig, JUNIOR_TRANCHE, initialDepositAmount, avaxValue
        );
    }

    function testCreateProduct_RevertInactivePool() public {
        console.log("ID: Fa_CP_36");
        console.log("deposit AVAX to Senior tranche");
        console.log("should revert with error VE_INVALID_POOL if the pool is inactive");
        deal(address(user1), initialDepositAmount);
        setupFactoryState();
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(true));
        sut.setPoolStatus(address(wavax), address(usdc), 2);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_POOL));
        user1.createProductAndDeposit(address(wavax), address(usdc), SENIOR_TRANCHE, initialDepositAmount);
    }
}
