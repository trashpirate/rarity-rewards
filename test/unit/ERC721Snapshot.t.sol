// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouterMock, FunctionsResponse} from "test/mocks/FunctionsRouterMock.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";
import {DeployRevenueShare} from "script/DeployRevenueShare.s.sol";
import {RevenueShare} from "src/RevenueShare.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC721AMock} from "@erc721a/contracts/mocks/ERC721AMock.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Snapshot} from "src/ERC721Snapshot.sol";

contract ERC721SnapshotTest is Test {
    // configurations
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;

    // contracts
    DeployRevenueShare deployer;
    RevenueShare consumer;
    FunctionsRouter router;
    ERC721AMock collection;
    MockERC20 token;

    // helpers
    uint256 constant STARTING_BALANCE = 100_000 ether;
    uint256 constant STARTING_DEPOSIT = 1000 ether;
    address USER = makeAddr("user");
    // bytes response = "YELLOW";

    modifier onlyAnvil() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() external virtual {
        deployer = new DeployRevenueShare();
        (consumer, helperConfig) = deployer.run();

        networkConfig = helperConfig.getActiveNetworkConfig();

        router = FunctionsRouter(networkConfig.functionsRouter);
        collection = ERC721AMock(networkConfig.collection);

        collection.mint(USER, 100);
        collection.mint(address(this), 900);

        token = new MockERC20("Mock Token", "MTK", 18);
        token.mint(consumer.owner(), STARTING_BALANCE);
        token.mint(USER, STARTING_BALANCE);
    }

    function test__Update() external {
        ERC721Snapshot snapshot = new ERC721Snapshot(address(collection));

        uint256 gasLeft = gasleft();
        snapshot.getSnapshot(USER);
        uint256 gasUsed = gasLeft - gasleft();
        console.log("Gas used for update: %d", gasUsed);
    }
}
