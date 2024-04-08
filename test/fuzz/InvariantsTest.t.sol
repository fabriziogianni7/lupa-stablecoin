// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// this contract has all the invariants - the properties of the system that should always hold

// what are our inveriants?

// 1. the total supply of Lupa should be always less than total value of collateral
// 2. getter view functions should never revert

import {Test, console} from "lib/forge-std/src/Test.sol";

import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {DeployLupaEngine} from "../../script/DeployLupaEngine.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {CustomMockAggregatorV3} from "../../script/mocks/CustomMockAggregatorV3.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {NetworkConfig} from "../../script/structs/Config.sol";
import {LupaStablecoin} from "../../src/LupaStablecoin.sol";
import {LupaEngine} from "../../src/LupaEngine.sol";
import {StopOnRevertHandler} from "./StopOnRevertHandler.sol";

contract InvariantsTest is StdInvariant, Test {
    NetworkConfig public activeNetworkConfig;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    CustomMockAggregatorV3 public wethFeed;
    CustomMockAggregatorV3 public wbtcFeed;
    LupaStablecoin public lupaStablecoin;
    LupaEngine public lupaEngine;
    StopOnRevertHandler public handler;

    function setUp() public {
        DeployLupaEngine deployLupaEngine = new DeployLupaEngine();
        (lupaEngine, lupaStablecoin, activeNetworkConfig) = deployLupaEngine.run();

        weth = ERC20Mock(activeNetworkConfig.tokensAllowed[0]);
        wbtc = ERC20Mock(activeNetworkConfig.tokensAllowed[1]);
        // weth.mint(TEST_USER, STARTING_USER_BALANCE);
        // wbtc.mint(TEST_USER, STARTING_USER_BALANCE);

        wethFeed = CustomMockAggregatorV3(activeNetworkConfig.priceFeeds[0]);
        wbtcFeed = CustomMockAggregatorV3(activeNetworkConfig.priceFeeds[1]);

        handler = new StopOnRevertHandler(lupaStablecoin, lupaEngine, weth, wbtc, wethFeed, wbtcFeed);
        targetContract(address(handler));
    }

    //invariant:
    // 1. the total supply of Lupa should be always less than total value of collateral

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    /// forge-config: default.invariant.call-override = false
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get val of collateral of protocol and compare it to DSC
        // total supply of Lupa are always  < than TVL in LupaEngine
        uint256 totalSupply = lupaStablecoin.totalSupply();

        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(lupaEngine));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(lupaEngine));

        uint256 totalWethValue = lupaEngine.getUsdValueOfToken(address(weth)) * wethDeposted;
        uint256 totalWbtcValue = lupaEngine.getUsdValueOfToken(address(wbtc)) * wbtcDeposited;

        uint256 tvl = totalWethValue + totalWbtcValue;

        console.log("totalSupply: %s", totalSupply);
        console.log("wethValue: %s", totalWethValue);
        console.log("wbtcValue: %s", totalWbtcValue);
        console.log("tvl: %s", tvl);

        assert(totalSupply <= tvl);
    }
}
