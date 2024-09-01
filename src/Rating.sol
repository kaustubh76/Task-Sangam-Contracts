// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import { UserManagement } from "../src/UserManagement.sol";
import { JobPosting } from "../src/JobPosting.sol";

contract Rating is AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RATING_MANAGER_ROLE = keccak256("RATING_MANAGER_ROLE");

    struct RatingData {
        uint256 jobId;
        address rater;
        address rated;
        uint8 score;
        string comment;
        uint256 timestamp;
    }

    UserManagement public userManagement;
    JobPosting public jobPosting;

    mapping(uint256 => mapping(address => RatingData)) public jobRatings;
    mapping(address => RatingData[]) public userRatings;

    uint8 public constant MIN_RATING = 1;
    uint8 public constant MAX_RATING = 5;

    event RatingSubmitted(uint256 indexed jobId, address indexed rater, address indexed rated, uint8 score);

    constructor(address _userManagementAddress, address _jobPostingAddress) {
        userManagement = UserManagement(_userManagementAddress);
        jobPosting = JobPosting(_jobPostingAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(RATING_MANAGER_ROLE, msg.sender);
    }

    function submitRating(uint256 _jobId, address _rated, uint8 _score, string memory _comment) external whenNotPaused {
        require(_score >= MIN_RATING && _score <= MAX_RATING, "Invalid rating score");
        require(jobPosting.getJob(_jobId).status == JobPosting.JobStatus.Completed, "Job is not completed");
        require(
            msg.sender == jobPosting.getJob(_jobId).client || msg.sender == jobPosting.getJob(_jobId).hiredFreelancer,
            "Only job participants can submit ratings"
        );
        require(
            _rated == jobPosting.getJob(_jobId).client || _rated == jobPosting.getJob(_jobId).hiredFreelancer,
            "Invalid rated address"
        );
        require(msg.sender != _rated, "Cannot rate yourself");
        require(jobRatings[_jobId][msg.sender].timestamp == 0, "Rating already submitted for this job");

        RatingData memory newRating = RatingData({
            jobId: _jobId,
            rater: msg.sender,
            rated: _rated,
            score: _score,
            comment: _comment,
            timestamp: block.timestamp
        });

        jobRatings[_jobId][msg.sender] = newRating;
        userRatings[_rated].push(newRating);

        updateUserReputation(_rated);

        emit RatingSubmitted(_jobId, msg.sender, _rated, _score);
    }

    function updateUserReputation(address _user) internal {
        uint256 totalScore = 0;
        uint256 ratingCount = userRatings[_user].length;

        for (uint256 i = 0; i < ratingCount; i++) {
            totalScore += userRatings[_user][i].score;
        }

        if (ratingCount > 0) {
            uint256 averageScore = (totalScore * 100) / (ratingCount * MAX_RATING);
            userManagement.updateReputation(_user, averageScore);
        }
    }

    function getUserRatings(address _user) external view returns (RatingData[] memory) {
        return userRatings[_user];
    }

    function getJobRating(uint256 _jobId, address _rater) external view returns (RatingData memory) {
        return jobRatings[_jobId][_rater];
    }

    function pauseContract() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}