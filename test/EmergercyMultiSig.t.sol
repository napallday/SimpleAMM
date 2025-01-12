// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import {EmergencyMultiSig} from "../src/EmergencyMultiSig.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IMultiSigExecutor} from "../src/interfaces/IMultiSigExecutor.sol";
import {MockMultiSigProposalExecutor} from "./mocks/MockMultiSigProposalExecutor.sol";

contract EmergencyMultiSigTest is Test {
    EmergencyMultiSig public multiSig;
    MockERC20 public token;
    MockMultiSigProposalExecutor public executor;

    address[] public signers;
    address public admin;
    address public nonSigner;
    uint256 public constant REQUIRED_APPROVALS = 2;

    event WithdrawalProposed(bytes32 indexed proposalId, address token, address to, uint256 amount, uint256 deadline);
    event WithdrawalApproved(bytes32 indexed proposalId, address approver);
    event WithdrawalExecuted(bytes32 indexed proposalId);

    function setUp() public {
        admin = makeAddr("admin");
        signers = new address[](3);
        signers[0] = makeAddr("signer1");
        signers[1] = makeAddr("signer2");
        signers[2] = makeAddr("signer3");
        nonSigner = makeAddr("nonSigner");

        vm.startPrank(admin);
        multiSig = new EmergencyMultiSig(signers, REQUIRED_APPROVALS);
        token = new MockERC20();
        executor = new MockMultiSigProposalExecutor();
        multiSig.setExecutor(address(executor));
        vm.stopPrank();
    }

    function test_Constructor() public view {
        // Test initial state
        assertTrue(multiSig.hasRole(multiSig.DEFAULT_ADMIN_ROLE(), admin));
        for (uint256 i = 0; i < signers.length; i++) {
            assertTrue(multiSig.hasRole(multiSig.SIGNER_ROLE(), signers[i]));
        }
        assertEq(multiSig.requiredApprovals(), REQUIRED_APPROVALS);
    }

    function test_ProposeWithdrawal() public {
        vm.startPrank(signers[0]);

        bytes32 proposalId = multiSig.proposeWithdrawal(address(token), address(this), 100);

        (address tokenAddr, address to, uint256 amount, uint256 deadline, uint256 approvals, bool executed) =
            multiSig.getProposalDetails(proposalId);
        vm.stopPrank();

        assertEq(tokenAddr, address(token));
        assertEq(to, address(this));
        assertEq(amount, 100);
        assertEq(deadline, block.timestamp + multiSig.PROPOSAL_DURATION());
        assertEq(approvals, 1); // Proposer auto-approves
        assertFalse(executed);
    }

    function test_ApproveWithdrawal() public {
        vm.startPrank(signers[0]);
        bytes32 proposalId = multiSig.proposeWithdrawal(address(token), address(this), 100);
        vm.stopPrank();

        vm.startPrank(signers[1]);
        multiSig.approveWithdrawal(proposalId);

        (,,,, uint256 approvals,) = multiSig.getProposalDetails(proposalId);
        assertEq(approvals, 2);
    }

    // cannot approve twice for one user
    function test_RevertIf_ApproveWithdrawalTwice() public {
        vm.startPrank(signers[0]);
        bytes32 proposalId = multiSig.proposeWithdrawal(address(token), address(this), 100);
        vm.stopPrank();

        vm.startPrank(signers[1]);
        multiSig.approveWithdrawal(proposalId);
        vm.expectRevert(EmergencyMultiSig.EmergencyMultiSig__ProposalAlreadyApproved.selector);
        multiSig.approveWithdrawal(proposalId);
        vm.stopPrank();
    }

    function test_RevertIf_ApprovalAfterProposal() public {
        vm.startPrank(signers[0]);
        bytes32 proposalId = multiSig.proposeWithdrawal(address(token), address(this), 100);
        // Try to approve again with same signer
        vm.expectRevert(EmergencyMultiSig.EmergencyMultiSig__ProposalAlreadyApproved.selector);
        multiSig.approveWithdrawal(proposalId);
        vm.stopPrank();
    }

    function test_ExecuteWithdrawal() public {
        vm.startPrank(signers[0]);
        bytes32 proposalId = multiSig.proposeWithdrawal(address(token), address(this), 100);
        vm.stopPrank();

        // Second signer approves
        vm.prank(signers[1]);
        multiSig.approveWithdrawal(proposalId);

        // Execute withdrawal
        vm.prank(admin);
        multiSig.executeWithdrawal(proposalId);

        // Verify proposal was executed
        (,,,,, bool executed) = multiSig.getProposalDetails(proposalId);
        assertTrue(executed);
    }

    function test_RevertIf_ProposalExpired() public {
        vm.startPrank(signers[0]);
        bytes32 proposalId = multiSig.proposeWithdrawal(address(token), address(this), 100);
        vm.stopPrank();

        // Fast forward past deadline
        vm.warp(block.timestamp + multiSig.PROPOSAL_DURATION() + 1);

        vm.prank(signers[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyMultiSig.EmergencyMultiSig__ProposalExpired.selector, block.timestamp - 1, block.timestamp
            )
        );
        multiSig.approveWithdrawal(proposalId);
    }

    function test_RevertIf_NonSignerProposal() public {
        vm.prank(nonSigner);
        vm.expectRevert();
        multiSig.proposeWithdrawal(address(token), address(this), 100);
    }

    function test_RevertIf_ExecuteWithoutSufficientApprovals() public {
        vm.startPrank(signers[0]);
        bytes32 proposalId = multiSig.proposeWithdrawal(address(token), address(this), 100);
        vm.stopPrank();

        // Try to execute without second approval
        vm.prank(admin);
        vm.expectRevert(EmergencyMultiSig.EmergencyMultiSig__InsufficientApprovals.selector);
        multiSig.executeWithdrawal(proposalId);
    }

    function test_RevertIf_InvalidRecipient() public {
        vm.startPrank(signers[0]);
        vm.expectRevert(EmergencyMultiSig.EmergencyMultiSig__InvalidRecipient.selector);
        multiSig.proposeWithdrawal(address(token), address(0), 100);
        vm.stopPrank();
    }

    function test_RevertIf_InvalidAmount() public {
        vm.startPrank(signers[0]);
        vm.expectRevert(EmergencyMultiSig.EmergencyMultiSig__InvalidAmount.selector);
        multiSig.proposeWithdrawal(address(token), address(this), 0);
        vm.stopPrank();
    }
}
