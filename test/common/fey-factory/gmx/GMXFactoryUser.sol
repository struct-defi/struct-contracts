// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../../fey-products/IFEYProductHarness.sol";
import "./IFEYFactoryHarness.sol";
import "@external/IWETH9.sol";
import "@core/libraries/types/DataTypes.sol";

import "@interfaces/IGAC.sol";

import "@mocks/ERC1155ReceiverMock.sol";

/**
 * @title GMX factory User contract
 * @notice User contract to interact with FEYGMX Factory Contract.
 *
 */
contract GMXFactoryUser is ERC1155Holder {
    IFEYFactoryHarness public feyFactory;
    IFEYProductHarness public feyProduct;

    constructor(address _feyFactory) {
        feyFactory = IFEYFactoryHarness(_feyFactory);
    }

    function setFEYProduct(address _feyProduct) external {
        feyProduct = IFEYProductHarness(_feyProduct);
    }

    function getTrancheInfo(DataTypes.Tranche _tranche) external view returns (DataTypes.TrancheInfo memory) {
        return feyProduct.getTrancheInfo(_tranche);
    }

    function getInvestorDetails(DataTypes.Tranche _tranche) external view returns (DataTypes.Investor memory) {
        return feyProduct.getInvestorDetails(_tranche, address(this));
    }

    function tokenDecimals() external view returns (uint256 _srDecimals, uint256 _jrDecimals) {
        return feyProduct.tokenDecimals();
    }

    function trancheConfig(DataTypes.Tranche _tranche) external view returns (DataTypes.TrancheConfig memory) {
        return feyProduct.getTrancheConfig(_tranche);
    }

    function getProductConfig() external view returns (DataTypes.ProductConfig memory) {
        return feyProduct.getProductConfig();
    }

    function increaseAllowance(address _token, uint256 _amount) external {
        IERC20Metadata(_token).approve(address(feyFactory), _amount);
    }

    function setApprovalForAll(IERC1155 _token, address _operator) external {
        IERC1155(_token).setApprovalForAll(_operator, true);
    }

    function getFirstProduct() external view returns (address) {
        return feyFactory.getFirstProduct();
    }

    function setPerformanceFee(uint256 _performanceFee) external {
        feyFactory.setPerformanceFee(_performanceFee);
    }

    function setManagementFee(uint256 _managementFee) external {
        feyFactory.setManagementFee(_managementFee);
    }

    function setLeverageThresholdMinCap(uint256 _levThresholdMin) external {
        feyFactory.setLeverageThresholdMinCap(_levThresholdMin);
    }

    function setLeverageThresholdMaxCap(uint256 _levThresholdMax) external {
        feyFactory.setLeverageThresholdMaxCap(_levThresholdMax);
    }

    function setMinimumTrancheDuration(uint256 _trancheDurationMin) external {
        feyFactory.setMinimumTrancheDuration(_trancheDurationMin);
    }

    function setMaximumTrancheDuration(uint256 _trancheDurationMax) external {
        feyFactory.setMaximumTrancheDuration(_trancheDurationMax);
    }

    function setTrancheCapacity(uint256 _trancheCapUSD) external {
        feyFactory.setTrancheCapacity(_trancheCapUSD);
    }

    function setPoolStatus(address _token0, address _token1) external {
        feyFactory.setPoolStatus(_token0, _token1, 1);
    }

    function setFEYProductImplementation(address _feyProductImpl) external {
        feyFactory.setFEYProductImplementation(_feyProductImpl);
    }

    function setStructPriceOracle(IStructPriceOracle _structPriceOracle) external {
        feyFactory.setStructPriceOracle(_structPriceOracle);
    }

    function setMinimumDepositValueUSD(uint256 _newValue) external {
        feyFactory.setMinimumDepositValueUSD(_newValue);
    }

    function setYieldSource(address _yieldSource) external {
        feyFactory.setYieldSource(_yieldSource);
    }

    function getMaxFixedRate() external view returns (uint256 maxFixedRate) {
        maxFixedRate = feyFactory.maxFixedRate();
    }

    function setMaxFixedRate(uint256 _fixedRateMax) external {
        feyFactory.setMaxFixedRate(_fixedRateMax);
    }

    function productTokenId(uint256 _spTokenId) external view returns (address productAddress) {
        return feyFactory.productTokenId(_spTokenId);
    }

    function trancheCapacityUSD() external view returns (uint256) {
        return feyFactory.trancheCapacityUSD();
    }

    function setTokenStatus(address _token, uint256 _status) external {
        feyFactory.setTokenStatus(_token, _status);
    }

    function constructProductParams(address _tokenSenior, address _tokenJunior)
        external
        view
        returns (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfigUserInput
        )
    {
        return _constructProductParams(_tokenSenior, _tokenJunior);
    }

    function _constructProductParams(address _tokenSenior, address _tokenJunior)
        internal
        view
        returns (
            DataTypes.TrancheConfig memory trancheConfigSenior,
            DataTypes.TrancheConfig memory trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory productConfigUserInput
        )
    {
        trancheConfigSenior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(payable(_tokenSenior)),
            decimals: 18,
            spTokenId: 0,
            capacity: 2000000e18
        });

        trancheConfigJunior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(_tokenJunior),
            decimals: 6,
            spTokenId: 1,
            capacity: 2000000e18
        });

        productConfigUserInput = DataTypes.ProductConfigUserInput({
            fixedRate: 5000,
            startTimeTranche: block.timestamp + 1000 hours,
            endTimeTranche: block.timestamp + 2000 hours,
            leverageThresholdMin: feyFactory.leverageThresholdMinCap(),
            leverageThresholdMax: feyFactory.leverageThresholdMaxCap()
        });
    }

    function createProductAndDeposit(
        address _tokenSenior,
        address _tokenJunior,
        DataTypes.Tranche _tranche,
        uint256 _initialDepositAmount
    ) external {
        (
            DataTypes.TrancheConfig memory _trancheConfigSenior,
            DataTypes.TrancheConfig memory _trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory _productConfigUserInput
        ) = _constructProductParams(_tokenSenior, _tokenJunior);

        feyFactory.createProduct(
            _trancheConfigSenior, _trancheConfigJunior, _productConfigUserInput, _tranche, _initialDepositAmount
        );
    }

    function createProductAndDepositAVAX(
        address _tokenSenior,
        address _tokenJunior,
        DataTypes.Tranche _tranche,
        uint256 _initialDepositAmount,
        uint256 _avaxValue
    ) external {
        (
            DataTypes.TrancheConfig memory _trancheConfigSenior,
            DataTypes.TrancheConfig memory _trancheConfigJunior,
            DataTypes.ProductConfigUserInput memory _productConfigUserInput
        ) = _constructProductParams(_tokenSenior, _tokenJunior);

        feyFactory.createProduct{value: _avaxValue}(
            _trancheConfigSenior, _trancheConfigJunior, _productConfigUserInput, _tranche, _initialDepositAmount
        );
    }

    function createProductAndDepositAVAXCustom(
        DataTypes.TrancheConfig memory _trancheConfigSenior,
        DataTypes.TrancheConfig memory _trancheConfigJunior,
        DataTypes.ProductConfigUserInput memory _productConfigUserInput,
        DataTypes.Tranche _tranche,
        uint256 _initialDepositAmount,
        uint256 _avaxValue
    ) external {
        feyFactory.createProduct{value: _avaxValue}(
            _trancheConfigSenior, _trancheConfigJunior, _productConfigUserInput, _tranche, _initialDepositAmount
        );
    }

    function localPause() external {
        IGAC(address(feyFactory)).pause();
    }

    function localUnpause() external {
        IGAC(address(feyFactory)).unpause();
    }

    function globalPause() external {
        (, bytes memory data) = address(feyFactory).call(abi.encodeWithSignature("gac()"));
        address gacAddress = abi.decode(data, (address));
        IGAC(gacAddress).pause();
    }

    function globalUnpause() external {
        (, bytes memory data) = address(feyFactory).call(abi.encodeWithSignature("gac()"));
        address gacAddress = abi.decode(data, (address));
        IGAC(gacAddress).unpause();
    }
}
