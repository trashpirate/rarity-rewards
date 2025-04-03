// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract DeployMockERC20 is Script {
    function run() external returns (MockERC20, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (,,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        MockERC20 token = new MockERC20("MyToken", "MTK", 18);

        vm.stopBroadcast();

        return (token, helperConfig);
    }
}
