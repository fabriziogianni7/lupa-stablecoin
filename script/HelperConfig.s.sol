// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {LupaStablecoin} from "../src/LupaStablecoin.sol";
import {NetworkConfig} from "./structs/Config.sol";
import {Script, console} from "lib/forge-std/src/Script.sol";
import {CustomMockAggregatorV3} from "./mocks/CustomMockAggregatorV3.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
// lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/MockAggregator.sol

contract HelperConfig is Script {
    NetworkConfig private activeNetworkConfig;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getLocalConfig();
        }
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory config) {
        address[] memory tokens = new address[](2);
        tokens[1] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063; //wbtc
        tokens[0] = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81; // weth

        address[] memory priceFeeds = new address[](2);
        priceFeeds[1] = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43; // BTC/USD (8 decimals!)
        priceFeeds[0] = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD (8 decimals!)
        string memory selector = "SEPOLIA_PK";
        config = NetworkConfig({tokensAllowed: tokens, priceFeeds: priceFeeds, pkSelector: selector});
    }

    function getLocalConfig() public returns (NetworkConfig memory config) {
        vm.startBroadcast();
        ERC20Mock wethMock = new ERC20Mock();
        ERC20Mock wbtcMock = new ERC20Mock();
        address[] memory tokens = new address[](2);
        tokens[0] = address(wethMock);
        tokens[1] = address(wbtcMock);

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = address(new CustomMockAggregatorV3(3000e18));
        priceFeeds[1] = address(new CustomMockAggregatorV3(60000e18));
        string memory selector = "ANVIL_PK";
        vm.stopBroadcast();
        config = NetworkConfig({tokensAllowed: tokens, priceFeeds: priceFeeds, pkSelector: selector});
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
