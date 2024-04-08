// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ILupaEngine} from "./interfaces/ILupaEngine.sol";
import {LupaStablecoin} from "./LupaStablecoin.sol";

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "../lib/forge-std/src/console.sol";

/**
 * @title DSCEngine
 * @author fabriziogianni7
 * @custom:interface see ILupaEngine.sol
 * the "engine" of our token
 * it is necessary to keep 1 token = 1$ value
 * backed of WETH and WBTC
 * handle logic to mint and reedem the stable coin
 * This is an ERC20 goverded by our DSCEngine contract
 * our dsc should be always overcollateralized
 * our dsc system should always be overcollateralized. at no point the value of collateral should be <= the dollars backed value of our dsc
 */
contract LupaEngine is ILupaEngine, Ownable, ReentrancyGuard {
    ////////////////////////////////////
    ////////// ERRORS ///////////////
    ////////////////////////////////////
    error LupaEngine__AmountMustBeMoreThanZero();
    error LupaEngine__PriceFeedAndTokensAreNotTheSameLength();
    error LupaEngine__TokenNotAllowed();
    error LupaEngine__DepositFailed();
    error LupaEngine__HealthFactorIsTooLow(uint256 ratio, address _user);
    error LupaEngine__MintFailed();
    error LupaEngine__TransferFailed();
    error LupaEngine__NotEnoughCollateral();
    error LupaEngine__HealthFactorOk(uint256 healthFactor);

    ////////////////////////////////////
    ////////// STATE VARIABLES /////////
    ////////////////////////////////////
    LupaStablecoin private immutable i_lupaStablecoin;
    uint256 private constant HEALTH_FACTOR = 150;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // 200% overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; // 200% overcollateralized

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateral;
    mapping(address user => uint256 amountLupaMinted) s_LupaMintedByUser;
    address[] private s_allowedCollateraltokens;

    ////////////////////////////////////
    ////////// EVENTS ///////////////
    ////////////////////////////////////
    event Deposited(address indexed user, address indexed token, uint256 indexed amount);
    event LupaMinted(address indexed to, uint256 indexed amount);
    event LupaBurned(address indexed tokenMinter, address indexed burnerUser, uint256 indexed amount);
    event Redeemed(address indexed user, address indexed _token, uint256 _amount);
    event TokenAdded(address indexed token);
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        address indexed collateralToken,
        uint256 totalCollateral,
        uint256 amount
    );

    ////////////////////////////////////
    ////////// MODIFIERS ///////////////
    ////////////////////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) revert LupaEngine__AmountMustBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert LupaEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////////////////
    ////////// FUNCTIONS ///////////////
    ////////////////////////////////////
    constructor(address _lupaStablecoinAddress, address[] memory _tokens, address[] memory _priceFeeds)
        Ownable(msg.sender)
    {
        if (_tokens.length != _priceFeeds.length) {
            revert LupaEngine__PriceFeedAndTokensAreNotTheSameLength();
        }

        i_lupaStablecoin = LupaStablecoin(_lupaStablecoinAddress);

        for (uint256 i = 0; i < _tokens.length; i++) {
            s_priceFeeds[_tokens[i]] = _priceFeeds[i];
        }
        s_allowedCollateraltokens = _tokens;
    }

    ////////////////////////////////////
    ////////// EXTERNAL FUNCTIONS //////
    ////////////////////////////////////

    function addAllowedTokens(address _token) external onlyOwner {
        if (_token == address(0)) revert LupaEngine__TokenNotAllowed();
        s_allowedCollateraltokens.push(_token);
        emit TokenAdded(_token);
    }

    /// @notice see ILupaEngine.sol
    function depositCollateralAndMintLupa(
        address _collateralTokenAddress,
        uint256 _collateralAmount,
        uint256 _mintAmount
    ) external {
        depositCollateral(_collateralTokenAddress, _collateralAmount);
        mintLupa(_mintAmount);
    }

    /**
     * @notice burn Lupa and get collateral back to the user
     */
    function redeemCollateralForLupa(address _token, uint256 _lupaAmount, uint256 _collateralAmount)
        external
        moreThanZero(_lupaAmount)
        moreThanZero(_collateralAmount)
        isAllowedToken(_token)
        nonReentrant
    {
        _burnLupa(msg.sender, msg.sender, _lupaAmount);
        _redeemCollateral(_token, _collateralAmount, msg.sender);
    }

    /**
     * @notice if any user healtfactor is low, anyone can call this to liquidate him
     * @notice who call this function should receive user collateral and burn his tokens - someone need to call redeem and burn for you
     * @notice if someone is ALMOST undercollateralized, the protocol pays who call this function
     * @notice anuyone can call this function and liquidate the amount of Lupa they want, but if the health factor does not improve, this function revert
     */
    function liquidateUser(address _user, address _collateralToken, uint256 _amountInWei) external {
        uint256 healthFactor = _calculateHealthFactor(_user);
        if (healthFactor >= MIN_HEALTH_FACTOR) revert LupaEngine__HealthFactorOk(healthFactor);

        // calculate amount of collateral to liquidate to the msg.sender + bonus
        uint256 amountOfCollateralToRedeem = _getTokenAmountFromUSD(_collateralToken, _amountInWei);

        // calculate bonus to liquidator
        uint256 bonus = (amountOfCollateralToRedeem * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        // liquidate
        _burnLupa(msg.sender, _user, _amountInWei);
        _redeemCollateral(_collateralToken, amountOfCollateralToRedeem + bonus, _user);
        emit Liquidated(msg.sender, _user, _collateralToken, amountOfCollateralToRedeem + bonus, _amountInWei);
    }

    ////////////////////////////////////
    /////// PUBLIC FUNCTIONS ///////////
    ////////////////////////////////////

    /**
     * @notice get the collateral back to the user
     * @notice decrease the collateral in the corresponding mapping
     * @notice transfer collateral to user
     * @notice need to consequentially burn tokens otherwise the user risks to decreaase the health factor
     * @notice should emit a redeemed event
     */
    function redeemCollateral(address _token, uint256 _amount)
        public
        moreThanZero(_amount)
        isAllowedToken(_token)
        nonReentrant
    {
        _redeemCollateral(_token, _amount, msg.sender);
    }

    /**
     * @notice burn lupa on behalf of user
     * @notice decrease the total amount of tokens per user
     * @notice transfer tokens from user to this contract
     * @notice  this contract will later call burn
     * @notice  _tokenOwner can be different than _burnerUser
     */
    function burnLupa(uint256 _amount) public moreThanZero(_amount) nonReentrant {
        _burnLupa(msg.sender, msg.sender, _amount);
    }

    /**
     * @notice see ILupaEngine.sol
     * @notice follow CEI pattern
     */
    function depositCollateral(address _collateralTokenAddress, uint256 _amount)
        public
        nonReentrant
        moreThanZero(_amount)
        isAllowedToken(_collateralTokenAddress)
    {
        s_userCollateral[msg.sender][_collateralTokenAddress] += _amount;

        bool success = IERC20(_collateralTokenAddress).transferFrom(msg.sender, address(this), _amount);
        if (!success) revert LupaEngine__DepositFailed();
        emit Deposited(msg.sender, _collateralTokenAddress, _amount);
    }

    /// @notice see ILupaEngine.sol
    // check if collateral value > DSC amount
    function mintLupa(uint256 _amount) public nonReentrant moreThanZero(_amount) {
        s_LupaMintedByUser[msg.sender] += _amount;
        // if they minted too much comparing to the deposited collateral, should revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_lupaStablecoin.mint(msg.sender, _amount);
        if (!success) revert LupaEngine__MintFailed();
        emit LupaMinted(msg.sender, _amount);
    }

    ////////////////////////////////////
    //// PRIVATE/ INTERNAL FUNCTIONS ///
    ////////////////////////////////////
    /**
     * @notice return how close to liquidation a user is
     * check health factor (do they have enought colalteral) revert if they have too low collateral
     * if user goes below 1, they can get liquidated
     * @param _user the user we want to calculate the hf for
     */
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 healthFactor = _calculateHealthFactor(_user);
        if (healthFactor < MIN_HEALTH_FACTOR) revert LupaEngine__HealthFactorIsTooLow(healthFactor, _user);
    }

    /**
     *
     * @dev return how close to liquidation a user is
     * if user goes below 1, they can get liquidated
     * @param _user the user we want to calculate the hf for
     *   @custom:examples
     *     collateralAdjustedForThreshold:
     *         total collateral value * Liquidation threshold / 100
     *         eg
     *         100$ * 50 / 100 = 50$
     *
     *     hf:
     *         collateralAdjustedForThreshold * PRECISION / totalLupaMinted
     *         eg (say I have minted 50 LP)
     *         50 * 1e18 / 50 = 1e18 --> hf is ok!
     *         eg (say I have minted 50LP for 90$ of ETH)
     *         collateralAdjustedForThreshold = 90$ * 50/100 = 45$
     *         hf= 45 * 1e18 / 50 = 45000000000000000000/50 = 9e17 --> hf is low!
     */
    function _calculateHealthFactor(address _user) internal view returns (uint256 ratio) {
        (uint256 totalLunaMinted, uint256 totalCollateralValueDeposited) =
            _getUserTotalLupaMintedAndTotalCollateralValue(_user);
        //edge case: if the user has no collateral left, this function fails...
        if (totalLunaMinted == 0) {
            return MIN_HEALTH_FACTOR;
        }

        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueDeposited * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        uint256 hf = ((collateralAdjustedForThreshold) / (totalLunaMinted / PRECISION));
        return hf;
    }

    /**
     * @notice get the total number of Lupa minted and the total value in USD of collateral for a specific user
     * @param _user the user we want to calculate the value for
     */
    function _getUserTotalLupaMintedAndTotalCollateralValue(address _user)
        internal
        view
        returns (uint256 totalLunaMinted, uint256 totalCollateralValueDeposited)
    {
        totalLunaMinted = s_LupaMintedByUser[_user];
        totalCollateralValueDeposited = getTotalValueOfCollaterInUSDByUser(_user);
    }

    /**
     * @notice get collateral back to the user
     * @notice who burn can also be a 3rd party
     * @notice if the redeemer withdraw too much he can go with a low health factor
     * @param _token the token to withdraw
     * @param _amount amount to burn
     */
    function _redeemCollateral(address _token, uint256 _amount, address _from) internal {
        if (s_userCollateral[_from][_token] < _amount) revert LupaEngine__NotEnoughCollateral();
        s_userCollateral[_from][_token] -= _amount;
        bool success = IERC20(_token).transfer(msg.sender, _amount);
        if (!success) revert LupaEngine__TransferFailed();

        _revertIfHealthFactorIsBroken(_from);
        emit Redeemed(msg.sender, _token, _amount);
    }

    /**
     * @notice burn lupa
     * @notice who burn can also be a 3rd party
     * @param _burnerUser who burn the tokens
     * @param _tokenMinter who minted the tokens
     * @param _amount amount to burn
     */
    function _burnLupa(address _burnerUser, address _tokenMinter, uint256 _amount) private {
        s_LupaMintedByUser[_tokenMinter] -= _amount;

        bool success = i_lupaStablecoin.transferFrom(_burnerUser, address(this), _amount);
        if (!success) revert LupaEngine__TransferFailed();

        i_lupaStablecoin.burn(_amount);
        emit LupaBurned(_tokenMinter, _burnerUser, _amount);
    }

    function _getValueOfSingleTokenCollateral(address _token, uint256 _amount)
        private
        view
        returns (uint256 totalValue)
    {
        uint256 price = _getUsdValueOfToken(_token);
        totalValue = price * _amount;
        return totalValue;
    }

    function _getUsdValueOfToken(address _token) private view returns (uint256 usdValue) {
        address priceFeedAddress = s_priceFeeds[_token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        usdValue = ((uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
        return usdValue;
    }

    function _getTokenAmountFromUSD(address _token, uint256 _usdAmount) private view returns (uint256) {
        address priceFeedAddress = s_priceFeeds[_token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // usdAmount need to be in wei
        uint256 collateralAmount = ((_usdAmount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));

        // 1500e18 /2000e18

        /**
         * 1500 * 1e18 / 2000e8 * 1e10 = 1500 / 2000 = 0.0...
         */
        return collateralAmount;
    }

    ////////////////////////////////////
    ////////// GETTERS FUNCTIONS //////
    ////////////////////////////////////

    function getTotalValueOfCollaterInUSDByUser(address _user) public view returns (uint256 value) {
        // loop tru array of tokens
        // sum up value
        address[] memory allTokens = s_allowedCollateraltokens;
        value = 0;
        for (uint256 i = 0; i < allTokens.length; i++) {
            uint256 tokenAmunt = s_userCollateral[_user][allTokens[i]];
            if (tokenAmunt > 0) {
                value += _getValueOfSingleTokenCollateral(allTokens[i], tokenAmunt);
            }
        }
        return value;
    }

    function getLupaAddress() external view returns (address lupa) {
        lupa = address(i_lupaStablecoin);
    }

    /// @notice see ILupaEngine.sol
    function getHealtFactor(address _user) external view returns (uint256) {
        return _calculateHealthFactor(_user);
    }

    function getUsdValueOfToken(address _token) external view returns (uint256) {
        return _getUsdValueOfToken(_token);
    }

    function getUserTotalLupaMintedAndTotalCollateralValue(address _user)
        external
        view
        returns (uint256 totalLunaMinted, uint256 totalCollateralValueDeposited)
    {
        return _getUserTotalLupaMintedAndTotalCollateralValue(_user);
    }

    function getLupaStablecoin() external view returns (LupaStablecoin) {
        return i_lupaStablecoin;
    }

    function getHealthFactor() external pure returns (uint256) {
        return HEALTH_FACTOR;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getUserCollateral(address user, address token) external view returns (uint256) {
        return s_userCollateral[user][token];
    }

    function getLupaMintedByUser(address user) external view returns (uint256) {
        return s_LupaMintedByUser[user];
    }

    function getAllowedCollateralTokens() external view returns (address[] memory) {
        return s_allowedCollateraltokens;
    }
}
