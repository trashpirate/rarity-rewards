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
    // bytes response = "YELLOW";

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
            uint256 gasLeft = gasleft();
            (FunctionsResponse.FulfillResult resultCode,) = FunctionsRouterMock(address(router)).fulfill(response);
            console.log("Request Mock fulfilled with gas: ", gasLeft - gasleft());
            assertEq(uint256(resultCode), 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event RequestRevertedWithErrorMsg(string reason);
    event RequestRevertedWithoutErrorMsg(bytes data);
    event Withdrawal(address indexed token, uint256 indexed periodId, uint256 indexed amount);
    event Deposit(address indexed token, uint256 indexed periodId, uint256 indexed amount);
    event Claimed(address indexed claimer, uint256 periodId, uint256 amount);
    event Activated(uint256 indexed periodId);
    event Deactivated(uint256 indexed periodId);
    event ClaimTimeSet(uint256 indexed time);
    event EmergencyWithdrawal(uint256 indexed amount);

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
                            TEST DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    function test__Deployment() public view {
        assertEq(consumer.owner(), helperConfig.ANVIL_DEFAULT_ADDRESS());
        assertNotEq(consumer.getSubscriptionId(), 0);
        assertEq(consumer.getDonID(), networkConfig.donID);
        assertEq(consumer.getSource(), vm.readFile("functions-toolkit/source/code.js"));

        FunctionsRouter.Subscription memory sub =
            FunctionsRouter(networkConfig.functionsRouter).getSubscription(consumer.getSubscriptionId());
        assertEq(sub.owner, consumer.owner());
        console.log("Subscription Owner: ", sub.owner);
        console.log("Subscription Consumers:");
        for (uint256 i = 0; i < sub.consumers.length; i++) {
            console.log("%d: %s", i + 1, sub.consumers[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              TEST DEPOSIT
    //////////////////////////////////////////////////////////////*/
    // success
    function test__Deposit() public {
        address owner = consumer.owner();

        vm.startPrank(owner);
        token.approve(address(consumer), 100 ether);
        consumer.deposit(0, address(token), 100 ether, block.timestamp);
        vm.stopPrank();

        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        assertEq(period.startTime, block.timestamp);
        assertEq(period.endTime, block.timestamp + 30 days);
        assertEq(period.amount, 100 ether);
        assertEq(period.token, address(token));
        assertEq(uint256(period.status), 0);
    }

    function test__DepositUpdate() public {
        address owner = consumer.owner();

        // approve funds
        vm.prank(owner);
        token.approve(address(consumer), 200 ether);

        //  initial deposit
        uint256 initialAmount = 100 ether;
        vm.prank(owner);
        consumer.deposit(0, address(token), initialAmount, block.timestamp);

        // update period with funds and start time
        uint256 newAmount = 50 ether;
        uint256 startTime = block.timestamp + 1 days;
        vm.prank(owner);
        consumer.deposit(0, address(token), newAmount, startTime);

        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        assertEq(period.startTime, startTime);
        assertEq(period.endTime, startTime + 30 days);
        assertEq(period.amount, initialAmount + newAmount);
        assertEq(period.token, address(token));
        assertEq(uint256(period.status), 0);
    }

    // events
    function test__Emit__Deposit() public {
        address owner = consumer.owner();

        // approve funds
        vm.prank(owner);
        token.approve(address(consumer), 200 ether);

        //  initial deposit
        uint256 initialAmount = 100 ether;

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(token), 0, initialAmount);

        vm.prank(owner);
        consumer.deposit(0, address(token), initialAmount, block.timestamp);
    }

    // reverts
    function test__Revert__OnlyOwnerCanDeposit() public {
        vm.prank(USER);
        token.approve(address(consumer), 100 ether);

        vm.expectRevert("Only callable by owner");

        vm.prank(USER);
        consumer.deposit(0, address(token), 100 ether, block.timestamp);
    }

    function test__Revert__DepositWhenActive() public {
        address owner = consumer.owner();

        // approve funds
        vm.prank(owner);
        token.approve(address(consumer), 200 ether);

        //  initial deposit
        uint256 initialAmount = 100 ether;
        vm.prank(owner);
        consumer.deposit(0, address(token), initialAmount, block.timestamp);

        // activate period
        vm.prank(owner);
        consumer.activate(0);

        // update period with funds and start time
        uint256 newAmount = 50 ether;
        uint256 startTime = block.timestamp + 1 days;

        // expect revert
        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodActive.selector);

        vm.prank(owner);
        consumer.deposit(0, address(token), newAmount, startTime);
    }

    function test__Revert__DepositWhenExpired() public {
        address owner = consumer.owner();

        // approve funds
        vm.prank(owner);
        token.approve(address(consumer), 200 ether);

        //  initial deposit
        uint256 startTime = block.timestamp;
        uint256 initialAmount = 100 ether;
        vm.prank(owner);
        consumer.deposit(0, address(token), initialAmount, startTime);

        // roll time
        vm.warp(startTime + 31 days);

        // update period with funds
        uint256 newAmount = 50 ether;

        // expect revert
        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodExpired.selector);

        vm.prank(owner);
        consumer.deposit(0, address(token), newAmount, startTime);
    }

    function test__Revert__DepositWithWrongToken() public {
        address owner = consumer.owner();

        // approve funds
        vm.prank(owner);
        token.approve(address(consumer), 200 ether);

        //  initial deposit
        uint256 startTime = block.timestamp;
        uint256 initialAmount = 100 ether;
        vm.prank(owner);
        consumer.deposit(0, address(token), initialAmount, startTime);

        // update period with funds
        uint256 newAmount = 50 ether;

        // expect revert
        vm.expectRevert(RevenueShare.RevenueShare__InvalidTokenAddress.selector);

        vm.prank(owner);
        consumer.deposit(0, address(123445), newAmount, startTime);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST ACTIVATE
    //////////////////////////////////////////////////////////////*/
    function test__Activate() public {
        address owner = consumer.owner();

        vm.startPrank(owner);
        token.approve(address(consumer), STARTING_BALANCE);
        consumer.deposit(0, address(token), 100 ether, block.timestamp);
        vm.stopPrank();

        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        assertEq(uint256(period.status), 0);

        vm.prank(owner);
        consumer.activate(0);

        period = consumer.getClaimPeriod(0);
        assertEq(uint256(period.status), 1);
    }

    // events
    function test__Emit__Activated() public {
        address owner = consumer.owner();

        vm.startPrank(owner);
        token.approve(address(consumer), STARTING_BALANCE);
        consumer.deposit(0, address(token), 100 ether, block.timestamp);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Activated(0);

        vm.prank(owner);
        consumer.activate(0);
    }

    // reverts
    function test__Revert__OnlyOwnerCanActivate() public {
        address owner = consumer.owner();
        vm.startPrank(owner);
        token.approve(address(consumer), STARTING_BALANCE);
        consumer.deposit(0, address(token), 100 ether, block.timestamp);
        vm.stopPrank();

        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        assertEq(uint256(period.status), 0);

        vm.expectRevert("Only callable by owner");

        vm.prank(USER);
        consumer.activate(0);
    }

    function test__Revert__ActivateWhenActive() public {
        address owner = consumer.owner();
        vm.startPrank(owner);
        token.approve(address(consumer), STARTING_BALANCE);
        consumer.deposit(0, address(token), 100 ether, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        // expect revert
        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodActive.selector);

        vm.prank(owner);
        consumer.activate(0);
    }

    function test__Revert__ActivateWhenExpired() public {
        address owner = consumer.owner();
        vm.startPrank(owner);
        token.approve(address(consumer), STARTING_BALANCE);
        consumer.deposit(0, address(token), 100 ether, block.timestamp);
        vm.stopPrank();

        // roll time
        vm.warp(block.timestamp + 31 days);

        // expect revert
        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodExpired.selector);

        vm.prank(owner);
        consumer.activate(0);
    }

    /*//////////////////////////////////////////////////////////////
                             TEST WITHDRAW
    //////////////////////////////////////////////////////////////*/
    // success
    function test__Withdraw() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        vm.stopPrank();

        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        assertEq(period.amount, amount);

        uint256 balanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        consumer.withdraw(0);

        uint256 balanceAfter = token.balanceOf(owner);
        period = consumer.getClaimPeriod(0);

        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(period.amount, 0);
    }

    function test__WithdrawWhenExpired() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        assertEq(period.amount, amount);

        // make it expired
        vm.warp(block.timestamp + 31 days);

        uint256 balanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        consumer.withdraw(0);

        uint256 balanceAfter = token.balanceOf(owner);
        period = consumer.getClaimPeriod(0);

        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(period.amount, 0);
    }

    // events
    function test__Emit__Withdrawal() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Withdrawal(address(token), 0, amount);

        vm.prank(owner);
        consumer.withdraw(0);
    }

    // reverts
    function test__Revert__OnlyOwnerCanWithdraw() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        vm.stopPrank();

        vm.expectRevert("Only callable by owner");

        vm.prank(USER);
        consumer.withdraw(0);
    }

    function test__Revert__NothingToWithdraw() public {
        address owner = consumer.owner();
        uint256 amount = 0;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        vm.stopPrank();

        vm.expectRevert(RevenueShare.RevenueShare__NothingToWithdraw.selector);

        vm.prank(owner);
        consumer.withdraw(0);
    }

    function test__Revert__WithdrawWhenActive() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodActive.selector);

        vm.prank(owner);
        consumer.withdraw(0);
    }

    /*//////////////////////////////////////////////////////////////
                            TEST DEACTIVATE
    //////////////////////////////////////////////////////////////*/
    // success
    function test__Deactivate() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        RevenueShare.ClaimPeriod memory period = consumer.getClaimPeriod(0);
        assertEq(uint256(period.status), 1);

        vm.prank(owner);
        consumer.deactivate(0);

        period = consumer.getClaimPeriod(0);
        assertEq(uint256(period.status), 0);
    }

    // events
    function test__Emit__Deactivated() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Deactivated(0);

        vm.prank(owner);
        consumer.deactivate(0);
    }

    // reverts
    function test__Revert__DeactivateWhenInactive() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        vm.stopPrank();

        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodInactive.selector);

        vm.prank(owner);
        consumer.deactivate(0);
    }

    function test__Revert__OnlyOwnerCanDeactivate() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        vm.expectRevert("Only callable by owner");

        vm.prank(USER);
        consumer.deactivate(0);
    }

    /*//////////////////////////////////////////////////////////////
                         TEST SETCLAIMDURATION
    //////////////////////////////////////////////////////////////*/

    // success
    function test__SetClaimTime() public {
        address owner = consumer.owner();
        uint256 newDuration = 60 days;

        vm.prank(owner);
        consumer.setClaimTime(newDuration);

        assertEq(consumer.getClaimTime(), newDuration);
    }

    // events
    function test__Emit__ClaimTimeSet() public {
        address owner = consumer.owner();
        uint256 newDuration = 60 days;

        vm.expectEmit(true, true, true, true);
        emit ClaimTimeSet(newDuration);

        vm.prank(owner);
        consumer.setClaimTime(newDuration);
    }

    // reverts
    function test__Revert__OnlyOwnerCanSetClaimTime() public {
        uint256 newDuration = 60 days;

        vm.expectRevert("Only callable by owner");

        vm.prank(USER);
        consumer.setClaimTime(newDuration);
    }

    /*//////////////////////////////////////////////////////////////
                        TEST EMERGENCY WITHDRAW
    //////////////////////////////////////////////////////////////*/

    // success
    function test__EmergencyWithdraw() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        uint256 balanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        consumer.emergencyWithdraw(address(token));

        uint256 balanceAfter = token.balanceOf(owner);

        assertEq(amount, balanceAfter - balanceBefore);
    }

    // emit event
    function test__Emit__EmergencyWithdrawal() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdrawal(amount);

        vm.prank(owner);
        consumer.emergencyWithdraw(address(token));
    }

    // revert
    function test__Revert__OnlyOwnerCanEmergencyWithdraw() public {
        address owner = consumer.owner();
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(consumer), amount);
        consumer.deposit(0, address(token), amount, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        vm.expectRevert("Only callable by owner");

        vm.prank(USER);
        consumer.emergencyWithdraw(address(token));
    }

    function test__Revert__EmergencyWithdrawWhenZeroBalance() public {
        address owner = consumer.owner();

        vm.startPrank(owner);
        consumer.deposit(0, address(token), 0, block.timestamp);
        consumer.activate(0);
        vm.stopPrank();

        vm.expectRevert(RevenueShare.RevenueShare__NothingToWithdraw.selector);

        vm.prank(owner);
        consumer.emergencyWithdraw(address(token));
    }

    /*//////////////////////////////////////////////////////////////
                               TEST CLAIM
    //////////////////////////////////////////////////////////////*/

    // success
    function test__Claim() public onlyAnvil hasDeposits {
        bytes memory response = "YELLOW";
        uint256 balanceBefore = token.balanceOf(USER);

        vm.prank(USER);
        consumer.claim(0, 1);

        fulfilled(response);

        uint256 balanceAfter = token.balanceOf(USER);
        uint256 claimed = balanceAfter - balanceBefore;
        console.log("User claimed: ", claimed);

        // rewards calculation -> response == YELLOW
        // reward = 1000 ether / 5 / 80 = 2.5 ether
        assertEq(claimed, 2.5 ether);
    }

    // events
    function test__Emit__Claimed() public onlyAnvil hasDeposits {
        bytes memory response = "YELLOW";

        vm.prank(USER);
        consumer.claim(0, 1);

        // rewards calculation -> response == YELLOW
        // reward = 1000 ether / 5 / 80 = 2.5 ether

        vm.expectEmit(true, true, true, true);
        emit Claimed(USER, 0, 2.5 ether);

        fulfilled(response);
    }

    // reverts
    function test__Revert__ClaimByWrongUser() public hasDeposits {
        address wrongUser = makeAddr("wrong-user");

        vm.expectRevert(RevenueShare.RevenueShare__InvalidTokenOwner.selector);
        vm.prank(wrongUser);
        consumer.claim(0, 1);
    }

    function test__Revert__ClaimWhenClaimPending() public hasDeposits {
        vm.prank(USER);
        consumer.claim(0, 1);

        vm.expectRevert(RevenueShare.RevenueShare__ClaimPending.selector);
        vm.prank(USER);
        consumer.claim(0, 12);
    }

    function test__Revert__AlreadyClaimed() public hasDeposits {
        bytes memory response = "YELLOW";

        vm.prank(USER);
        consumer.claim(0, 1);

        fulfilled(response);

        vm.expectRevert(RevenueShare.RevenueShare__AlreadyClaimed.selector);
        vm.prank(USER);
        consumer.claim(0, 1);
    }

    function test__Revert__ClaimWhenClaimPeriodInactive() public hasDeposits {
        address owner = consumer.owner();
        vm.prank(owner);
        consumer.deactivate(0);

        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodInactive.selector);
        vm.prank(USER);
        consumer.claim(0, 1);
    }

    function test__Revert__ClaimWhenClaimPeriodExpired() public hasDeposits {
        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(RevenueShare.RevenueShare__ClaimPeriodExpired.selector);
        vm.prank(USER);
        consumer.claim(0, 1);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST GETTERS
    //////////////////////////////////////////////////////////////*/

    // success
    function test__GetTraitSize() public view {
        assertEq(consumer.getTraitSize("GREEN"), 790);
        assertEq(consumer.getTraitSize("BLUE"), 100);
        assertEq(consumer.getTraitSize("YELLOW"), 80);
        assertEq(consumer.getTraitSize("RED"), 20);
        assertEq(consumer.getTraitSize("PURPLE"), 10);
    }

    function test__GetLastResponse() public onlyAnvil hasDeposits {
        bytes memory response = "YELLOW";

        vm.prank(USER);
        consumer.claim(0, 1);

        fulfilled(response);

        assertEq(consumer.getLastResponse(), response);
    }

    function test__GetClaims() public onlyAnvil hasDeposits {
        bytes memory response = "YELLOW";

        vm.prank(USER);
        consumer.claim(0, 1);

        fulfilled(response);

        RevenueShare.Claims memory claims = consumer.getClaims(0, USER);

        assertEq(claims.numClaimed, 1);
    }

    // reverts
    function test__Revert__GetInvalidTrait() public {
        vm.expectRevert(RevenueShare.RevenueShare__InvalidTrait.selector);
        consumer.getTraitSize("GREY");
    }
}
