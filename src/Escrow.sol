// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { JobPosting } from "../src/JobPosting.sol";

contract Escrow is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ESCROW_MANAGER_ROLE = keccak256("ESCROW_MANAGER_ROLE");

    struct EscrowAccount {
        uint256 balance;
        bool isReleased;
        address client;
        address freelancer;
        EscrowStatus status;
        uint256 createdAt;
        uint256 releasedAt;
    }

    enum EscrowStatus { Active, Released, Refunded, Disputed }

    IERC20 public paymentToken;
    JobPosting public jobPosting;

    mapping(uint256 => EscrowAccount) public escrows;

    event FundsDeposited(uint256 indexed jobId, uint256 amount);
    event FundsReleased(uint256 indexed jobId, address indexed freelancer, uint256 amount);
    event FundsRefunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event DisputeInitiated(uint256 indexed jobId);
    event DisputeResolved(uint256 indexed jobId, address winner, uint256 amount);

    constructor(address _paymentTokenAddress, address _jobPostingAddress) {
        paymentToken = IERC20(_paymentTokenAddress);
        jobPosting = JobPosting(_jobPostingAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ESCROW_MANAGER_ROLE, msg.sender);
    }

    modifier onlyJobParticipant(uint256 _jobId) {
        require(
            msg.sender == escrows[_jobId].client || msg.sender == escrows[_jobId].freelancer,
            "Only job participant can perform this action"
        );
        _;
    }

    modifier escrowExists(uint256 _jobId) {
        require(escrows[_jobId].client != address(0), "Escrow does not exist for this job");
        _;
    }

    function createEscrow(uint256 _jobId, address _client, address _freelancer, uint256 _amount) external onlyRole(ESCROW_MANAGER_ROLE) whenNotPaused {
        require(escrows[_jobId].client == address(0), "Escrow already exists for this job");
        require(_amount > 0, "Escrow amount must be greater than zero");

        escrows[_jobId] = EscrowAccount({
            balance: _amount,
            isReleased: false,
            client: _client,
            freelancer: _freelancer,
            status: EscrowStatus.Active,
            createdAt: block.timestamp,
            releasedAt: 0
        });

        paymentToken.safeTransferFrom(_client, address(this), _amount);
        emit FundsDeposited(_jobId, _amount);
    }

    function releaseFunds(uint256 _jobId) external nonReentrant whenNotPaused onlyJobParticipant(_jobId) escrowExists(_jobId) {
        require(escrows[_jobId].status == EscrowStatus.Active, "Escrow is not in active state");
        require(msg.sender == escrows[_jobId].client, "Only client can release funds");

        uint256 amount = escrows[_jobId].balance;
        escrows[_jobId].balance = 0;
        escrows[_jobId].isReleased = true;
        escrows[_jobId].status = EscrowStatus.Released;
        escrows[_jobId].releasedAt = block.timestamp;

        paymentToken.safeTransfer(escrows[_jobId].freelancer, amount);
        emit FundsReleased(_jobId, escrows[_jobId].freelancer, amount);
    }

    function refundClient(uint256 _jobId) external nonReentrant whenNotPaused onlyRole(ESCROW_MANAGER_ROLE) escrowExists(_jobId) {
        require(escrows[_jobId].status == EscrowStatus.Active, "Escrow is not in active state");

        uint256 amount = escrows[_jobId].balance;
        escrows[_jobId].balance = 0;
        escrows[_jobId].status = EscrowStatus.Refunded;

        paymentToken.safeTransfer(escrows[_jobId].client, amount);
        emit FundsRefunded(_jobId, escrows[_jobId].client, amount);
    }

    function initiateDispute(uint256 _jobId) external nonReentrant whenNotPaused onlyJobParticipant(_jobId) escrowExists(_jobId) {
        require(escrows[_jobId].status == EscrowStatus.Active, "Escrow is not in active state");
        escrows[_jobId].status = EscrowStatus.Disputed;
        emit DisputeInitiated(_jobId);
    }

    function resolveDispute(uint256 _jobId, address _winner) external onlyRole(ESCROW_MANAGER_ROLE) escrowExists(_jobId) {
        require(escrows[_jobId].status == EscrowStatus.Disputed, "Escrow is not in disputed state");
        require(_winner == escrows[_jobId].client || _winner == escrows[_jobId].freelancer, "Invalid winner address");

        uint256 amount = escrows[_jobId].balance;
        escrows[_jobId].balance = 0;
        escrows[_jobId].status = EscrowStatus.Released;
        escrows[_jobId].releasedAt = block.timestamp;

        paymentToken.safeTransfer(_winner, amount);
        emit DisputeResolved(_jobId, _winner, amount);
    }

    function getEscrowDetails(uint256 _jobId) external view returns (EscrowAccount memory) {
        require(escrows[_jobId].client != address(0), "Escrow does not exist for this job");
        return escrows[_jobId];
    }

    function addFunds(uint256 _jobId, uint256 _amount) external nonReentrant whenNotPaused escrowExists(_jobId) {
        require(msg.sender == escrows[_jobId].client, "Only client can add funds");
        require(escrows[_jobId].status == EscrowStatus.Active, "Escrow is not in active state");
        require(_amount > 0, "Amount must be greater than zero");

        escrows[_jobId].balance += _amount;
        paymentToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit FundsDeposited(_jobId, _amount);
    }

    function pauseContract() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}