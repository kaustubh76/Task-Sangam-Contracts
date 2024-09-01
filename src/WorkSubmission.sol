// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {UserManagement} from "../src/UserManagement.sol";
import {JobPosting} from "../src/JobPosting.sol";
import {ProposalManagement} from "../src/ProposalManagement.sol";

contract WorkSubmission is Ownable, Pausable, ReentrancyGuard {
    UserManagement public userManagement;
    JobPosting public jobPosting;
    ProposalManagement public proposalManagement;

    enum SubmissionStatus {
        Pending,
        Approved,
        Rejected,
        Revised
    }

    struct Submission {
        uint256 id;
        uint256 jobId;
        address freelancer;
        string workIPFSHash;
        string commentIPFSHash;
        SubmissionStatus status;
        uint256 submittedAt;
    }

    mapping(uint256 => Submission[]) public jobSubmissions;
    uint256 public submissionCounter;

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
        SubmissionStatus newStatus
    );

    modifier onlyJobParticipants(uint256 _jobId) {
        require(
            jobPosting.getJob(_jobId).client == msg.sender ||
                jobPosting.getJob(_jobId).hiredFreelancer == msg.sender,
            "Only job participants can perform this action"
        );
        _;
    }

    modifier onlyJobClient(uint256 _jobId) {
        require(
            jobPosting.getJob(_jobId).client == msg.sender,
            "Only the job client can perform this action"
        );
        _;
    }

    modifier onlyJobFreelancer(uint256 _jobId) {
        require(
            jobPosting.getJob(_jobId).hiredFreelancer == msg.sender,
            "Only the hired freelancer can perform this action"
        );
        _;
    }

    constructor(
        address _userManagementAddress,
        address _jobPostingAddress,
        address _proposalManagementAddress
    ) Ownable(msg.sender) {
        userManagement = UserManagement(_userManagementAddress);
        jobPosting = JobPosting(_jobPostingAddress);
        proposalManagement = ProposalManagement(_proposalManagementAddress);
    }

    function submitWork(
        uint256 _jobId,
        string memory _workIPFSHash,
        string memory _commentIPFSHash
    ) external whenNotPaused nonReentrant onlyJobFreelancer(_jobId) {
        require(
            jobPosting.getJob(_jobId).status == JobPosting.JobStatus.InProgress,
            "Job is not in progress"
        );

        submissionCounter++;
        Submission memory newSubmission = Submission({
            id: submissionCounter,
            jobId: _jobId,
            freelancer: msg.sender,
            workIPFSHash: _workIPFSHash,
            commentIPFSHash: _commentIPFSHash,
            status: SubmissionStatus.Pending,
            submittedAt: block.timestamp
        });

        jobSubmissions[_jobId].push(newSubmission);

        emit WorkSubmitted(submissionCounter, _jobId, msg.sender);
    }

    function updateSubmission(
        uint256 _jobId,
        uint256 _submissionId,
        string memory _newWorkIPFSHash,
        string memory _newCommentIPFSHash
    ) external whenNotPaused nonReentrant onlyJobFreelancer(_jobId) {
        Submission[] storage submissions = jobSubmissions[_jobId];
        uint256 submissionIndex = findSubmissionIndex(
            submissions,
            _submissionId
        );
        require(submissionIndex < submissions.length, "Submission not found");
        require(
            submissions[submissionIndex].status == SubmissionStatus.Pending ||
                submissions[submissionIndex].status ==
                SubmissionStatus.Rejected,
            "Can only update pending or rejected submissions"
        );

        submissions[submissionIndex].workIPFSHash = _newWorkIPFSHash;
        submissions[submissionIndex].commentIPFSHash = _newCommentIPFSHash;
        submissions[submissionIndex].status = SubmissionStatus.Revised;
        submissions[submissionIndex].submittedAt = block.timestamp;

        emit SubmissionUpdated(
            _submissionId,
            _newWorkIPFSHash,
            _newCommentIPFSHash
        );
        emit SubmissionStatusChanged(_submissionId, SubmissionStatus.Revised);
    }

    function approveSubmission(
        uint256 _jobId,
        uint256 _submissionId
    ) external whenNotPaused nonReentrant onlyJobClient(_jobId) {
        Submission[] storage submissions = jobSubmissions[_jobId];
        uint256 submissionIndex = findSubmissionIndex(
            submissions,
            _submissionId
        );
        require(submissionIndex < submissions.length, "Submission not found");
        require(
            submissions[submissionIndex].status == SubmissionStatus.Pending ||
                submissions[submissionIndex].status == SubmissionStatus.Revised,
            "Can only approve pending or revised submissions"
        );

        submissions[submissionIndex].status = SubmissionStatus.Approved;
        jobPosting.completeJob(_jobId);

        emit SubmissionStatusChanged(_submissionId, SubmissionStatus.Approved);
    }

    function rejectSubmission(
        uint256 _jobId,
        uint256 _submissionId,
        string memory _feedbackIPFSHash
    ) external whenNotPaused nonReentrant onlyJobClient(_jobId) {
        Submission[] storage submissions = jobSubmissions[_jobId];
        uint256 submissionIndex = findSubmissionIndex(
            submissions,
            _submissionId
        );
        require(submissionIndex < submissions.length, "Submission not found");
        require(
            submissions[submissionIndex].status == SubmissionStatus.Pending ||
                submissions[submissionIndex].status == SubmissionStatus.Revised,
            "Can only reject pending or revised submissions"
        );

        submissions[submissionIndex].status = SubmissionStatus.Rejected;
        submissions[submissionIndex].commentIPFSHash = _feedbackIPFSHash;

        emit SubmissionStatusChanged(_submissionId, SubmissionStatus.Rejected);
    }

    function getJobSubmissions(
        uint256 _jobId
    ) external view returns (Submission[] memory) {
        return jobSubmissions[_jobId];
    }

    function findSubmissionIndex(
        Submission[] storage submissions,
        uint256 _submissionId
    ) internal view returns (uint256) {
        for (uint256 i = 0; i < submissions.length; i++) {
            if (submissions[i].id == _submissionId) {
                return i;
            }
        }
        return submissions.length;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
