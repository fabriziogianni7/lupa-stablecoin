// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title DSCEngine
 * @author fabriziogianni7
 * the "engine" of our token
 * it is necessary to keep 1 token = 1$ value
 * backed of WETH and WBTC
 * handle logic to mint and reedem the stable coin
 * This is an ERC20 goverded by our DSCEngine contract
 * our dsc should be always overcollateralized
 * our dsc system should always be overcollateralized. at no point the value of collateral should be <= the dollars backed value of our dsc
 */
interface ILupaEngine {
    /**
     * @notice allow users to deposit some collateral and get some Lupa
     * @dev need to be able to determine how much collateral is needed to mint 1 Lupa
     */
    function depositCollateralAndMintLupa(
        address _collateralTokenAddress,
        uint256 _collateralAmount,
        uint256 _mintAmount
    ) external;

    /**
     * @notice allow to get back the deposited collateral in exchange for Lupa
     */
    function redeemCollateralForLupa(address _token, uint256 _lupaAmount, uint256 _collateralAmount) external;

    /**
     * @notice allow other users to liquidate users who have a low health factor
     */
    function liquidateUser(address _user, address _collateralToken, uint256 _amount) external;

    /**
     * @notice get the health factor
     */
    function getHealtFactor(address _user) external view returns (uint256);

    /**
     * @notice allow to burn lupa
     */
    function addAllowedTokens(address _token) external;
}
