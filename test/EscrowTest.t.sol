// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/JobPosting.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract MockJobPosting {
    function getJob(
        uint256 _jobId
    ) external pure returns (JobPosting.Job memory) {
        return
            JobPosting.Job(
                _jobId,
                address(0),
                "",
                0,
                0,
                address(0),
                false,
                false,
                JobPosting.JobStatus.Posted,
                0,
                0
            );
    }
}

contract EscrowTest is Test {
    Escrow public escrow;
    MockERC20 public paymentToken;
    MockJobPosting public jobPosting;

    address public admin;
    address public escrowManager;
    address public client;
    address public freelancer;

    uint256 public constant JOB_ID = 1;
    uint256 public constant ESCROW_AMOUNT = 100 * 10 ** 18;

    event FundsDeposited(uint256 indexed jobId, uint256 amount);
    event FundsReleased(
        uint256 indexed jobId,
        address indexed freelancer,
        uint256 amount
    );
    event FundsRefunded(
        uint256 indexed jobId,
        address indexed client,
        uint256 amount
    );
    event DisputeInitiated(uint256 indexed jobId);
    event DisputeResolved(
        uint256 indexed jobId,
        address winner,
        uint256 amount
    );

    function setUp() public {
        admin = address(this);
        escrowManager = address(0x1);
        client = address(0x2);
        freelancer = address(0x3);

        paymentToken = new MockERC20();
        jobPosting = new MockJobPosting();
        escrow = new Escrow(address(paymentToken), address(jobPosting));

        // Set up roles
        escrow.grantRole(escrow.ESCROW_MANAGER_ROLE(), escrowManager);

        // Fund client with tokens
        paymentToken.transfer(client, 1000 * 10 ** 18);
    }

    function testCreateEscrow() public {
        vm.startPrank(escrowManager);
        vm.expectEmit(true, false, false, true);
        emit FundsDeposited(JOB_ID, ESCROW_AMOUNT);

        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );

        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
        vm.stopPrank();

        Escrow.EscrowAccount memory account = escrow.getEscrowDetails(JOB_ID);
        assertEq(account.balance, ESCROW_AMOUNT);
        assertEq(account.client, client);
        assertEq(account.freelancer, freelancer);
        assertEq(uint(account.status), uint(Escrow.EscrowStatus.Active));
    }

    function testFailCreateEscrowNonManager() public {
        vm.prank(client);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
    }

    function testFailCreateExistingEscrow() public {
        vm.startPrank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
        vm.stopPrank();
    }

    function testReleaseFunds() public {
        // Setup
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        // Test
        vm.prank(client);
        vm.expectEmit(true, true, false, true);
        emit FundsReleased(JOB_ID, freelancer, ESCROW_AMOUNT);

        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                freelancer,
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );

        escrow.releaseFunds(JOB_ID);

        Escrow.EscrowAccount memory account = escrow.getEscrowDetails(JOB_ID);
        assertEq(account.balance, 0);
        assertEq(account.isReleased, true);
        assertEq(uint(account.status), uint(Escrow.EscrowStatus.Released));
    }

    function testFailReleaseFundsNonClient() public {
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(freelancer);
        escrow.releaseFunds(JOB_ID);
    }

    function testRefundClient() public {
        // Setup
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        // Test
        vm.prank(escrowManager);
        vm.expectEmit(true, true, false, true);
        emit FundsRefunded(JOB_ID, client, ESCROW_AMOUNT);

        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                client,
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );

        escrow.refundClient(JOB_ID);

        Escrow.EscrowAccount memory account = escrow.getEscrowDetails(JOB_ID);
        assertEq(account.balance, 0);
        assertEq(uint(account.status), uint(Escrow.EscrowStatus.Refunded));
    }

    function testFailRefundClientNonManager() public {
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        escrow.refundClient(JOB_ID);
    }

    function testInitiateDispute() public {
        // Setup
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        // Test
        vm.prank(client);
        vm.expectEmit(true, false, false, false);
        emit DisputeInitiated(JOB_ID);
        escrow.initiateDispute(JOB_ID);

        Escrow.EscrowAccount memory account = escrow.getEscrowDetails(JOB_ID);
        assertEq(uint(account.status), uint(Escrow.EscrowStatus.Disputed));
    }

    function testResolveDispute() public {
        // Setup
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        escrow.initiateDispute(JOB_ID);

        // Test
        vm.prank(escrowManager);
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(JOB_ID, freelancer, ESCROW_AMOUNT);

        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                freelancer,
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );

        escrow.resolveDispute(JOB_ID, freelancer);

        Escrow.EscrowAccount memory account = escrow.getEscrowDetails(JOB_ID);
        assertEq(account.balance, 0);
        assertEq(uint(account.status), uint(Escrow.EscrowStatus.Released));
    }

    function testFailResolveDisputeNonManager() public {
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(client);
        escrow.initiateDispute(JOB_ID);

        vm.prank(client);
        escrow.resolveDispute(JOB_ID, freelancer);
    }

    function testAddFunds() public {
        // Setup
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        // Test
        uint256 additionalAmount = 50 * 10 ** 18;
        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit FundsDeposited(JOB_ID, additionalAmount);

        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                additionalAmount
            ),
            abi.encode(true)
        );

        escrow.addFunds(JOB_ID, additionalAmount);

        Escrow.EscrowAccount memory account = escrow.getEscrowDetails(JOB_ID);
        assertEq(account.balance, ESCROW_AMOUNT + additionalAmount);
    }

    function testFailAddFundsNonClient() public {
        vm.prank(escrowManager);
        vm.mockCall(
            address(paymentToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                client,
                address(escrow),
                ESCROW_AMOUNT
            ),
            abi.encode(true)
        );
        escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);

        vm.prank(freelancer);
        escrow.addFunds(JOB_ID, 50 * 10 ** 18);
    }

     function testPauseAndUnpause() public {
         vm.prank(admin);
         escrow.pauseContract();
         vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
         vm.prank(escrowManager);
         escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
         vm.prank(admin);
         escrow.unpauseContract();
         vm.prank(escrowManager);
         vm.mockCall(
             address(paymentToken),
             abi.encodeWithSelector(IERC20.transferFrom.selector, client, address(escrow), ESCROW_AMOUNT),
             abi.encode(true)
         );
         escrow.createEscrow(JOB_ID, client, freelancer, ESCROW_AMOUNT);
         Escrow.EscrowAccount memory account = escrow.getEscrowDetails(JOB_ID);
         assertEq(account.balance, ESCROW_AMOUNT);
     }

    function testFailPauseNonAdmin() public {
        vm.prank(client);
        escrow.pauseContract();
    }
}
