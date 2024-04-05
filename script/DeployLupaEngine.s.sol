// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LupaEngine} from "../src/LupaEngine.sol";
import {LupaStablecoin} from "../src/LupaStablecoin.sol";
import {NetworkConfig} from "./structs/Config.sol";

contract DeployLupaEngine is Script {
    function run() public returns (LupaEngine, LupaStablecoin, NetworkConfig memory) {
        HelperConfig helperConfig = new HelperConfig();
        NetworkConfig memory activeNetworkConfig = helperConfig.getConfig();

        uint256 deployerPrivateKey = vm.envUint(activeNetworkConfig.pkSelector);

        vm.startBroadcast(deployerPrivateKey);

        LupaStablecoin lupaStablecoin = new LupaStablecoin();

        LupaEngine lupaEngine =
            new LupaEngine(address(lupaStablecoin), activeNetworkConfig.tokensAllowed, activeNetworkConfig.priceFeeds);
        lupaStablecoin.transferOwnership(address(lupaEngine));
        vm.stopBroadcast();

        return (lupaEngine, lupaStablecoin, activeNetworkConfig);
    }
}
