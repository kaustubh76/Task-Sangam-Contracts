// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Rating.sol";
import "../src/UserManagement.sol";
import "../src/JobPosting.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    function mint(address account, uint256 amount) public {
        _totalSupply += amount;
        _balances[account] += amount;
    }
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
}
contract RatingTest is Test {
    Rating public rating;
    UserManagement public userManagement;
    JobPosting public jobPosting;
    MockERC20 public paymentToken;
    address public admin = address(1);
    address public client = address(2);
    address public freelancer = address(3);
    address public ratingManager = address(4);
    uint256 public constant JOB_BUDGET = 1000 * 1e18;
    uint256 public constant JOB_DURATION = 30 days;
    function setUp() public {
        vm.startPrank(admin);
        paymentToken = new MockERC20();
        paymentToken.mint(address(this), 1_000_000_000 * 1e18);
        paymentToken.mint(client, 1000000 * 1e18);
        userManagement = new UserManagement();
        jobPosting = new JobPosting(
            address(userManagement),
            address(paymentToken)
        );
        rating = new Rating(address(userManagement), address(jobPosting));
        userManagement.grantRole(
            userManagement.MODERATOR_ROLE(),
            address(jobPosting)
        );
        userManagement.grantRole(
            userManagement.MODERATOR_ROLE(),
            address(rating)
        );
        rating.grantRole(rating.RATING_MANAGER_ROLE(), ratingManager);
        vm.stopPrank();
        // Setup users
        vm.prank(client);
        userManagement.registerUser(false);
        vm.prank(freelancer);
        userManagement.registerUser(true);
        // Mint tokens for client
        paymentToken.mint(client, JOB_BUDGET);
    }
    function testSubmitRating() public {
        uint256 jobId = _createAndCompleteJob();
        vm.prank(client);
        rating.submitRating(jobId, freelancer, 4, "Good job");
        Rating.RatingData memory ratingData = rating.getJobRating(
            jobId,
            client
        );
        assertEq(ratingData.rater, client);
        assertEq(ratingData.rated, freelancer);
        assertEq(ratingData.score, 4);
        assertEq(ratingData.comment, "Good job");
    }
    function testSubmitRatingInvalidScore() public {
        uint256 jobId = _createAndCompleteJob();
        vm.prank(client);
        vm.expectRevert("Invalid rating score");
        rating.submitRating(jobId, freelancer, 0, "Invalid score");
        vm.prank(client);
        vm.expectRevert("Invalid rating score");
        rating.submitRating(jobId, freelancer, 6, "Invalid score");
    }
    function testSubmitRatingJobNotCompleted() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert("Job is not completed");
        rating.submitRating(jobId, freelancer, 4, "Job not completed");
    }
    function testSubmitRatingNonParticipant() public {
        uint256 jobId = _createAndCompleteJob();
        address nonParticipant = address(5);
        vm.prank(nonParticipant);
        vm.expectRevert("Only job participants can submit ratings");
        rating.submitRating(jobId, freelancer, 4, "Non-participant rating");
    }
    function testSubmitRatingInvalidRated() public {
        uint256 jobId = _createAndCompleteJob();
        address invalidRated = address(5);
        vm.prank(client);
        vm.expectRevert("Invalid rated address");
        rating.submitRating(jobId, invalidRated, 4, "Invalid rated address");
    }
    function testSubmitRatingSelf() public {
        uint256 jobId = _createAndCompleteJob();
        vm.prank(client);
        vm.expectRevert("Cannot rate yourself");
        rating.submitRating(jobId, client, 4, "Self-rating");
    }
    function testSubmitRatingTwice() public {
        uint256 jobId = _createAndCompleteJob();
        vm.startPrank(client);
        rating.submitRating(jobId, freelancer, 4, "First rating");
        vm.expectRevert("Rating already submitted for this job");
        rating.submitRating(jobId, freelancer, 5, "Second rating");
        vm.stopPrank();
    }
    function testUpdateUserReputation() public {
        uint256 jobId1 = _createAndCompleteJob();
        uint256 jobId2 = _createAndCompleteJob();
        vm.prank(client);
        rating.submitRating(jobId1, freelancer, 4, "Good job");
        vm.prank(client);
        rating.submitRating(jobId2, freelancer, 5, "Excellent job");
        UserManagement.User memory freelancerData = userManagement.getUser(
            freelancer
        );
        assertEq(freelancerData.reputation, 90); // (4 + 5) * 100 / (2 * 5) = 90
    }
    function testGetUserRatings() public {
        uint256 jobId1 = _createAndCompleteJob();
        uint256 jobId2 = _createAndCompleteJob();
        vm.prank(client);
        rating.submitRating(jobId1, freelancer, 4, "Good job");
        vm.prank(client);
        rating.submitRating(jobId2, freelancer, 5, "Excellent job");
        Rating.RatingData[] memory ratings = rating.getUserRatings(freelancer);
        assertEq(ratings.length, 2);
        assertEq(ratings[0].score, 4);
        assertEq(ratings[1].score, 5);
    }
    function testPauseContract() public {
        vm.prank(admin);
        rating.pauseContract();
        uint256 jobId = _createAndCompleteJob();
        vm.prank(client);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        rating.submitRating(jobId, freelancer, 4, "Paused contract");
    }
    function testUnpauseContract() public {
        vm.startPrank(admin);
        rating.pauseContract();
        rating.unpauseContract();
        vm.stopPrank();
        uint256 jobId = _createAndCompleteJob();
        vm.prank(client);
        rating.submitRating(jobId, freelancer, 4, "Unpaused contract");
        Rating.RatingData memory ratingData = rating.getJobRating(
            jobId,
            client
        );
        assertEq(ratingData.score, 4);
    }
    function _createJob() internal returns (uint256) {
        vm.startPrank(client);
        paymentToken.approve(address(jobPosting), JOB_BUDGET);
        jobPosting.createJob(
            "ipfs://job-description",
            JOB_BUDGET,
            block.timestamp + JOB_DURATION
        );
        uint256 jobId = jobPosting.getAllJobsCounter() - 1;
        vm.stopPrank();
        vm.prank(freelancer);
        jobPosting.submitProposal(jobId, freelancer);
        vm.prank(client);
        jobPosting.hireFreelancer(jobId, freelancer);
        return jobId;
    }
    function _createAndCompleteJob() internal returns (uint256) {
        uint256 jobId = _createJob();
        vm.prank(client);
        jobPosting.completeJob(jobId);
        return jobId;
    }
}
