// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {UserManagement} from "../src/UserManagement.sol";

contract UserManagementTest is Test {
    UserManagement public userManagement;
    address public owner;
    address public addr1;
    address public addr2;
    address public moderator;

    function setUp() public {
        owner = address(this);
        addr1 = address(0x1);
        addr2 = address(0x2);
        moderator = address(0x3);

        userManagement = new UserManagement();
        userManagement.grantRole(userManagement.MODERATOR_ROLE(), moderator);
    }

    function testDeployment() public {
        assertTrue(
            userManagement.hasRole(userManagement.DEFAULT_ADMIN_ROLE(), owner)
        );
        assertTrue(userManagement.hasRole(userManagement.ADMIN_ROLE(), owner));
    }

    function testRegisterUser() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        UserManagement.User memory user = userManagement.getUser(addr1);
        assertTrue(user.isFreelancer);
        assertTrue(user.isActive);
        assertEq(user.userAddress, addr1);
    }

    function testRegisterUserTwice() public {
        vm.startPrank(addr1);
        userManagement.registerUser(true);

        vm.expectRevert("User already registered");
        userManagement.registerUser(true);
        vm.stopPrank();
    }

    function testDeactivateUser() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        userManagement.deactivateUser(addr1);
        UserManagement.User memory user = userManagement.getUser(addr1);
        assertFalse(user.isActive);
    }

    function testReactivateUser() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        userManagement.deactivateUser(addr1);
        userManagement.reactivateUser(addr1);
        UserManagement.User memory user = userManagement.getUser(addr1);
        assertTrue(user.isActive);
    }

    function testUpdateReputation() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        vm.prank(moderator);
        userManagement.updateReputation(addr1, 75);

        UserManagement.User memory user = userManagement.getUser(addr1);
        assertEq(user.reputation, 75);
    }

    function testUpdateReputationAboveMax() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        vm.prank(moderator);
        vm.expectRevert("Reputation must be between 0 and MAX_REPUTATION");
        userManagement.updateReputation(addr1, 101);
    }

    function testCompleteJob() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        vm.prank(moderator);
        userManagement.completeJob(addr1, 1 ether);

        UserManagement.User memory user = userManagement.getUser(addr1);
        assertEq(user.totalJobsCompleted, 1);
        assertEq(user.totalEarnings, 1 ether);
    }

    function testUpdateUserActivity() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        uint256 beforeTimestamp = block.timestamp;
        vm.warp(beforeTimestamp + 1 days);

        userManagement.updateUserActivity(addr1);

        UserManagement.User memory user = userManagement.getUser(addr1);
        assertGt(user.lastActivityTimestamp, beforeTimestamp);
    }

    function testDeactivateInactiveUsers() public {
        vm.prank(addr1);
        userManagement.registerUser(true);
        vm.prank(addr2);
        userManagement.registerUser(false);
        // Simulate passage of time
        vm.warp(block.timestamp + 181 days);
        userManagement.deactivateInactiveUsers();
        UserManagement.User memory user1 = userManagement.getUser(addr1);
        UserManagement.User memory user2 = userManagement.getUser(addr2);
        assertFalse(user1.isActive);
        assertFalse(user2.isActive);
    }

    function testPauseContract() public {
        userManagement.pauseContract();
        assertTrue(userManagement.paused());
        vm.prank(addr1);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        userManagement.registerUser(true);
    }

    function testUnpauseContract() public {
        userManagement.pauseContract();
        userManagement.unpauseContract();
        assertFalse(userManagement.paused());

        vm.prank(addr1);
        userManagement.registerUser(true);
        UserManagement.User memory user = userManagement.getUser(addr1);
        assertTrue(user.isActive);
    }
    
    function testGetUserAddressById() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        address userAddress = userManagement.getUserAddressById(1);
        assertEq(userAddress, addr1);
    }
    
    function testGetNonExistentUserAddressById() public {
        vm.expectRevert("Invalid user ID");
        userManagement.getUserAddressById(999);
    }

    function testMultipleJobCompletions() public {
        vm.prank(addr1);
        userManagement.registerUser(true);

        vm.startPrank(moderator);
        userManagement.completeJob(addr1, 1 ether);
        userManagement.completeJob(addr1, 2 ether);
        vm.stopPrank();

        UserManagement.User memory user = userManagement.getUser(addr1);
        assertEq(user.totalJobsCompleted, 2);
        assertEq(user.totalEarnings, 3 ether);
    }

    receive() external payable {}
}
