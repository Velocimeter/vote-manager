// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "./IBribe.sol";

// Bribes pay out rewards for a given pool based on the votes that were received from the user (goes hand in hand with Voter.vote())
interface IExternalBribe is IBribe {
    // address public immutable voter; // only voter can modify balances (since it only happens on vote())
    // address public immutable _ve; // 天使のたまご

    // uint internal constant DURATION = 7 days; // rewards are released over the voting period
    // uint internal constant MAX_REWARD_TOKENS = 16;

    // uint internal constant PRECISION = 10 ** 18;

    // uint public totalSupply;
    // mapping(uint => uint) public balanceOf;
    // mapping(address => mapping(uint => uint)) public tokenRewardsPerEpoch;
    // mapping(address => uint) public periodFinish;
    // mapping(address => mapping(uint => uint)) public lastEarn;

    function rewards(uint256) external view returns (address);

    function isReward(address) external view returns (bool);

    /// @notice A checkpoint for marking balance
    struct Checkpoint {
        uint256 timestamp;
        uint256 balanceOf;
    }

    /// @notice A checkpoint for marking supply
    struct SupplyCheckpoint {
        uint256 timestamp;
        uint256 supply;
    }

    /// @notice A record of balance checkpoints for each account, by index
    // mapping (uint => mapping (uint => Checkpoint)) public checkpoints;
    /// @notice The number of checkpoints for each account
    // mapping (uint => uint) public numCheckpoints;
    /// @notice A record of balance checkpoints for each token, by index
    // mapping (uint => SupplyCheckpoint) public supplyCheckpoints;
    /// @notice The number of checkpoints
    // uint public supplyNumCheckpoints;

    function getEpochStart(uint256 timestamp) external pure returns (uint256);

    /**
     * @notice Determine the prior balance for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param tokenId The token of the NFT to check
     * @param timestamp The timestamp to get the balance at
     * @return The balance the account had as of the given block
     */
    function getPriorBalanceIndex(uint256 tokenId, uint256 timestamp) external view returns (uint256);

    function getPriorSupplyIndex(uint256 timestamp) external view returns (uint256);

    function rewardsListLength() external view returns (uint256);

    // returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable(address token) external view returns (uint256);

    // allows a user to claim rewards for a given token
    function getReward(uint256 tokenId, address[] memory tokens) external;

    // used by Voter to allow batched reward claims
    function getRewardForOwner(uint256 tokenId, address[] memory tokens) external;

    function earned(address token, uint256 tokenId) external view returns (uint256);

    // This is an external function, but internal notation is used since it can only be called "internally" from Gauges
    function _deposit(uint256 amount, uint256 tokenId) external;

    function _withdraw(uint256 amount, uint256 tokenId) external;

    function left(address token) external view returns (uint256);

    function notifyRewardAmount(address token, uint256 amount) external;

    function swapOutRewardToken(
        uint256 i,
        address oldToken,
        address newToken
    ) external;
}