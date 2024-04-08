// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;
// this handler narrow down the way we call functions

import {Test, console} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";

import {LupaStablecoin} from "../../src/LupaStablecoin.sol";
import {LupaEngine} from "../../src/LupaEngine.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {CustomMockAggregatorV3} from "../../script/mocks/CustomMockAggregatorV3.sol";

contract StopOnRevertHandler is Test {
    LupaStablecoin lupa;
    LupaEngine lupaEngine;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    CustomMockAggregatorV3 public wethFeed;
    CustomMockAggregatorV3 public wbtcFeed;

    // Ghost Variables - maximum token supply
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(
        LupaStablecoin _lupa,
        LupaEngine _lupaEngine,
        ERC20Mock _weth,
        ERC20Mock _wbtc,
        CustomMockAggregatorV3 _wethFeed,
        CustomMockAggregatorV3 _wbtcFeed
    ) {
        lupa = _lupa;
        lupaEngine = _lupaEngine;
        weth = _weth;
        wbtc = _wbtc;
        wethFeed = _wethFeed;
        wbtcFeed = _wbtcFeed;
    }

    function canAlwaysDepositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(lupaEngine), amountCollateral);
        lupaEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // to to redeem collateral
        // max amount any user has
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxAmountCollateral = lupaEngine.getUserCollateral(msg.sender, address(collateral));

        // try to withdraw that collateral
        amountCollateral = bound(amountCollateral, 0, maxAmountCollateral);
        vm.assume(amountCollateral > 0);

        vm.prank(msg.sender);
        lupaEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function depositCollateralAndMintLupa(uint256 collateralSeed, uint256 amountCollateral, uint256 lupaAmountToMint)
        public
    {
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);
        lupaAmountToMint = bound(lupaAmountToMint, 1e18, MAX_DEPOSIT_SIZE);
        vm.assume(amountCollateral >= 2 && lupaAmountToMint > 0);
        vm.assume(lupaAmountToMint == 2 && lupaAmountToMint > 0);

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 collValue = lupaEngine.getUsdValueOfToken(address(collateral));
        vm.assume(lupaAmountToMint <= (collValue * 10) / 2);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(lupaEngine), amountCollateral);

        lupaEngine.depositCollateralAndMintLupa(address(collateral), amountCollateral, lupaAmountToMint);
        vm.stopPrank();
    }

    /// Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
