// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UserManagement} from "../src/UserManagement.sol";

contract JobPosting is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant JOB_MANAGER_ROLE = keccak256("JOB_MANAGER_ROLE");

    struct Job {
        uint256 id;
        address client;
        string ipfsHash;
        uint256 budget;
        uint256 deadline;
        address hiredFreelancer;
        bool isCompleted;
        bool isCancelled;
        JobStatus status;
        uint256 createdAt;
        uint256 completedAt;
    }

    enum JobStatus {
        Posted,
        InProgress,
        Completed,
        Cancelled,
        Disputed
    }

    UserManagement public userManagement;
    IERC20 public paymentToken;
    address public proposalManager;
    address public workSubmission;
    uint256 private _jobIdCounter;
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => mapping(address => bool)) public jobProposals;

    uint256 public constant MAX_JOB_DURATION = 365 days;
    uint256 public constant MIN_JOB_BUDGET = 1e18; // 1 token

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        uint256 budget,
        uint256 deadline
    );
    event ProposalSubmitted(uint256 indexed jobId, address indexed freelancer);
    event FreelancerHired(uint256 indexed jobId, address indexed freelancer);
    event JobCompleted(uint256 indexed jobId);
    event JobCancelled(uint256 indexed jobId);
    event JobDisputed(uint256 indexed jobId);
    event DisputeResolved(uint256 indexed jobId, address winner);

    constructor(address _userManagementAddress, address _paymentTokenAddress) {
        userManagement = UserManagement(_userManagementAddress);
        paymentToken = IERC20(_paymentTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(JOB_MANAGER_ROLE, msg.sender);
    }

    modifier onlyClient(uint256 _jobId) {
        require(
            jobs[_jobId].client == msg.sender,
            "Only job client can perform this action"
        );
        _;
    }

    modifier onlyClientOrProposalManager(uint256 _jobId) {
        require(
            jobs[_jobId].client == msg.sender || proposalManager == msg.sender,
            "Only propsal manager or job client can perform this action"
        );
        _;
    }

    modifier onlyClientOrWorkSubmission(uint256 _jobId) {
        require(
            jobs[_jobId].client == msg.sender || address(workSubmission) == msg.sender,
            "Only work submission or job client can perform this action"
        );
        _;
    }

    modifier onlyActiveJob(uint256 _jobId) {
        require(
            jobs[_jobId].status == JobStatus.Posted ||
                jobs[_jobId].status == JobStatus.InProgress,
            "Job is not active"
        );
        _;
    }

    modifier jobExists(uint256 _jobId) {
        require(_jobId <= _jobIdCounter, "Job does not exist");
        _;
    }

    function setProposalManager(
        address _proposalManager
    ) external onlyRole(ADMIN_ROLE) {
        proposalManager = _proposalManager;
    }

    function setWorkSubmission(address _workSubmissionAddress) external onlyRole(ADMIN_ROLE) {
        workSubmission = _workSubmissionAddress;
    }

    function createJob(
        string memory _ipfsHash,
        uint256 _budget,
        uint256 _deadline
    ) external nonReentrant whenNotPaused {
        require(
            userManagement.getUser(msg.sender).userAddress != address(0),
            "User not registered"
        );
        require(
            !userManagement.getUser(msg.sender).isFreelancer,
            "Freelancers cannot create jobs"
        );
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(
            _deadline <= block.timestamp + MAX_JOB_DURATION,
            "Job duration exceeds maximum allowed"
        );
        require(
            _budget >= MIN_JOB_BUDGET,
            "Job budget is below minimum allowed"
        );

        uint256 jobId = _jobIdCounter;
        jobs[jobId] = Job({
            id: jobId,
            client: msg.sender,
            ipfsHash: _ipfsHash,
            budget: _budget,
            deadline: _deadline,
            hiredFreelancer: address(0),
            isCompleted: false,
            isCancelled: false,
            status: JobStatus.Posted,
            createdAt: block.timestamp,
            completedAt: 0
        });
        ++_jobIdCounter;

        paymentToken.safeTransferFrom(msg.sender, address(this), _budget);

        emit JobCreated(jobId, msg.sender, _budget, _deadline);
    }

    function submitProposal(
        uint256 _jobId,
        address _freelancer
    ) external nonReentrant whenNotPaused jobExists(_jobId) {
        if (msg.sender != proposalManager) {
            require(msg.sender == _freelancer);
        }
        require(
            userManagement.getUser(_freelancer).isFreelancer,
            "Only freelancers can submit proposals"
        );
        require(
            jobs[_jobId].status == JobStatus.Posted,
            "Job is not open for proposals"
        );
        require(
            !jobProposals[_jobId][_freelancer],
            "Proposal already submitted"
        );
        require(
            block.timestamp < jobs[_jobId].deadline,
            "Job deadline has passed"
        );

        jobProposals[_jobId][_freelancer] = true;
        emit ProposalSubmitted(_jobId, _freelancer);
    }

    function hireFreelancer(
        uint256 _jobId,
        address _freelancer
    )
        external
        nonReentrant
        whenNotPaused
        onlyClientOrProposalManager(_jobId)
        onlyActiveJob(_jobId)
    {
        require(
            jobs[_jobId].hiredFreelancer == address(0),
            "Freelancer already hired"
        );
        require(
            userManagement.getUser(_freelancer).isFreelancer,
            "Hired address must be a freelancer"
        );
        require(
            jobProposals[_jobId][_freelancer],
            "Freelancer has not submitted a proposal"
        );
        require(
            block.timestamp < jobs[_jobId].deadline,
            "Job deadline has passed"
        );

        jobs[_jobId].hiredFreelancer = _freelancer;
        jobs[_jobId].status = JobStatus.InProgress;
        emit FreelancerHired(_jobId, _freelancer);
    }

    function completeJob(
        uint256 _jobId
    )
        external
        nonReentrant
        whenNotPaused
        onlyClientOrWorkSubmission(_jobId)
        onlyActiveJob(_jobId)
    {
        require(
            jobs[_jobId].hiredFreelancer != address(0),
            "No freelancer hired for this job"
        );
        require(
            block.timestamp <= jobs[_jobId].deadline,
            "Job deadline has passed"
        );

        jobs[_jobId].isCompleted = true;
        jobs[_jobId].status = JobStatus.Completed;
        jobs[_jobId].completedAt = block.timestamp;

        address freelancer = jobs[_jobId].hiredFreelancer;
        uint256 payment = jobs[_jobId].budget;

        paymentToken.safeTransfer(freelancer, payment);
        userManagement.completeJob(freelancer, payment);

        emit JobCompleted(_jobId);
    }

    function cancelJob(
        uint256 _jobId
    )
        external
        nonReentrant
        whenNotPaused
        onlyClient(_jobId)
        onlyActiveJob(_jobId)
    {
        require(
            jobs[_jobId].hiredFreelancer == address(0),
            "Cannot cancel job after hiring freelancer"
        );

        jobs[_jobId].isCancelled = true;
        jobs[_jobId].status = JobStatus.Cancelled;

        paymentToken.safeTransfer(jobs[_jobId].client, jobs[_jobId].budget);

        emit JobCancelled(_jobId);
    }

    function initiateDispute(
        uint256 _jobId
    ) external nonReentrant whenNotPaused onlyActiveJob(_jobId) {
        require(
            msg.sender == jobs[_jobId].client ||
                msg.sender == jobs[_jobId].hiredFreelancer,
            "Only client or hired freelancer can initiate dispute"
        );

        jobs[_jobId].status = JobStatus.Disputed;
        emit JobDisputed(_jobId);
    }

    function resolveDispute(
        uint256 _jobId,
        address _winner
    ) external onlyRole(JOB_MANAGER_ROLE) {
        require(
            jobs[_jobId].status == JobStatus.Disputed,
            "Job is not in disputed state"
        );
        require(
            _winner == jobs[_jobId].client ||
                _winner == jobs[_jobId].hiredFreelancer,
            "Invalid winner address"
        );

        if (_winner == jobs[_jobId].hiredFreelancer) {
            paymentToken.safeTransfer(
                jobs[_jobId].hiredFreelancer,
                jobs[_jobId].budget
            );
            userManagement.completeJob(
                jobs[_jobId].hiredFreelancer,
                jobs[_jobId].budget
            );
        } else {
            paymentToken.safeTransfer(jobs[_jobId].client, jobs[_jobId].budget);
        }

        jobs[_jobId].isCompleted = true;
        jobs[_jobId].status = JobStatus.Completed;
        jobs[_jobId].completedAt = block.timestamp;

        emit DisputeResolved(_jobId, _winner);
    }

    function getJob(uint256 _jobId) external view returns (Job memory) {
        require(_jobId <= _jobIdCounter, "Job does not exist");
        return jobs[_jobId];
    }

    function extendJobDeadline(
        uint256 _jobId,
        uint256 _newDeadline
    ) external onlyClient(_jobId) onlyActiveJob(_jobId) {
        require(
            _newDeadline > jobs[_jobId].deadline,
            "New deadline must be later than current deadline"
        );
        require(
            _newDeadline <= block.timestamp + MAX_JOB_DURATION,
            "New deadline exceeds maximum allowed job duration"
        );
        jobs[_jobId].deadline = _newDeadline;
    }

    function increaseBudget(
        uint256 _jobId,
        uint256 _additionalBudget
    ) external nonReentrant onlyClient(_jobId) onlyActiveJob(_jobId) {
        require(
            _additionalBudget > 0,
            "Additional budget must be greater than zero"
        );
        paymentToken.safeTransferFrom(
            msg.sender,
            address(this),
            _additionalBudget
        );
        jobs[_jobId].budget += _additionalBudget;
    }

    function getActiveJobCount() external view returns (uint256) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _jobIdCounter; i++) {
            if (
                jobs[i].status == JobStatus.Posted ||
                jobs[i].status == JobStatus.InProgress
            ) {
                activeCount++;
            }
        }
        return activeCount;
    }

    function getAllJobsCounter() external view returns (uint256) {
        return _jobIdCounter;
    }

    function pauseContract() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
