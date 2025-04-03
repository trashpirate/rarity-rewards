// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouterMock, FunctionsResponse} from "test/mocks/FunctionsRouterMock.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";
import {DeployRarityRewards} from "script/DeployRarityRewards.s.sol";
import {RarityRewards} from "src/RarityRewards.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC721AMock} from "@erc721a/contracts/mocks/ERC721AMock.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RarityRewardsTest is Test {
    // configurations
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;

    // contracts
    DeployRarityRewards deployer;
    RarityRewards consumer;
    FunctionsRouter router;
    ERC721AMock collection;
    MockERC20 token;

    // helpers
    uint256 constant STARTING_BALANCE = 100_000 ether;
    uint256 constant STARTING_DEPOSIT = 1000 ether;
    address USER = makeAddr("user");
    string[5] TRAITS = ["GREEN", "BLUE", "YELLOW", "RED", "PURPLE"];

    modifier onlyAnvil() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    modifier hasDeposits() {
        address owner = consumer.owner();
        vm.startPrank(owner);
        token.approve(address(consumer), STARTING_DEPOSIT);
        consumer.deposit(0, address(token), STARTING_DEPOSIT, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();
        _;
    }

    function fulfilled(bytes memory response) internal {
        if (block.chainid == 31337) {
            (FunctionsResponse.FulfillResult resultCode,) = FunctionsRouterMock(address(router)).fulfill(response);
            assertEq(uint256(resultCode), 0);
            console.log("Request Mock fulfilled.");
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() external virtual {
        deployer = new DeployRarityRewards();
        (consumer, helperConfig) = deployer.run();

        networkConfig = helperConfig.getActiveNetworkConfig();

        router = FunctionsRouter(networkConfig.functionsRouter);
        collection = ERC721AMock(networkConfig.collection);

        collection.mint(USER, 100);

        token = new MockERC20("Mock Token", "MTK", 18);
        token.mint(consumer.owner(), STARTING_BALANCE);
        token.mint(USER, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                               TEST CLAIM
    //////////////////////////////////////////////////////////////*/
    function test__Fuzz__Claim(uint256 seed) public onlyAnvil hasDeposits {
        seed = bound(seed, 0, 4);
        bytes memory response = bytes(TRAITS[seed]);
        uint256 balanceBefore = token.balanceOf(USER);

        vm.prank(USER);
        consumer.claim(0, 1);

        fulfilled(response);

        uint256 balanceAfter = token.balanceOf(USER);
        uint256 claimed = balanceAfter - balanceBefore;
        console.log("User claimed: ", claimed);

        // rewards calculation -> response == YELLOW
        uint256 expectedReward = STARTING_DEPOSIT / TRAITS.length / consumer.getTraitSize(TRAITS[seed]);
        assertEq(claimed, expectedReward);
    }
}
