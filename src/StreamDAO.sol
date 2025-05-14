// SPDX-License-Identifier: MIT
// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StreamDAO
 * @author @iEmekaa
 * @notice A contract that lets someone stream ERC20 tokens to another address over time — like Sablier but simplified.
 * A payer creates a stream to a recipient
 * Tokens are released linearly over time (e.g., 100 tokens over 30 days)
 * The recipient can call withdraw() to claim what they’ve earned so far
 * The payer can cancel the stream anytime — remaining tokens are refunded, and recipient gets what they earned up to that point
 */

contract StreamDAO {
    error NotOwner();
    error AlreadyAPayer();
    error MustBeAPayer();
    error EnterAValidAmount();
    error EndTimeMustBeMoreThanStartTime();
    error TokenNotStreamed();
    error NotARecipient();
    error ETHTransferFailed();
    error AmountCannotBeZero();
    error StreamNotActive();
    error YouHaveInsufficientBalance();

    address private immutable i_owner;

    event PayerAdded(address indexed payer);
    event StreamCreated(
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        uint256 createdAt
    );
    event ETHStreamed(
        address indexed payer,
        uint256 amount,
        uint256 streamedAt
    );
    event StreamCancelled(
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 cancelledAt
    );
    event WithdrawCompleted(
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 withdrawnAt
    );

    modifier onlyOwner() {
        if (msg.sender != i_owner) revert NotOwner();
        _;
    }
    modifier onlyPayer() {
        if (!payers[msg.sender]) revert MustBeAPayer();
        _;
    }

    constructor() {
        i_owner = msg.sender;
    }

    struct Stream {
        address recipient;
        address token;
        uint256 amount;
        uint256 startTime; // must be in seconds
        uint256 endTime; // must be in seconds
        bool isActive;
    }

    mapping(address => bool) public payers;
    mapping(address => mapping(uint256 => Stream)) public streamIds;
    address[] private allPayers;

    function addPayer(address _payer) external onlyOwner {
        if (payers[_payer]) revert AlreadyAPayer();
        payers[_payer] = true;
        allPayers.push(_payer);
        emit PayerAdded(_payer);
    }

    function createStream(
        uint256 streamId,
        address _recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) external onlyPayer returns (Stream memory) {
        // must be a payer
        if (amount <= 0) revert EnterAValidAmount();
        if (endTime <= startTime) revert EndTimeMustBeMoreThanStartTime();
        Stream storage s = streamIds[msg.sender][streamId] = Stream({
            recipient: _recipient,
            token: token,
            amount: amount,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });
        // transfer token to contract
        if (token == address(0)) {
            _creditETHStream();
        } else {
            _creditERC20Stream(token, amount);
        }
        emit StreamCreated(
            msg.sender,
            _recipient,
            token,
            amount,
            startTime,
            endTime,
            block.timestamp
        );
        return s;
    }

    function cancelstream(
        uint256 streamId,
        address recipient,
        address token
    ) external onlyPayer {
        // must be a payer
        if (!streamIds[msg.sender][streamId].isActive) revert NotARecipient();
        if (streamIds[msg.sender][streamId].token != token)
            revert TokenNotStreamed();

        streamIds[msg.sender][streamId].isActive = false;
        streamIds[msg.sender][streamId].recipient = address(0);
        uint256 totalAmount = streamIds[msg.sender][streamId].amount;
        uint256 startTime = streamIds[msg.sender][streamId].startTime;
        uint256 endTime = streamIds[msg.sender][streamId].endTime;

        (uint256 amountDue, uint256 amountLeft) = streamLogic(
            totalAmount,
            startTime,
            endTime
        );
        // Transfers tokens respectively
        if (token == address(0)) {
            (bool success, ) = recipient.call{value: amountDue}("");
            if (!success) revert ETHTransferFailed();
            (bool success2, ) = msg.sender.call{value: amountLeft}("");
            if (!success2) revert ETHTransferFailed();
        } else {
            IERC20(token).transfer(msg.sender, amountLeft);
            IERC20(token).transfer(recipient, amountDue);
        }
        emit StreamCancelled(msg.sender, recipient, token, block.timestamp);
    }

    function withdraw(
        uint256 id,
        address payer,
        address token,
        uint256 amount
    ) external {
        // must be a recipient and token must be streamed
        if (!streamIds[payer][id].isActive) revert StreamNotActive();
        if (amount <= 0) revert AmountCannotBeZero();
        if (streamIds[payer][id].token != token) revert TokenNotStreamed();

        // confirm with the stream logic so they can withdraw what they've earned so far
        (uint256 amountDue, ) = streamLogic(
            streamIds[payer][id].amount,
            streamIds[payer][id].startTime,
            streamIds[payer][id].endTime
        );
        if (amount > amountDue) revert YouHaveInsufficientBalance();
        streamIds[payer][id].amount -= amount;
        if (streamIds[payer][id].amount == 0) {
            streamIds[payer][id].isActive = false;
        }
        if (token == address(0)) {
            withdrawETH(amount);
        } else {
            withdrawIERC20(token, amount);
        }
    }

    function getStream(
        address recipient,
        uint256 id
    ) external view onlyPayer returns (Stream memory) {
        // must be a payer
        // payer cannot view streams of other payers
        if (streamIds[msg.sender][id].recipient != recipient)
            revert NotARecipient();
        return streamIds[msg.sender][id];
    }

    function getPayers() external view onlyOwner returns (address[] memory) {
        // returns all players
        return allPayers;
    }

    function _creditETHStream() public payable returns (bool) {
        emit ETHStreamed(msg.sender, msg.value, block.timestamp);
        return true;
    }

    function _creditERC20Stream(address token, uint256 amount) internal {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function streamLogic(
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) public view returns (uint256 amountDue, uint256 amountLeft) {
        // no need to validate the start and end times as they would have already been validated in the cancelstream() and withdraw() functions
        uint256 totalduration = endTime - startTime;
        uint256 currentduration = block.timestamp - startTime;
        amountDue = (amount * currentduration) / totalduration;
        amountLeft = amount - amountDue;
    }

    function withdrawETH(uint256 amount) internal {
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    function withdrawIERC20(
        address token,
        uint256 amount
    ) internal returns (bool) {
        IERC20(token).transfer(msg.sender, amount);
        emit WithdrawCompleted(msg.sender, token, amount, block.timestamp);
        return true;
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }
}
