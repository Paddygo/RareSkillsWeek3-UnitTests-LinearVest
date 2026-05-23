// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LinearVest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RareTokenERC20 is ERC20 {
    constructor() ERC20("RareToken", "RST") {

    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract RareTokenFeeOnTransfer is ERC20, Ownable(msg.sender) {
    constructor() ERC20("RareToken", "RST") {

    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
    
    function _update(address from, address to, uint256 value) internal override {
        uint256 valueNew = value * 1000 / 999;
        // fee is burned

        super._update(from, to, valueNew);
    }
}   

contract LinearVestTest is Test {
    LinearVest vest;
    RareTokenERC20 rareToken;

    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address chad = makeAddr("Chad");

    event VestCreated(
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 duration
    );

    function setUp() public {
        vest = new LinearVest();
        rareToken = new RareTokenERC20();
        rareToken.mint(alice, 100e18);
        vm.prank(alice);
        rareToken.approve(address(vest), 100e18);
    }

    function test_createVest_event() public {
        vm.expectEmit();
        emit VestCreated(alice, bob, address(rareToken), 100e18, block.timestamp + 1 days, 100 days);
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );
    }

    function test_createVest_alreadyExists() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        vm.expectRevert();
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );
    }

    function test_createVest_feeOnTransfer() public {
        RareTokenFeeOnTransfer rareTokenFeeOnTransfer = new RareTokenFeeOnTransfer();
        rareTokenFeeOnTransfer.mint(alice, 100e18);

        vm.prank(alice);
        rareTokenFeeOnTransfer.approve(address(vest), 100e18);

        vm.expectRevert();
        vm.prank(alice);
        vest.createVest(
            rareTokenFeeOnTransfer,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );
    }

    function test_createVestParameterSanity() public {
        vm.expectRevert();
        vm.prank(alice);
        vest.createVest(
            IERC20(address(0)),
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        vm.expectRevert();
        vm.prank(alice);
        vest.createVest(
            rareToken,
            address(0),
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        vm.expectRevert();
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            0,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        vm.expectRevert();
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp - 1 seconds),
            uint40(100 days),
            0
        );

        vm.expectRevert();
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(0),
            0
        );
    }

    function test_withdrawVestBeforeStartTime() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        bytes32 vestId = keccak256(abi.encode(address(rareToken), bob, 100e18, block.timestamp + 1 days, 100 days, 0));
        vm.expectRevert();
        vm.prank(bob);
        vest.withdrawVest(vestId, 0);
    }


    function test_fullVest() public {
        vm.prank(alice);    
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        bytes32 vestId = vest.computeVestId(rareToken, bob, 100e18, uint40(block.timestamp + 1 days), uint40(100 days), 0);

        vm.warp(block.timestamp + 101 days);
        vm.prank(bob);
        vest.withdrawVest(vestId, 100e18);

        assertEq(rareToken.balanceOf(bob), 100e18);
    }

    function test_withdrawVestPartial() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        bytes32 vestId = vest.computeVestId(rareToken, bob, 100e18, uint40(block.timestamp + 1 days), uint40(100 days), 0);
        vm.warp(block.timestamp + 51 days);
        vm.prank(bob);
        vest.withdrawVest(vestId, 50e18);

        assertEq(rareToken.balanceOf(bob), 50e18);
    }

    function test_withdrawVestPartialRequestFullAmount() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        bytes32 vestId = vest.computeVestId(rareToken, bob, 100e18, uint40(block.timestamp + 1 days), uint40(100 days), 0);
        vm.warp(block.timestamp + 51 days);
        vm.prank(bob);
        vest.withdrawVest(vestId, type(uint256).max);

        assertEq(rareToken.balanceOf(bob), 50e18);
    }

    function test_100SecondVest() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp),
            uint40(100 seconds),
            0
        );

        bytes32 vestId = vest.computeVestId(rareToken, bob, 100e18, uint40(block.timestamp), uint40(100 seconds), 0);
        vm.warp(block.timestamp + 1 seconds);
        vm.prank(bob);
        vest.withdrawVest(vestId, 100e18 / 100);

        assertEq(rareToken.balanceOf(bob), 1e18);
    }

    function test_100MinuteVest() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp),
            uint40(100 minutes),
            0
        );

        bytes32 vestId = vest.computeVestId(rareToken, bob, 100e18, uint40(block.timestamp), uint40(100 minutes), 0);
        vm.warp(block.timestamp + 2 minutes);
        vm.prank(bob);
        vest.withdrawVest(vestId, type(uint256).max);

        assertEq(rareToken.balanceOf(bob), 2e18);
    }

    function test_withdrawBeforeStart() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        bytes32 vestId = vest.computeVestId(rareToken, bob, 100e18, uint40(block.timestamp + 1 days), uint40(100 days), 0);
        vm.prank(bob);
        vm.expectRevert();
        vest.withdrawVest(vestId, 100e18);
    }

    function test_withdrawNotRecipient() public {
        vm.prank(alice);
        vest.createVest(
            rareToken,
            bob,
            100e18,
            uint40(block.timestamp + 1 days),
            uint40(100 days),
            0
        );

        bytes32 vestId = vest.computeVestId(rareToken, bob, 100e18, uint40(block.timestamp + 1 days), uint40(100 days), 0);
        vm.warp(block.timestamp + 101 days);
        vm.prank(chad);
        vm.expectRevert();
        vest.withdrawVest(vestId, 100e18);
    }
}