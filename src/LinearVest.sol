//Line 127

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// LinearVest is a contract that releases tokens to a recipient linearly over a specified period.
// For example, if 100 tokens are vested over 100 days, the recipient will receive 1 token per day.
// However, the vesting happens every second, so every update to the block.timestamp means the amount
// withdrawable is updated. The contract should track the amount of tokens the user has withdrawn so far.
// For example, if the vesting period is 4 hours, then after 1 hour, 1/4th of the tokens are withdrawable.

// Be careful to track the amount withdrawn per-vesting. The same user might have multiple vestings using
// the same token.

// Lifecycle:
// Sender deposits tokens into the contracts and creates a vest
// Receiver can withdraw their tokens at any time, but only up to the amount released
// The receiver can identify vests that belong to them by scanning for events that contain
// their address as the recipient

contract LinearVest {
    using SafeERC20 for IERC20;

    struct Vest {
        address token;
        uint40 startTime;
        address recipient;
        uint40 duration;
        uint256 amount;
        uint256 withdrawn;
    }

    mapping(bytes32 => Vest) public vests; // Again I think this should be clearly described on the mapping variable name bytes32 VestIds.
    bytes32[] public vestIds;

    // Events
    event VestCreated(
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 duration
    );

    event VestWithdrawn(
        address indexed recipient, bytes32 indexed vestId, address token, uint256 amount, uint256 timestamp
    );

    /*
     * @notice Creates a vest
     * @param token The token to vest
     * @param recipient The recipient of the vest
     * @param amount The amount of tokens to vest
     * @param startTime The start time of the vest in seconds
     * @param duration The duration of the vest in seconds
     * @param salt Allows for multiple vests to be created with the same parameters
     */
    function createVest(
        IERC20 token,
        address recipient,
        uint256 amount,
        uint40 startTime,
        uint40 duration,
        uint256 salt
    ) external {
        require(recipient != address(0), "bad recipient");
        require(amount > 0, "amount 0");
        require(duration > 0, "duration 0");
        require(address(token) != address(0), "bad token");
        require(startTime >= block.timestamp, "bad start");

        bytes32 vestId = computeVestId(token, recipient, amount, startTime, duration, salt);

        require(vests[vestId].amount == 0, "already exists");

        uint256 beforeBal = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBal = token.balanceOf(address(this));

        require(afterBal - beforeBal == amount, "fee on transfer");

        vests[vestId] = Vest({
            token: address(token),
            startTime: startTime,
            recipient: recipient,
            duration: duration,
            amount: amount,
            withdrawn: 0
        });

        vestIds.push(vestId);

        emit VestCreated(msg.sender, recipient, address(token), amount, startTime, duration);
    }

    /**
     * @notice Withdraws a vest
     * @param vestId The ID of the vest to withdraw
     * @param amount The amount to withdraw. If amount is greater than the amount withdrawable,
     * the amount withdrawable is withdrawn.
     */
    function withdrawVest(bytes32 vestId, uint256 amount) external {
        Vest storage vest = vests[vestId]; // Explain this. Answer: This creates a reference (pointer) to the vest mapping of the vestID we are working with which is stored in blockchain storage. I need to put storage because I am going to modify state and it needs to persist. If I were to put memory instead of storage, I would only be modifing the copy and it would stop existing after the transaction.

        require(vest.recipient == msg.sender, "not recipient");
        require(block.timestamp > vest.startTime, "not started");

        uint256 unlocked;

        if (block.timestamp <= vest.startTime) {
            unlocked = 0;
        } else if (block.timestamp >= vest.startTime + vest.duration) {
            unlocked = vest.amount;
        } else {
            uint256 elapsed = block.timestamp - vest.startTime;
            unlocked = (vest.amount * elapsed) / vest.duration; // Explain this: Is this format divisible? I am multiplying a uint256 vest.amount with an uint256 elapsedTime and dividing an uint40 vest.duration?
        }

        uint256 withdrawable = unlocked - vest.withdrawn;

        require(withdrawable > 0, "nothing");

        uint256 toWithdraw = amount > withdrawable ? withdrawable : amount; //Explain this expression

        vest.withdrawn += toWithdraw;

        IERC20(vest.token).safeTransfer(msg.sender, toWithdraw);

        emit VestWithdrawn(msg.sender, vestId, vest.token, toWithdraw, block.timestamp);
    }

    /*
     * @notice Computes the vest ID for a given vest
     * @param token The token to vest
     * @param recipient The recipient of the vest
     * @param amount The amount of tokens to vest
     * @param startTime The start time of the vest in seconds
     * @param duration The duration of the vest in seconds
     * @param salt Allows for multiple vests to be created with the same parameters
     * @return The vest ID, which is the keccak256 hash of the vest parameters
     */
    function computeVestId(
        IERC20 token,
        address recipient,
        uint256 amount,
        uint40 startTime,
        uint40 duration,
        uint256 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(token, recipient, amount, startTime, duration, salt));
    }
}
