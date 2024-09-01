// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/JobPosting.sol";
import "../src/UserManagement.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract JobPostingTest is Test {
    JobPosting public jobPosting;
    UserManagement public userManagement;
    MockERC20 public paymentToken;

    address public owner;
    address public client;
    address public freelancer;
    address public jobManager;
    address public admin;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant JOB_MANAGER_ROLE = keccak256("JOB_MANAGER_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        client = address(0x1);
        freelancer = address(0x2);
        jobManager = address(0x3);
        admin = address(0x4);

        vm.startPrank(owner);

        userManagement = new UserManagement();
        paymentToken = new MockERC20();
        jobPosting = new JobPosting(
            address(userManagement),
            address(paymentToken)
        );

        userManagement.grantRole(MODERATOR_ROLE, address(jobPosting));

        jobPosting.grantRole(ADMIN_ROLE, admin);
        jobPosting.grantRole(JOB_MANAGER_ROLE, jobManager);

        paymentToken.mint(client, INITIAL_BALANCE);
        paymentToken.mint(freelancer, INITIAL_BALANCE);

        vm.stopPrank();

        vm.prank(client);
        userManagement.registerUser(false);
        vm.prank(freelancer);
        userManagement.registerUser(true);
    }

    function testCreateJob() public {
        vm.startPrank(client);
        paymentToken.approve(address(jobPosting), INITIAL_BALANCE);

        uint256 budget = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 30 days;
        string memory ipfsHash = "QmTest";

        jobPosting.createJob(ipfsHash, budget, deadline);

        JobPosting.Job memory job = jobPosting.getJob(0);
        assertEq(job.client, client);
        assertEq(job.ipfsHash, ipfsHash);
        assertEq(job.budget, budget);
        assertEq(job.deadline, deadline);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.Posted));

        vm.stopPrank();
    }

    function testSubmitProposal() public {
        // Create a job first
        testCreateJob();

        vm.prank(freelancer);
        jobPosting.submitProposal(0, freelancer);

        assertTrue(jobPosting.jobProposals(0, freelancer));
    }

    function testHireFreelancer() public {
        testSubmitProposal();

        vm.prank(client);
        jobPosting.hireFreelancer(0, freelancer);

        JobPosting.Job memory job = jobPosting.getJob(0);
        assertEq(job.hiredFreelancer, freelancer);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.InProgress));
    }

    function testCompleteJob() public {
        testHireFreelancer();
        uint256 initialBalance = paymentToken.balanceOf(freelancer);
        vm.prank(client);
        jobPosting.completeJob(0);
        JobPosting.Job memory job = jobPosting.getJob(0);
        assertTrue(job.isCompleted);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.Completed));
        uint256 finalBalance = paymentToken.balanceOf(freelancer);
        assertEq(finalBalance - initialBalance, job.budget);
    }

    function testCancelJob() public {
        testCreateJob();

        uint256 initialBalance = paymentToken.balanceOf(client);

        vm.prank(client);
        jobPosting.cancelJob(0);

        JobPosting.Job memory job = jobPosting.getJob(0);
        assertTrue(job.isCancelled);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.Cancelled));

        uint256 finalBalance = paymentToken.balanceOf(client);
        assertEq(finalBalance - initialBalance, job.budget);
    }

    function testInitiateDispute() public {
        testHireFreelancer();

        vm.prank(client);
        jobPosting.initiateDispute(0);

        JobPosting.Job memory job = jobPosting.getJob(0);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.Disputed));
    }
    
    function testResolveDispute() public {
        testInitiateDispute();

        uint256 initialBalance = paymentToken.balanceOf(freelancer);

        vm.prank(jobManager);
        jobPosting.resolveDispute(0, freelancer);

        JobPosting.Job memory job = jobPosting.getJob(0);
        assertTrue(job.isCompleted);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.Completed));

        uint256 finalBalance = paymentToken.balanceOf(freelancer);
        assertEq(finalBalance - initialBalance, job.budget);
    }
    
    function testExtendJobDeadline() public {
        testCreateJob();

        uint256 newDeadline = block.timestamp + 60 days;

        vm.prank(client);
        jobPosting.extendJobDeadline(0, newDeadline);

        JobPosting.Job memory job = jobPosting.getJob(0);
        assertEq(job.deadline, newDeadline);
    }

    function testIncreaseBudget() public {
        testCreateJob();

        uint256 additionalBudget = 50 * 10 ** 18;
        uint256 initialBudget = jobPosting.getJob(0).budget;

        vm.startPrank(client);
        paymentToken.approve(address(jobPosting), additionalBudget);
        jobPosting.increaseBudget(0, additionalBudget);
        vm.stopPrank();

        JobPosting.Job memory job = jobPosting.getJob(0);
        assertEq(job.budget, initialBudget + additionalBudget);
    }

     function testGetActiveJobCount() public {
         testCreateJob();
         testCreateJob();
         testHireFreelancer(); // this will also create a job
         uint256 activeCount = jobPosting.getActiveJobCount();
         assertEq(activeCount, 3);
     }

    function testPauseAndUnpauseContract() public {
        vm.startPrank(admin);
        jobPosting.pauseContract();
        assertTrue(jobPosting.paused());

        jobPosting.unpauseContract();
        assertFalse(jobPosting.paused());
        vm.stopPrank();
    }

    function testFailCreateJobWhenPaused() public {
        vm.prank(admin);
        jobPosting.pauseContract();

        vm.expectRevert("Pausable: paused");
        testCreateJob();
    }

    function testFailUnauthorizedActions() public {
        vm.expectRevert(
            "AccessControl: account 0x0000000000000000000000000000000000000001 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        vm.prank(client);
        jobPosting.pauseContract();

        vm.expectRevert("Only job client can perform this action");
        vm.prank(freelancer);
        jobPosting.cancelJob(0);

        vm.expectRevert(
            "AccessControl: account 0x0000000000000000000000000000000000000002 is missing role 0x3333f7ba63096e0feeff23993a70ebab9a83332c3d971c5a2f6f0e19d7a81792"
        );
        vm.prank(freelancer);
        jobPosting.resolveDispute(0, freelancer);
    }
}
