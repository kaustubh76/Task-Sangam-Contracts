// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ProposalManagement.sol";
import "../src/UserManagement.sol";
import "../src/JobPosting.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract ProposalManagementTest is Test {
    ProposalManagement public proposalManagement;
    UserManagement public userManagement;
    JobPosting public jobPosting;
    MockERC20 public paymentToken;

    address public owner;
    address public freelancer1;
    address public freelancer2;
    address public client;
    address public moderator;

    uint256 public constant JOB_ID = 0;

    function setUp() public {
        owner = address(this);
        freelancer1 = address(0x1);
        freelancer2 = address(0x2);
        client = address(0x3);
        moderator = address(0x4);

        paymentToken = new MockERC20();
        userManagement = new UserManagement();
        jobPosting = new JobPosting(
            address(userManagement),
            address(paymentToken)
        );
        proposalManagement = new ProposalManagement(
            address(userManagement),
            address(jobPosting)
        );
        jobPosting.setProposalManager(address(proposalManagement));

        vm.startPrank(owner);
        userManagement.grantRole(userManagement.ADMIN_ROLE(), owner);
        userManagement.grantRole(userManagement.MODERATOR_ROLE(), moderator);
        vm.stopPrank();

        vm.prank(freelancer1);
        userManagement.registerUser(true);

        vm.prank(freelancer2);
        userManagement.registerUser(true);

        vm.prank(client);
        userManagement.registerUser(false);

        paymentToken.transfer(client, 100 * 10 ** 18);

        vm.startPrank(client);
        paymentToken.approve(address(jobPosting), 10 * 10 ** 18);
        jobPosting.createJob(
            "ipfs://jobhash",
            10 * 10 ** 18,
            block.timestamp + 7 days
        );
        vm.stopPrank();
    }

    function testSubmitProposal() public {
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );

        (
            uint256 id,
            uint256 jobId,
            address freelancer,
            uint256 bidAmount,
            string memory proposalIPFSHash,
            uint256 deliveryTime,
            ProposalManagement.ProposalStatus status,

        ) = proposalManagement.proposals(1);

        assertEq(id, 1);
        assertEq(jobId, JOB_ID);
        assertEq(freelancer, freelancer1);
        assertEq(bidAmount, 9 * 10 ** 18);
        assertEq(proposalIPFSHash, "ipfs://proposalhash");
        assertEq(deliveryTime, block.timestamp + 5 days);
        assertEq(uint(status), uint(ProposalManagement.ProposalStatus.Pending));
    }

    function testFailSubmitProposalNonFreelancer() public {
        vm.prank(client);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );
    }

    function testFailSubmitProposalInvalidJob() public {
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            999,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );
    }

    function testUpdateProposal() public {
        vm.startPrank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );
        proposalManagement.updateProposal(
            1,
            8 * 10 ** 18,
            "ipfs://newhash",
            block.timestamp + 4 days
        );
        vm.stopPrank();

        (
            ,
            ,
            address freelancer,
            uint256 bidAmount,
            string memory proposalIPFSHash,
            uint256 deliveryTime,
            ,

        ) = proposalManagement.proposals(1);

        assertEq(freelancer, freelancer1);
        assertEq(bidAmount, 8 * 10 ** 18);
        assertEq(proposalIPFSHash, "ipfs://newhash");
        assertEq(deliveryTime, block.timestamp + 4 days);
    }

    function testFailUpdateProposalNonOwner() public {
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );

        vm.prank(freelancer2);
        proposalManagement.updateProposal(
            1,
            8 * 10 ** 18,
            "ipfs://newhash",
            block.timestamp + 4 days
        );
    }

    function testWithdrawProposal() public {
        vm.startPrank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );
        proposalManagement.withdrawProposal(1);
        vm.stopPrank();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ProposalManagement.ProposalStatus status,

        ) = proposalManagement.proposals(1);
        assertEq(
            uint(status),
            uint(ProposalManagement.ProposalStatus.Withdrawn)
        );
    }

    function testFailWithdrawProposalNonOwner() public {
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );

        vm.prank(freelancer2);
        proposalManagement.withdrawProposal(1);
    }

    function testAcceptProposal() public {
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );
        vm.prank(client);
        proposalManagement.acceptProposal(1);
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ProposalManagement.ProposalStatus status,

        ) = proposalManagement.proposals(1);
        assertEq(
            uint(status),
            uint(ProposalManagement.ProposalStatus.Accepted)
        );
        JobPosting.Job memory job = jobPosting.getJob(JOB_ID);
        assertEq(job.hiredFreelancer, freelancer1);
        assertEq(uint(job.status), uint(JobPosting.JobStatus.InProgress));
    }

    function testFailAcceptProposalNonClient() public {
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );

        vm.prank(freelancer2);
        proposalManagement.acceptProposal(1);
    }

    function testGetProposalsByJob() public {
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash1",
            block.timestamp + 5 days
        );

        vm.prank(freelancer2);
        proposalManagement.submitProposal(
            JOB_ID,
            8 * 10 ** 18,
            "ipfs://proposalhash2",
            block.timestamp + 4 days
        );

        uint256[] memory proposals = proposalManagement.getProposalsByJob(
            JOB_ID
        );
        assertEq(proposals.length, 2);
        assertEq(proposals[0], 1);
        assertEq(proposals[1], 2);
    }

    function testGetProposalsByFreelancer() public {
        vm.startPrank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash1",
            block.timestamp + 5 days
        );

        // Create another job for testing
        vm.stopPrank();
        vm.startPrank(client);
        paymentToken.approve(address(jobPosting), 15 * 10 ** 18);
        jobPosting.createJob(
            "ipfs://jobhash2",
            15 * 10 ** 18,
            block.timestamp + 14 days
        );
        vm.stopPrank();

        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            1,
            14 * 10 ** 18,
            "ipfs://proposalhash2",
            block.timestamp + 10 days
        );

        uint256[] memory proposals = proposalManagement
            .getProposalsByFreelancer(freelancer1);
        assertEq(proposals.length, 2);
        assertEq(proposals[0], 1);
        assertEq(proposals[1], 2);
    }

    function testPauseAndUnpause() public {
        vm.prank(owner);
        proposalManagement.pause();
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );
        proposalManagement.unpause();
        vm.stopPrank();
        vm.prank(freelancer1);
        proposalManagement.submitProposal(
            JOB_ID,
            9 * 10 ** 18,
            "ipfs://proposalhash",
            block.timestamp + 5 days
        );
        (uint256 id, , , , , , , ) = proposalManagement.proposals(1);
        assertEq(id, 1);
    }

    function testFailPauseNonOwner() public {
        vm.prank(freelancer1);
        proposalManagement.pause();
    }
}
