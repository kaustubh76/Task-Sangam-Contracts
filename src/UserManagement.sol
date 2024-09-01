// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract UserManagement is AccessControl, Pausable {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    struct User {
        address userAddress;
        bool isFreelancer;
        uint256 reputation;
        bool isActive;
        uint256 totalJobsCompleted;
        uint256 totalEarnings;
        uint256 lastActivityTimestamp;
    }

    mapping(address => User) public users;
    uint256 private _userIdCounter;

    uint256 public constant MAX_REPUTATION = 100;
    uint256 public constant INACTIVITY_THRESHOLD = 180 days;

    event UserRegistered(address indexed userAddress, bool isFreelancer, uint256 userId);
    event UserDeactivated(address indexed userAddress);
    event UserReactivated(address indexed userAddress);
    event ReputationUpdated(address indexed userAddress, uint256 newReputation);
    event JobCompleted(address indexed userAddress, uint256 earnings);
    event UserActivityUpdated(address indexed userAddress, uint256 timestamp);


    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function registerUser(bool _isFreelancer) external whenNotPaused {
        require(users[msg.sender].userAddress == address(0), "User already registered");
        uint256 userId = _userIdCounter;
        users[msg.sender] = User({
            userAddress: msg.sender,
            isFreelancer: _isFreelancer,
            reputation: 0,
            isActive: true,
            totalJobsCompleted: 0,
            totalEarnings: 0,
            lastActivityTimestamp: block.timestamp
        });
        ++_userIdCounter;
        emit UserRegistered(msg.sender, _isFreelancer, userId);
    }

    function deactivateUser(address _user) external onlyRole(ADMIN_ROLE) {
        require(users[_user].userAddress != address(0), "User not registered");
        require(users[_user].isActive, "User already deactivated");
        users[_user].isActive = false;
        emit UserDeactivated(_user);
    }

    function reactivateUser(address _user) external onlyRole(ADMIN_ROLE) {
        require(users[_user].userAddress != address(0), "User not registered");
        require(!users[_user].isActive, "User already active");
        users[_user].isActive = true;
        emit UserReactivated(_user);
    }

    function updateReputation(address _user, uint256 _newReputation) external onlyRole(MODERATOR_ROLE) {
        require(users[_user].userAddress != address(0), "User not registered");
        require(_newReputation <= MAX_REPUTATION, "Reputation must be between 0 and MAX_REPUTATION");
        users[_user].reputation = _newReputation;
        emit ReputationUpdated(_user, _newReputation);
    }

    function completeJob(address _user, uint256 _earnings) external onlyRole(MODERATOR_ROLE) {
        require(users[_user].userAddress != address(0), "User not registered");
        users[_user].totalJobsCompleted++;
        users[_user].totalEarnings += _earnings;
        updateUserActivity(_user);
        emit JobCompleted(_user, _earnings);
    }

    function updateUserActivity(address _user) public {
        require(users[_user].userAddress != address(0), "User not registered");
        users[_user].lastActivityTimestamp = block.timestamp;
        emit UserActivityUpdated(_user, block.timestamp);
    }

    function deactivateInactiveUsers() external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 1; i <= _userIdCounter; i++) {
            address userAddress = getUserAddressById(i);
            if (users[userAddress].isActive && 
                block.timestamp - users[userAddress].lastActivityTimestamp > INACTIVITY_THRESHOLD) {
                users[userAddress].isActive = false;
                emit UserDeactivated(userAddress);
            }
        }
    }

    function getUserAddressById(uint256 _userId) public view returns (address) {
        require(_userId <= _userIdCounter, "Invalid user ID");
        // This is a simplification. In a real-world scenario, you'd need a more efficient way to map IDs to addresses.
        for (uint256 i = 1; i <= _userIdCounter; i++) {
            if (i == _userId) {
                return users[address(uint160(i))].userAddress;
            }
        }
        revert("User not found");
    }

    function getUser(address _user) external view returns (User memory) {
        return users[_user];
    }

    function pauseContract() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}