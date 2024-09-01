// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/WorkSubmission.sol";
import "../src/UserManagement.sol";
import "../src/JobPosting.sol";
import "../src/ProposalManagement.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract WorkSubmissionTest is Test {
    WorkSubmission public workSubmission;
    UserManagement public userManagement;
    JobPosting public jobPosting;
    ProposalManagement public proposalManagement;
    ERC20Mock public mockToken;

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    address public owner;
    address public client;
    address public freelancer;
    uint256 public jobId;

    event WorkSubmitted(
        uint256 indexed submissionId,
        uint256 indexed jobId,
        address indexed freelancer
    );
    event SubmissionUpdated(
        uint256 indexed submissionId,
        string newWorkIPFSHash,
        string newCommentIPFSHash
    );
    event SubmissionStatusChanged(
        uint256 indexed submissionId,
        WorkSubmission.SubmissionStatus newStatus
    );

    function setUp() public {
        owner = address(this);
        client = address(0x1);
        freelancer = address(0x2);

        // Deploy mock contracts
        mockToken = new ERC20Mock();
        mockToken.mint(address(this), 1_000_000_000 ether);
        mockToken.mint(client, 1000_000 ether);
        userManagement = new UserManagement();
        jobPosting = new JobPosting(
            address(userManagement),
            address(mockToken)
        );
        userManagement.grantRole(MODERATOR_ROLE, address(jobPosting));
        proposalManagement = new ProposalManagement(
            address(userManagement),
            address(jobPosting)
        );
        jobPosting.setProposalManager(address(proposalManagement));

        // Deploy WorkSubmission contract
        workSubmission = new WorkSubmission(
            address(userManagement),
            address(jobPosting),
            address(proposalManagement)
        );

        jobPosting.setWorkSubmission(address(workSubmission));

        // Setup users
        vm.prank(client);
        userManagement.registerUser(false);
        vm.prank(freelancer);
        userManagement.registerUser(true);

        // Create a job
        vm.startPrank(client);
        mockToken.approve(address(jobPosting), 1000 ether);
        jobPosting.createJob(
            "ipfs://job-hash",
            1000 ether,
            block.timestamp + 30 days
        );
        jobId = jobPosting.getActiveJobCount() - 1; // Assuming this returns the latest job ID
        vm.stopPrank();
        // Submit proposal and hire freelancer
        vm.prank(freelancer);
        proposalManagement.submitProposal(
            0,
            1000 ether,
            "ipfs://proposal-hash",
            block.timestamp + 20 days
        );
        vm.prank(client);
        proposalManagement.acceptProposal(1);
    }

    function testSubmitWork() public {
        vm.prank(freelancer);
        vm.expectEmit(true, true, true, false);
        emit WorkSubmitted(1, jobId, freelancer);
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");

        WorkSubmission.Submission memory submission = workSubmission
            .getJobSubmissions(jobId)[0];
        assertEq(submission.freelancer, freelancer);
        assertEq(submission.workIPFSHash, "ipfs://work-hash");
        assertEq(submission.commentIPFSHash, "Great work!");
        assertEq(
            uint(submission.status),
            uint(WorkSubmission.SubmissionStatus.Pending)
        );
    }

    function testUpdateSubmission() public {
        vm.startPrank(freelancer);
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");

        vm.expectEmit(true, true, true, false);
        emit SubmissionUpdated(1, "ipfs://updated-work-hash", "Updated work!");
        workSubmission.updateSubmission(
            jobId,
            1,
            "ipfs://updated-work-hash",
            "Updated work!"
        );

        WorkSubmission.Submission memory submission = workSubmission
            .getJobSubmissions(jobId)[0];
        assertEq(submission.workIPFSHash, "ipfs://updated-work-hash");
        assertEq(submission.commentIPFSHash, "Updated work!");
        assertEq(
            uint(submission.status),
            uint(WorkSubmission.SubmissionStatus.Revised)
        );
        vm.stopPrank();
    }

    function testApproveSubmission() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");

        vm.startPrank(client);
        vm.expectEmit(true, true, true, false);
        emit SubmissionStatusChanged(
            1,
            WorkSubmission.SubmissionStatus.Approved
        );
        workSubmission.approveSubmission(jobId, 1);
        WorkSubmission.Submission memory submission = workSubmission
            .getJobSubmissions(jobId)[0];
        assertEq(
            uint(submission.status),
            uint(WorkSubmission.SubmissionStatus.Approved)
        );
        assertEq(
            uint(jobPosting.getJob(jobId).status),
            uint(JobPosting.JobStatus.Completed)
        );
    }
    function testRejectSubmission() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");
        vm.prank(client);
        vm.expectEmit(true, true, true, false);
        emit SubmissionStatusChanged(
            1,
            WorkSubmission.SubmissionStatus.Rejected
        );
        workSubmission.rejectSubmission(jobId, 1, "Need improvements");

        WorkSubmission.Submission memory submission = workSubmission
            .getJobSubmissions(jobId)[0];
        assertEq(
            uint(submission.status),
            uint(WorkSubmission.SubmissionStatus.Rejected)
        );
        assertEq(submission.commentIPFSHash, "Need improvements");
    }
    function testOnlyFreelancerCanSubmitWork() public {
        vm.prank(client);
        vm.expectRevert("Only the hired freelancer can perform this action");
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");
    }

    function testOnlyClientCanApproveOrReject() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");

        vm.prank(freelancer);
        vm.expectRevert("Only the job client can perform this action");
        workSubmission.approveSubmission(jobId, 1);

        vm.prank(freelancer);
        vm.expectRevert("Only the job client can perform this action");
        workSubmission.rejectSubmission(jobId, 1, "Need improvements");
    }

    function testCannotSubmitWorkForNonExistentJob() public {
        vm.prank(freelancer);
        vm.expectRevert("Job does not exist");
        workSubmission.submitWork(999, "ipfs://work-hash", "Great work!");
    }

    function testCannotUpdateApprovedSubmission() public {
        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");

        vm.prank(client);
        workSubmission.approveSubmission(jobId, 1);

        vm.prank(freelancer);
        vm.expectRevert("Can only update pending or rejected submissions");
        workSubmission.updateSubmission(
            jobId,
            1,
            "ipfs://updated-work-hash",
            "Updated work!"
        );
    }

    function testPauseAndUnpause() public {
        workSubmission.pause();
        vm.prank(freelancer);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");

        workSubmission.unpause();

        vm.prank(freelancer);
        workSubmission.submitWork(jobId, "ipfs://work-hash", "Great work!");
    }

    function testOnlyOwnerCanPauseAndUnpause() public {
        vm.prank(freelancer);
        vm.expectRevert();
        workSubmission.pause();

        vm.prank(freelancer);
        vm.expectRevert();
        workSubmission.unpause();
    }
}

// // Mock ERC20 contract for testing
contract ERC20Mock is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
    }

    // Function to mint tokens for testing
    function mint(address account, uint256 amount) external {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
    }
}
