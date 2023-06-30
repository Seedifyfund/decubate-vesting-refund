// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {PRBTest} from "@prb/test/PRBTest.sol";
//import {console2} from "forge-std/console2.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {IGOVesting} from "src/IGOVesting.sol";
import {IIGOVesting} from "src/interfaces/IIGOVesting.sol";
import {MockToken} from "./mock/MockToken.sol";

contract IGOVestingTest is PRBTest, StdCheats {
    MockToken internal vested;
    MockToken internal payment;
    MockToken internal payment2;
    IGOVesting internal vesting;

    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal user3 = makeAddr("user3");

    function setUp() public {
        vested = new MockToken("Sale Token", "STK", 1e35);
        payment = new MockToken("Test Stable Coin ", "BUSD", 1e35);
        payment2 = new MockToken("Test Stable Coin ", "BUSD", 1e35);
        vesting = new IGOVesting();

        vested.transfer(address(vesting), 1400e18);
        payment.transfer(address(vesting), 100e18);
    }

    function setParams() internal {
        IIGOVesting.VestingSetup memory v;

        v = IIGOVesting.VestingSetup(
            uint32(block.timestamp),
            100_000,
            10_000_000,
            100
        );

        vesting.initializeCrowdfunding(
            IIGOVesting.ContractSetup(
                address(1),
                address(2),
                address(3),
                address(vested),
                50,
                1000e18,
                1 days,
                1000
            ),
            v
        );

        vesting.setCrowdfundingWhitelist(
            "testTag",
            address(this),
            100e18,
            address(payment),
            1000e18,
            10
        );
    }

    function testAddLinearVesting() external {
        setParams();
        (
            uint256 start,
            uint256 cliff,
            uint256 duration,
            uint256 initial
        ) = vesting.vestingPool();

        assertEq(cliff, block.timestamp + 100_000);
        assertEq(start, block.timestamp);
        assertEq(duration, 10_000_000);
        assertEq(initial, 100);
    }

    function testGetVestAmount() external {
        setParams();

        vm.warp(block.timestamp - 1);
        uint256 amount = vesting.getVestAmount(address(this));
        assertEq(amount, 0); //Nothing until
        vm.warp(block.timestamp + 1);
        amount = vesting.getVestAmount(address(this));
        assertEq(amount, 1000e18 / 10); //10% initial unlock
        vm.warp(block.timestamp + 300 days);
        amount = vesting.getVestAmount(address(this));
        assertEq(amount, 1000e18); //Full unlock
    }

    function testGetReleasableAmountLinear() external {
        setParams();
        vm.warp(block.timestamp + 10 days);
        uint256 amount = vesting.getReleasableAmount(address(this));
        assertEq(amount, vesting.getVestAmount(address(this)));
    }

    function testClaim() external {
        setParams();
        uint256 balBefore = vested.balanceOf(address(this));
        uint256 claimAmount = vesting.getReleasableAmount(address(this));
        vesting.claimDistribution(address(this));
        assertEq(vested.balanceOf(address(this)) - balBefore, claimAmount);
    }

    function testCrowdfundingSetupCorrectly() external {
        setParams();
        // correct balances
        assertTrue(vesting.getTotalToken(address(vested)) == 1400e18);
        assertTrue(payment.balanceOf(address(vesting)) == 100e18);

        // whitelist setup
        (, , uint256 value, uint256 amount, ) = vesting.userTag(
            "testTag",
            address(this)
        );
        assertTrue(amount == 1000e18);
        assertTrue(value == 100e18);
    }

    function testRefund() public {
        setParams();
        uint256 balBefore = payment.balanceOf(address(this));

        // cannot refund before vesting start
        (uint32 startTime, , , ) = vesting.vestingPool();
        vm.warp(startTime);
        vm.expectRevert(bytes("Not in grace period"));
        vesting.refund("testTag");

        // should receive refund sub fee
        vm.warp(startTime + 1);
        vesting.refund("testTag");
        assertEq(payment.balanceOf(address(this)) - balBefore, 99e18);
        assertGt(payment.balanceOf(address(2)), 0);

        // cannot refund twice
        vm.expectRevert(bytes("user already refunded"));
        vesting.refund("testTag");

        // cannot refund after grace period
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(bytes("Not in grace period"));
        vesting.refund("testTag");

        // cannot claim after refund
        vm.expectRevert(bytes("user already refunded"));
        vesting.claimDistribution(address(this));
    }

    function testRefundTags() public {
        IIGOVesting.VestingSetup memory v;

        v = IIGOVesting.VestingSetup(
            uint32(block.timestamp),
            100_000,
            10_000_000,
            100
        );

        vesting.initializeCrowdfunding(
            IIGOVesting.ContractSetup(
                address(1),
                address(2),
                address(3),
                address(vested),
                50,
                1000e18,
                1 days,
                1000
            ),
            v
        );

        payment.transfer(address(vesting), 700e18);
        payment2.transfer(address(vesting), 300e18);
        vesting.setCrowdfundingWhitelist(
            "testTag1",
            user1,
            100e18,
            address(payment),
            300e18,
            50
        );
        vesting.setCrowdfundingWhitelist(
            "testTag2",
            user1,
            200e18,
            address(payment2),
            400e18,
            50
        );
        vesting.setCrowdfundingWhitelist(
            "testTag1",
            user2,
            100e18,
            address(payment),
            300e18,
            25
        );
        vesting.setCrowdfundingWhitelist(
            "testTag2",
            user2,
            100e18,
            address(payment2),
            150e18,
            25
        );

        (uint32 startTime, , , ) = vesting.vestingPool();
        vm.warp(startTime + 1);

        vm.startPrank(user1);
        vesting.refund("testTag1");
        assertEq(payment.balanceOf(address(user1)), 95e18); //5% fee
        vesting.refund("testTag2");
        assertEq(payment2.balanceOf(address(user1)), 190e18); //5% fee
        vm.stopPrank();

        vm.warp(startTime + 2 days);
        vm.startPrank(address(1));
        vesting.claimRaisedFunds(address(payment));
        assertEq(payment.balanceOf(address(1)), 95e18); //5% platform fee
        assertEq(vested.balanceOf(address(1)), 700e18);

        vesting.claimRaisedFunds(address(payment2));
        assertEq(payment2.balanceOf(address(1)), 95e18);
        assertEq(vested.balanceOf(address(1)), 700e18); //Token amount remains same
    }

    function testInnovatorClaim() public {
        setParams();
        vm.startPrank(address(1));

        // grace period still in progress
        vm.expectRevert(bytes("grace period in progress"));
        vesting.claimRaisedFunds(address(payment));

        vm.warp(block.timestamp + 2 days);

        vesting.claimRaisedFunds(address(payment));

        // should receive funds sub fee & no tokens back as all were sold
        assertTrue(payment.balanceOf(address(1)) == 95e18);
        assertTrue(vested.balanceOf(address(1)) == 0);
        assertTrue(payment.balanceOf(address(2)) == 5e18);

        vm.stopPrank();
    }

    function testInnovatorClaimAfterRefund() public {
        testRefund();

        vm.startPrank(address(1));
        vm.warp(block.timestamp + 2 days);

        vesting.claimRaisedFunds(address(payment));

        // should receive no funds and all tokens on sale back
        assertTrue(payment.balanceOf(address(1)) == 0);
        assertTrue(vested.balanceOf(address(1)) == 1000e18);

        vm.stopPrank();
    }

    function testSetters() public {
        setParams();
        vm.startPrank(address(3));
        vesting.setVestingStartTime(uint32(block.timestamp + 100));
        vesting.setToken(address(4));
        vm.stopPrank();

        (uint32 startTime, , , ) = vesting.vestingPool();
        assertTrue(startTime == uint32(block.timestamp + 100));
        assertTrue(address(vesting.vestedToken()) == address(4));
    }
}
