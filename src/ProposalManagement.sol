// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import { UserManagement } from "../src/UserManagement.sol";
import { JobPosting } from "../src/JobPosting.sol";

contract ProposalManagement is Ownable, Pausable, ReentrancyGuard {
    UserManagement public userManagement;
    JobPosting public jobPosting;

    enum ProposalStatus { Pending, Accepted, Rejected, Withdrawn }

    struct Proposal {
        uint256 id;
        uint256 jobId;
        address freelancer;
        uint256 bidAmount;
        string proposalIPFSHash;
        uint256 deliveryTime;
        ProposalStatus status;
        uint256 createdAt;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => uint256[]) public jobToProposals;
    uint256 public proposalCounter;

    event ProposalSubmitted(uint256 indexed proposalId, uint256 indexed jobId, address indexed freelancer, uint256 bidAmount);
    event ProposalUpdated(uint256 indexed proposalId, uint256 newBidAmount, string newProposalIPFSHash, uint256 newDeliveryTime);
    event ProposalStatusChanged(uint256 indexed proposalId, ProposalStatus newStatus);

    modifier onlyFreelancer() {
        require(userManagement.getUser(msg.sender).isFreelancer, "Only freelancers can perform this action");
        _;
    }

    modifier onlyJobClient(uint256 _jobId) {
        require(jobPosting.getJob(_jobId).client == msg.sender, "Only the job client can perform this action");
        _;
    }

    modifier proposalExists(uint256 _proposalId) {
        require(_proposalId > 0 && _proposalId <= proposalCounter, "Proposal does not exist");
        _;
    }

    constructor(address _userManagementAddress, address _jobPostingAddress) Ownable(msg.sender) {
        userManagement = UserManagement(_userManagementAddress);
        jobPosting = JobPosting(_jobPostingAddress);
    }

    function submitProposal(uint256 _jobId, uint256 _bidAmount, string memory _proposalIPFSHash, uint256 _deliveryTime) 
        external 
        whenNotPaused 
        nonReentrant 
        onlyFreelancer 
    {
        require(userManagement.getUser(msg.sender).isActive, "Freelancer account is not active");
        require(jobPosting.getJob(_jobId).status == JobPosting.JobStatus.Posted, "Job is not open for proposals");
        require(_deliveryTime > block.timestamp, "Delivery time must be in the future");
        require(_bidAmount > 0, "Bid amount must be greater than zero");

        proposalCounter++;
        proposals[proposalCounter] = Proposal({
            id: proposalCounter,
            jobId: _jobId,
            freelancer: msg.sender,
            bidAmount: _bidAmount,
            proposalIPFSHash: _proposalIPFSHash,
            deliveryTime: _deliveryTime,
            status: ProposalStatus.Pending,
            createdAt: block.timestamp
        });

        jobToProposals[_jobId].push(proposalCounter);

        jobPosting.submitProposal(_jobId, msg.sender);

        emit ProposalSubmitted(proposalCounter, _jobId, msg.sender, _bidAmount);
    }

    function updateProposal(uint256 _proposalId, uint256 _newBidAmount, string memory _newProposalIPFSHash, uint256 _newDeliveryTime) 
        external 
        whenNotPaused 
        nonReentrant 
        proposalExists(_proposalId) 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.freelancer == msg.sender, "Only the proposal owner can update it");
        require(proposal.status == ProposalStatus.Pending, "Can only update pending proposals");
        require(jobPosting.getJob(proposal.jobId).status == JobPosting.JobStatus.Posted, "Associated job is no longer open");
        require(_newDeliveryTime > block.timestamp, "New delivery time must be in the future");
        require(_newBidAmount > 0, "New bid amount must be greater than zero");

        proposal.bidAmount = _newBidAmount;
        proposal.proposalIPFSHash = _newProposalIPFSHash;
        proposal.deliveryTime = _newDeliveryTime;

        emit ProposalUpdated(_proposalId, _newBidAmount, _newProposalIPFSHash, _newDeliveryTime);
    }

    function withdrawProposal(uint256 _proposalId) 
        external 
        whenNotPaused 
        nonReentrant 
        proposalExists(_proposalId) 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.freelancer == msg.sender, "Only the proposal owner can withdraw it");
        require(proposal.status == ProposalStatus.Pending, "Can only withdraw pending proposals");

        proposal.status = ProposalStatus.Withdrawn;
        emit ProposalStatusChanged(_proposalId, ProposalStatus.Withdrawn);
    }

    function acceptProposal(uint256 _proposalId) 
        external 
        whenNotPaused 
        nonReentrant 
        proposalExists(_proposalId) 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(jobPosting.getJob(proposal.jobId).client == msg.sender, "Only the job client can accept proposals");
        require(proposal.status == ProposalStatus.Pending, "Can only accept pending proposals");
        require(jobPosting.getJob(proposal.jobId).status == JobPosting.JobStatus.Posted, "Job is not open");

        proposal.status = ProposalStatus.Accepted;
        jobPosting.hireFreelancer(proposal.jobId, proposal.freelancer);
        // Reject all other proposals for this job
        uint256[] memory jobProposals = jobToProposals[proposal.jobId];
        for (uint256 i = 0; i < jobProposals.length; i++) {
            if (jobProposals[i] != _proposalId && proposals[jobProposals[i]].status == ProposalStatus.Pending) {
                proposals[jobProposals[i]].status = ProposalStatus.Rejected;
                emit ProposalStatusChanged(jobProposals[i], ProposalStatus.Rejected);
            }
        }

        emit ProposalStatusChanged(_proposalId, ProposalStatus.Accepted);
    }

    function getProposalsByJob(uint256 _jobId) external view returns (uint256[] memory) {
        return jobToProposals[_jobId];
    }

    function getProposalsByFreelancer(address _freelancer) external view returns (uint256[] memory) {
        uint256[] memory freelancerProposals = new uint256[](proposalCounter);
        uint256 count = 0;

        for (uint256 i = 1; i <= proposalCounter; i++) {
            if (proposals[i].freelancer == _freelancer) {
                freelancerProposals[count] = i;
                count++;
            }
        }

        // Resize the array to remove empty elements
        assembly {
            mstore(freelancerProposals, count)
        }

        return freelancerProposals;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}