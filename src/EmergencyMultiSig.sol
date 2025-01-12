// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import "./interfaces/IMultiSigExecutor.sol";

/**
 * @title EmergencyMultiSig
 * @notice Multi-signature wallet for emergency withdrawals with time-bound proposals
 * @dev Implements role-based access control with signers and admins
 */
contract EmergencyMultiSig is AccessControl, ReentrancyGuardTransient {
    // errors
    error EmergencyMultiSig__ZeroAddressSigner(address signer);
    error EmergencyMultiSig__InvalidRequiredApprovals(uint256 provided, uint256 maxAllowed);
    error EmergencyMultiSig__ProposalNotFound();
    error EmergencyMultiSig__ProposalAlreadyExecuted();
    error EmergencyMultiSig__ProposalExpired(uint256 deadline, uint256 timestamp);
    error EmergencyMultiSig__ProposalAlreadyApproved();
    error EmergencyMultiSig__InvalidRecipient();
    error EmergencyMultiSig__InvalidAmount();
    error EmergencyMultiSig__ProposalAlreadyExists();
    error EmergencyMultiSig__ProposalDoesNotExist();
    error EmergencyMultiSig__InsufficientApprovals();

    // Events
    /// @notice Emitted when new withdrawal proposal is created
    /// @param proposalId Unique identifier of the proposal
    /// @param token Address of token to withdraw (address(0) for ETH)
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    /// @param deadline Timestamp when proposal expires
    event WithdrawalProposed(
        bytes32 indexed proposalId, address indexed token, address to, uint256 amount, uint256 deadline
    );

    /// @notice Emitted when proposal receives an approval
    /// @param proposalId Unique identifier of the proposal
    /// @param approver Address of the signer who approved
    event WithdrawalApproved(bytes32 indexed proposalId, address indexed approver);

    /// @notice Emitted when proposal is executed
    /// @param proposalId Unique identifier of the executed proposal
    event WithdrawalExecuted(bytes32 indexed proposalId);

    /// @notice Emitted when proposal is cancelled
    /// @param proposalId Unique identifier of the cancelled proposal
    event WithdrawalCancelled(bytes32 indexed proposalId);

    // Constants
    /// @notice Role identifier for signers
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    /// @notice Duration before proposal expires
    uint256 public constant PROPOSAL_DURATION = 24 hours;

    // Immutables
    /// @notice Number of approvals required to execute proposal
    uint256 public immutable requiredApprovals;

    // structs

    /// @notice Structure containing proposal details
    /// @dev Uses mapping for approvals to save gas
    struct WithdrawalProposal {
        address token; // Token address to withdraw (address(0) for ETH)
        address to; // Recipient address
        uint256 amount; // Amount to withdraw
        uint256 deadline; // Proposal expiration timestamp
        uint256 approvals; // Number of approvals received
        bool executed; // Whether the proposal has been executed
        mapping(address => bool) hasApproved; // Track approvals from each signer
    }

    // State variables
    /// @notice Mapping from proposal ID to proposal details
    mapping(bytes32 => WithdrawalProposal) public proposals;
    /// @notice Interface to execute withdrawals
    IMultiSigExecutor public executor;

    /// @notice Initializes contract with initial signers and required approvals
    /// @param initialSigners Array of initial signer addresses
    /// @param _requiredApprovals Number of required approvals to execute
    /// @dev Validates that required approvals doesn't exceed signer count
    constructor(address[] memory initialSigners, uint256 _requiredApprovals) {
        if (_requiredApprovals == 0 || _requiredApprovals > initialSigners.length) {
            revert EmergencyMultiSig__InvalidRequiredApprovals(_requiredApprovals, initialSigners.length);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        for (uint256 i = 0; i < initialSigners.length; i++) {
            _grantRole(SIGNER_ROLE, initialSigners[i]);
        }

        requiredApprovals = _requiredApprovals;
    }

    /// @notice Sets the executor contract address
    /// @param _executor Address of executor contract
    /// @dev Can only be called by admin
    function setExecutor(address _executor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_executor == address(0)) revert EmergencyMultiSig__ZeroAddressSigner(_executor);
        executor = IMultiSigExecutor(_executor);
    }

    /// @notice Creates new withdrawal proposal
    /// @param token Address of token to withdraw (address(0) for ETH)
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    /// @return proposalId Unique identifier of created proposal
    /// @dev Proposer automatically approves the proposal
    function proposeWithdrawal(address token, address to, uint256 amount)
        external
        onlyRole(SIGNER_ROLE)
        returns (bytes32)
    {
        if (to == address(0)) revert EmergencyMultiSig__InvalidRecipient();
        if (amount == 0) revert EmergencyMultiSig__InvalidAmount();

        bytes32 proposalId = keccak256(abi.encode(token, to, amount, block.timestamp));

        WithdrawalProposal storage proposal = proposals[proposalId];
        if (proposal.deadline != 0) revert EmergencyMultiSig__ProposalAlreadyExists();

        proposal.token = token;
        proposal.to = to;
        proposal.amount = amount;
        proposal.deadline = block.timestamp + PROPOSAL_DURATION;
        proposal.approvals = 1; // Proposer automatically approves
        proposal.hasApproved[msg.sender] = true;

        emit WithdrawalProposed(proposalId, token, to, amount, proposal.deadline);
        emit WithdrawalApproved(proposalId, msg.sender);

        return proposalId;
    }

    /// @notice Approves an existing withdrawal proposal
    /// @param proposalId Unique identifier of proposal to approve
    /// @dev Reverts if proposal expired or already approved by signer
    function approveWithdrawal(bytes32 proposalId) external onlyRole(SIGNER_ROLE) {
        WithdrawalProposal storage proposal = proposals[proposalId];
        if (proposal.deadline == 0) revert EmergencyMultiSig__ProposalNotFound();
        if (proposal.executed) revert EmergencyMultiSig__ProposalAlreadyExecuted();
        if (block.timestamp >= proposal.deadline) {
            revert EmergencyMultiSig__ProposalExpired(proposal.deadline, block.timestamp);
        }
        if (proposal.hasApproved[msg.sender]) revert EmergencyMultiSig__ProposalAlreadyApproved();

        proposal.approvals += 1;
        proposal.hasApproved[msg.sender] = true;

        emit WithdrawalApproved(proposalId, msg.sender);
    }

    /// @notice Executes a proposal that has sufficient approvals
    /// @param proposalId Unique identifier of proposal to execute
    /// @dev Can only be called by admin, requires sufficient approvals
    function executeWithdrawal(bytes32 proposalId) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        WithdrawalProposal storage proposal = proposals[proposalId];
        if (proposal.deadline == 0) revert EmergencyMultiSig__ProposalDoesNotExist();
        if (proposal.executed) revert EmergencyMultiSig__ProposalAlreadyExecuted();
        if (block.timestamp >= proposal.deadline) {
            revert EmergencyMultiSig__ProposalExpired(proposal.deadline, block.timestamp);
        }
        if (proposal.approvals < requiredApprovals) revert EmergencyMultiSig__InsufficientApprovals();

        proposal.executed = true;

        // Call executor's emergencyWithdraw using the interface
        executor.executeEmergencyWithdraw(proposal.token, proposal.to, proposal.amount);

        emit WithdrawalExecuted(proposalId);
    }

    /// @notice Gets details of a specific proposal
    /// @param proposalId Unique identifier of proposal
    /// @return token Address of token to withdraw
    /// @return to Recipient address
    /// @return amount Amount to withdraw
    /// @return deadline Proposal expiration timestamp
    /// @return approvals Number of current approvals
    /// @return executed Whether proposal has been executed
    function getProposalDetails(bytes32 proposalId)
        external
        view
        returns (address token, address to, uint256 amount, uint256 deadline, uint256 approvals, bool executed)
    {
        WithdrawalProposal storage proposal = proposals[proposalId];
        return (proposal.token, proposal.to, proposal.amount, proposal.deadline, proposal.approvals, proposal.executed);
    }
}
