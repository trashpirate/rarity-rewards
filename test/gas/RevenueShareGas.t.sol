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

contract RevenueShareTest is Test {
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
    string[5] TRAITS = ["GREEN", "BLUE", "YELLOW", "RED", "PURPLE"];

    mapping(uint256 period => RevenueShare.ClaimPeriod) public s_period;

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
        deployer = new DeployRevenueShare();
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
                              GAS TEST CHECKS
    //////////////////////////////////////////////////////////////*/

    function _updateStatus(RevenueShare.ClaimPeriod memory period) private returns (RevenueShare.Status) {
        if (period.endTime > 0 && period.endTime < block.timestamp) {
            s_period[period.id].status = RevenueShare.Status.EXPIRED;
        }
        return period.status;
    }

    function _isExpired(RevenueShare.ClaimPeriod memory period) private returns (bool) {
        return _updateStatus(period) == RevenueShare.Status.EXPIRED;
    }

    function _isActive(uint256 periodId) private view returns (bool) {
        return s_period[periodId].status == RevenueShare.Status.ACTIVE;
    }

    function test__Gas__IsExpired() public hasDeposits {
        // vm.warp(block.timestamp + 31 days); // expired
        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        uint256 gasLeft = gasleft();
        _isExpired(period);
        console.log("_isExpired: ", gasLeft - gasleft());
        // Gas: 262 / expired: 22463
    }

    function test__Gas__UpdateState() public hasDeposits {
        // vm.warp(block.timestamp + 31 days); // expired
        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        uint256 gasLeft = gasleft();
        _updateStatus(period);
        console.log("_updateState: ", gasLeft - gasleft());
        // Gas: 191 (if expired: 22392)
    }

    function test__Gas__IsActive() public hasDeposits {
        // vm.warp(block.timestamp + 31 days); // expired
        // RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        // reading period.id instead of hardcoded 0 consumes 9 gas
        uint256 gasLeft = gasleft();
        _isActive(0);
        console.log("_isActive: ", gasLeft - gasleft());
        // Gas: 2324
    }
}
