// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Vote for velocimeter pairs, get rewards and grow veFlow
interface IFlowVoteFarmer {
    /* ========== STATE VARIABLES ========== */
    /// @dev Role
    // bytes32 public constant STRATEGIST = keccak256("STRATEGIST");

    /// Fees
    /// Fee related constants:
    /// {USDC} - Fees are taken in USDC.
    /// {treasury} - Address to send fees to.
    /// {strategistRemitter} - Address where strategist fee is remitted to.
    /// {MAX_FEE} - Maximum fee allowed by the strategy. Hard-capped at 10%.
    /// {STRATEGIST_MAX_FEE} - Maximum strategist fee allowed by the strategy (as % of treasury fee).
    ///                        Hard-capped at 50%
    // address public constant USDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    // address public constant OP = address(0x4200000000000000000000000000000000000042);
    // address public treasury;
    // address public strategistRemitter;
    // uint256 public constant PERCENT_DIVISOR = 10_000;
    // uint256 public constant MAX_FEE = 1000;
    // uint256 public constant STRATEGIST_MAX_FEE = 5000;

    ///@dev Distribution of fees earned, expressed as % of the profit from each harvest.
    ///{totalFee} - divided by 10,000 to determine the % fee. Set to 4.5% by default and
    ///lowered as necessary to provide users with the most competitive APY.
    ///{callFee} - Percent of the totalFee reserved for the harvester (1000 = 10% of total fee: 0.45% by default)
    ///{treasuryFee} - Percent of the totalFee taken by maintainers of the software (9000 = 90% of total fee: 4.05% by default)
    ///{strategistFee} - Percent of the treasuryFee taken by strategist (2500 = 25% of treasury fee: 1.0125% by default)
    // uint256 public totalFee;
    // uint256 public callFee;
    // uint256 public treasuryFee;
    // uint256 public strategistFee;

    // uint256 public constant EPOCH = 1 weeks; // Duration of an epoch
    // uint256 public constant MAX_WEIGHT = 10_000; // 100% voting power
    // address public constant VELO = address(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);
    // address public constant VEVELO = address(0x9c7305eb78a432ced5C4D14Cac27E8Ed569A2e26);
    // address public constant VELODROME_VOTER = address(0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e);
    // address public constant VELODROME_ROUTER = address(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9);
    function tokenIds(uint256) external view returns (uint256);

    /// @dev Vote-related vars
    function gauges(uint256) external view returns (address);

    function pairs(uint256) external view returns (address);

    function weigths(uint256) external view returns (uint256);

    function tokenToRewardInfo(
        address
    ) external view returns (RewardInfo memory);

    struct VeNFTInfo {
        uint256 internalId;
        bool autoLock;
        mapping(address => uint256) tokenToRewardAmount; // Amount of reward received thanks to this veNft
    }

    /// Information about rewards
    struct RewardInfo {
        uint256 totalReceived; // Amount of tokens received as reward
        uint256 totalReceivedFlow; // How much the above was worth in flow
    }

    // function tokenIdToInfo(uint256) external view returns (VeNFTInfo memory);
    function veNfts(uint256) external view returns (uint256);

    function tokenIdsLength() external view returns (uint256);

    function nftCap() external view returns (uint256);

    /// @dev tokenA => (tokenB => swapPath config): returns best path to swap
    ///         tokenA to tokenB
    function swapPath(
        address,
        address
    ) external view returns (address[] memory);

    /// @notice Time required after initiating an upgrade to do so
    // uint256 public upgradeProposalTime;
    // uint256 public constant ONE_YEAR = 365 days;
    // uint256 public constant UPGRADE_TIMELOCK = 48 hours; // minimum 48 hours for RF

    function initialize() external;

    /// @notice Mimics the behaviour of harvests
    function harvest() external;

    /* ========== USER ACTIONS ========== */

    /// @notice Allows a user to add his venft to this contract's managed nfts
    /// @dev The contract must be approved for the transfer first
    function delegate(uint256 _tokenId, address _owner) external;

    /// @notice Allows a user to withdraw his venfts from the managed venfts
    function undelegate(uint256 _tokenId, address _owner) external;

    /// @notice Makes a venft eligible to have its lock duration extended by a week
    function autoLock(uint256 _tokenId, bool _enable, address _owner) external;

    /// @notice Extend duration of venfts
    /// @dev Be careful not to spam this
    function increaseDurationAll() external;

    /* ========== VOTE ========== */

    /// @notice Attempt to vote using all veNfts held by the contract
    function vote() external;

    /* ========== REWARDS ========== */

    /// @notice Attempt to claim for veNfts held
    function claimFees() external;

    /// @notice For each token, try to swap to FLOW
    /// @dev To prepare for the incoming compounding, should store the amount of flow gotten
    function swapRewards() external;

    /// @notice Distribute available FLOW to grow the veNfts
    /// @dev Flow for 1 veNft = (nftReward1Share * 1e18 / reward1ReceivedTotal) + ()
    function compoundFlow() external;

    function chargeFees() external returns (uint256 callerFee);

    /* ========== ADMIN ========== */

    /// @notice Set balances tracked to 0
    function resetBalancesAll() external;

    /// @notice Set balances tracked to 0 for array of tokens
    function resetBalances(uint256[] memory _tokenIds) external;

    /// @notice Set gauges and weights to use when voting and claiming
    function setGaugesAndWeights(
        address[] calldata _gauges,
        uint256[] calldata _weights
    ) external;

    /// @notice Set routes to be used for swaps
    function updateSwapPath(address[] memory _path) external;

    /// @dev Updates the total fee, capped at 5%; only DEFAULT_ADMIN_ROLE.
    function updateTotalFee(uint256 _totalFee) external;

    function updateFees(uint256 _callFee, uint256 _treasuryFee) external;

    /// @dev Updates the current strategistRemitter. Only DEFAULT_ADMIN_ROLE may do this.
    function updateStrategistRemitter(address _newStrategistRemitter) external;

    function addReward(address _reward) external;

    function removeReward(address _reward) external;

    function setNftCap(uint256 _cap) external;

    function synchronize() external;

    function pause() external;

    function unpause() external;

    function harvestLogLength() external view returns (uint256);

    function calculateAPRForLog(uint256) external view returns (uint256);

    function averageAPRAcrossLastNHarvests(
        uint256
    ) external view returns (uint256);

    function upgradeTo(address) external;
}
