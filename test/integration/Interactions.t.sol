// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
// import {FunctionsRouterMock} from "test/mocks/FunctionsRouterMock.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";

import {RevenueShare} from "src/RevenueShare.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Claim} from "script/Interactions.s.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract SubscriptionsTest is Test {
    // configurations
    HelperConfig helperConfig;

    // helpers
    address collection;
    address functionsRouter;
    address link;
    bytes32 donID;
    uint64 subscriptionId;
    uint256 deployerKey;

    function setUp() external virtual {
        helperConfig = new HelperConfig();
        (collection, functionsRouter, link, donID,, deployerKey) = helperConfig.activeNetworkConfig();
    }

    function test__Integration_Claim() public {
        address client = DevOpsTools.get_most_recent_deployment("RevenueShare", block.chainid);

        Claim claim = new Claim();
        claim.claim(client, deployerKey);

        FunctionsRouter.Consumer memory consumer = FunctionsRouter(functionsRouter).getConsumer(client, subscriptionId);
        assertEq(consumer.initiatedRequests, 1);
    }
}
