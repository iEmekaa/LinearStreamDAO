// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployStreamDAO} from "../script/DeployStreamDAO.s.sol";
import {StreamDAO} from "../src/StreamDAO.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 10000000000000e18);
    }
}

contract TestStreamDAO is Test {
    address owner = makeAddr("owner");
    address payer = makeAddr("payer");
    address recipient = makeAddr("recipient");
    uint256 constant INITIAL_SUPPLY = 100000000e18;

    event PayerAdded(address indexed payer);

    error MustBeAPayer();

    StreamDAO streamDAO;
    MockERC20 token;
    DeployStreamDAO deployer;

    function setUp() external {
        deployer = new DeployStreamDAO();
        streamDAO = deployer.run();

        vm.startPrank(owner);
        token = new MockERC20();
        token.approve(address(streamDAO), INITIAL_SUPPLY);
        vm.stopPrank();
    }

    function testOwnerisMsgSender() external view {
        assertEq(streamDAO.getOwner(), msg.sender);
    }

    function testOnlyOwnerCanAddPayer() external {
        vm.prank(payer);
        vm.expectRevert(StreamDAO.NotOwner.selector);
        streamDAO.addPayer(recipient);
    }

    function testAddPayer() external {
        vm.prank(msg.sender);
        streamDAO.addPayer(payer);
        if (!streamDAO.payers(payer)) revert MustBeAPayer();
        // address[] memory addedPayer = streamDAO.getPayers();
        // assertEq(addedPayer[0], payer);
        // assertEq(addedPayer.length, 1);
    }

    function testPayerCanCreateStream() external {
        vm.prank(msg.sender);
        streamDAO.addPayer(payer);
        vm.prank(owner);
        token.transfer(payer, INITIAL_SUPPLY);

        vm.startPrank(payer);
        token.approve(address(streamDAO), INITIAL_SUPPLY);

        streamDAO.createStream(
            1,
            recipient,
            address(token),
            INITIAL_SUPPLY,
            block.timestamp,
            block.timestamp + 30 days
        );
        (, , , , , bool isActive) = streamDAO.streamIds(payer, 1);
        assertTrue(isActive);
        vm.stopPrank();
    }

    function PayerCanCancelStream() external {
        vm.prank(msg.sender);
        streamDAO.addPayer(payer);

        vm.startPrank(payer);
        streamDAO.createStream(
            1,
            recipient,
            address(token),
            INITIAL_SUPPLY,
            block.timestamp,
            block.timestamp + 30 days
        );
        vm.warp(block.timestamp + 30 days);
        streamDAO.cancelstream(1, recipient, address(token));
        (, , , , , bool isActive) = streamDAO.streamIds(payer, 1);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function testOnlyPayerCanCancelStream() external {
        vm.prank(payer);
        vm.expectRevert(StreamDAO.MustBeAPayer.selector);
        streamDAO.cancelstream(1, recipient, address(token));
    }

    function testReceiverCanWithdraw() external {
        vm.prank(msg.sender);
        streamDAO.addPayer(payer);
        vm.prank(owner);
        token.transfer(payer, INITIAL_SUPPLY);

        vm.startPrank(payer);
        token.approve(address(streamDAO), INITIAL_SUPPLY);

        streamDAO.createStream(
            1,
            recipient,
            address(token),
            INITIAL_SUPPLY,
            block.timestamp,
            block.timestamp + 30 days
        );
        vm.stopPrank();
        vm.prank(recipient);
        vm.warp(block.timestamp + 30 days);
        streamDAO.withdraw(1, payer, address(token), 10e18);
        vm.assertEq(token.balanceOf(recipient), 10e18);
    }

    function testOnlyReceiverCanWithdraw() external {
        vm.prank(recipient);
        vm.expectRevert(StreamDAO.StreamNotActive.selector);
        streamDAO.withdraw(1, payer, address(token), 10e18);
    }

    function testEmitAddPayer() external {
        vm.prank(msg.sender);
        vm.expectEmit(true, true, true, true);
        emit PayerAdded(payer);

        streamDAO.addPayer(payer);
    }

    function testStreamLogic() external {
        uint256 amount = 100e18;
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;

        vm.warp(block.timestamp + 15 days);

        (uint256 amountDue, uint256 amountLeft) = streamDAO.streamLogic(
            amount,
            startTime,
            endTime
        );

        uint256 totalDuration = endTime - startTime;
        uint256 currentDuration = block.timestamp - startTime;
        uint256 expectedAmountDue = (amount * currentDuration) / totalDuration;
        uint256 expectedAmountLeft = amount - expectedAmountDue;

        assertEq(amountDue, expectedAmountDue);
        assertEq(amountLeft, expectedAmountLeft);
    }

    function testPayerCanGetStreamDetails() external {
        vm.prank(msg.sender);
        streamDAO.addPayer(payer);
        vm.prank(owner);
        token.transfer(payer, INITIAL_SUPPLY);

        vm.startPrank(payer);
        token.approve(address(streamDAO), INITIAL_SUPPLY);

        streamDAO.createStream(
            1,
            recipient,
            address(token),
            INITIAL_SUPPLY,
            block.timestamp,
            block.timestamp + 30 days
        );

        streamDAO.getStream(recipient, 1);
        (address _recipient, , uint256 _amount, , , bool _isActive) = streamDAO
            .streamIds(payer, 1);

        assertEq(_recipient, recipient);
        assertEq(_amount, INITIAL_SUPPLY);
        assertTrue(_isActive);
        vm.stopPrank();
    }
}
