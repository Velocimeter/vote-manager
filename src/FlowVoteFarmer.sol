// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "./interfaces/IFlowVoteManager.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IExternalBribe.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IGauge.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

error FlowVoteFarmer__Unauthorized();
error FlowVoteFarmer__WrongInput();
error FlowVoteFarmer__VoteCooldown();
error FlowVoteFarmer__TokenExpiresTooEarly();
error FlowVoteFarmer__OverNftCap();

/// @dev Vote for VELOCIMETER pairs, get rewards and grow veFlow
contract FlowVoteFarmer is
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /* ========== STATE VARIABLES ========== */
    /// @dev Role
    bytes32 public constant MANAGER = keccak256("MANAGER");

    /// Fees
    /// Fee related constants:
    /// {USDC} - Fees are taken in USDC.
    /// {treasury} - Address to send fees to.
    /// {strategistRemitter} - Address where strategist fee is remitted to.
    /// {MAX_FEE} - Maximum fee allowed by the strategy. Hard-capped at 10%.
    /// {STRATEGIST_MAX_FEE} - Maximum strategist fee allowed by the strategy (as % of treasury fee).
    ///                        Hard-capped at 50%
    address public constant USDC =
        address(0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd);
    address public constant WCANTO =
        address(0x826551890Dc65655a0Aceca109aB11AbDbD7a07B);
    address public treasury;
    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public constant MAX_FEE = 1000;

    /// @dev Distribution of fees earned, expressed as % of the profit from each harvest.
    /// {totalFee} - divided by 10,000 to determine the % fee.
    uint256 public totalFee;

    /// over-arching conract managing all strategies
    IFlowVoteManager public manager;

    struct Harvest {
        uint256 timestamp;
        uint256 flowBefore;
        uint256 votingPowerBefore;
        uint256 flowAfter;
        uint256 votingPowerAfter;
    }

    Harvest[] harvestLog;

    uint256 public constant EPOCH = 1 weeks; // Duration of an epoch
    address public constant FLOW = 0xB5b060055F0d1eF5174329913ef861bC3aDdF029;
    address public constant VEFLOW = 0x8E003242406FBa53619769F31606ef2Ed8A65C00;
    IVoter public constant VELOCIMETER_VOTER =
        IVoter(0x8e3525Dbc8356c08d2d55F3ACb6416b5979D3389);
    address public constant VELOCIMETER_ROUTER =
        0x8e2e2f70B4bD86F82539187A634FB832398cc771;
    IRewardsDistributor public constant VELOCIMETER_REWARDS_DISTRIBUTOR =
        IRewardsDistributor(0x73278a66b75aC0714c4B049dFF26e5CddF365c85);

    /// @dev Vote-related vars
    address[] public gauges;
    address[] public pairs;
    uint256[] public weights;
    mapping(address => RewardInfo) tokenToRewardInfo;

    struct VeNFTInfo {
        uint256 veNftIdx;
        bool autoLock;
        mapping(address => uint256) tokenToRewardAmount; // Amount of reward received thanks to this veNft
    }

    /// Information about rewards
    struct RewardInfo {
        uint256 totalReceived; // Amount of tokens received as reward
        uint256 totalReceivedFlow; // How much the above was worth in flow
    }

    mapping(uint256 => VeNFTInfo) public tokenIdToInfo;
    uint256[] public tokenIds;
    uint256 public nftCap;

    /// @dev tokenA => (tokenB => swapPath config): returns best path to swap
    ///         tokenA to tokenB
    mapping(address => mapping(address => address[])) public swapPath;
    EnumerableSetUpgradeable.AddressSet private rewards; // Rewards (to swap to Flow)

    /// @notice Time required after initiating an upgrade to do so
    uint256 public upgradeProposalTime;
    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant UPGRADE_TIMELOCK = 48 hours; // minimum 48 hours for RF

    /* ========== CONSTRUCTOR ========== */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __FlowVoteFarmer_init() internal onlyInitializing {
        __UUPSUpgradeable_init();
        __AccessControlEnumerable_init();
        __Pausable_init_unchained();
        _grantRole(MANAGER, msg.sender);
    }

    function initialize() public initializer {
        __FlowVoteFarmer_init();
        manager = IFlowVoteManager(msg.sender);

        // Somewhat unsafe, saves gas
        IERC20Upgradeable(FLOW).safeIncreaseAllowance(
            VEFLOW,
            type(uint256).max
        );
    }

    /// @notice Mimics the behaviour of harvests
    function harvest() external onlyRole(MANAGER) {
        _removeRevokedNfts();
        uint256 timestamp = block.timestamp;
        (uint256 balanceBefore, uint256 votingPowerBefore) = _getFlowBalance();
        increaseDurationAll();
        claimFees();
        swapRewards(); //into flow
        chargeFees(); //charge fees on flow
        compoundFlow(); //deposits proper flow into veNFTs
        rebase();
        (uint256 balanceAfter, uint256 votingPowerAfter) = _getFlowBalance();
        harvestLog.push(
            Harvest(
                timestamp,
                balanceBefore,
                votingPowerBefore,
                balanceAfter,
                votingPowerAfter
            )
        );
    }

    function tokenIdsLength() external view returns (uint256) {
        return tokenIds.length;
    }

    function harvestLogLength() external view returns (uint256) {
        return harvestLog.length;
    }

    /// @dev Traverses the harvest log backwards _n items,
    ///      and returns the average APR calculated across all the included
    ///      log entries. APR is multiplied by PERCENT_DIVISOR to retain precision.
    function averageAPRAcrossLastNHarvests(
        uint256 _n
    ) external view returns (uint256) {
        uint256 runningAPRSum;
        uint256 numLogsProcessed;

        for (
            uint256 i = harvestLog.length - 1;
            i >= 0 && numLogsProcessed < _n;
            i--
        ) {
            runningAPRSum += calculateAPRForLog(i);
            numLogsProcessed++;
            if (i == 0) {
                break;
            }
        }
        return runningAPRSum / numLogsProcessed;
    }

    function calculateAPRForLog(
        uint256 _index
    ) public view returns (uint256 yearly) {
        Harvest storage log = harvestLog[_index];

        uint256 increase = log.votingPowerAfter - log.votingPowerBefore;
        uint256 increasePercentage = (increase * PERCENT_DIVISOR) /
            log.votingPowerBefore;

        yearly = (increasePercentage * ONE_YEAR) / EPOCH;
    }

    /* ========== USER ACTIONS ========== */

    /// @notice Allows a user to add his venft to this contract's managed nfts
    /// @dev The contract must be approved for the transfer first
    function delegate(
        uint256 _tokenId,
        address _owner
    ) external whenNotPaused onlyRole(MANAGER) {
        _requireMinimumLockDuration(_tokenId);
        _requireOwnerOf(_tokenId, _owner);
        if (!IVotingEscrow(VEFLOW).isApprovedOrOwner(address(this), _tokenId)) {
            revert FlowVoteFarmer__Unauthorized();
        }
        if (tokenIds.length >= nftCap) {
            revert FlowVoteFarmer__OverNftCap();
        }
        tokenIdToInfo[_tokenId].veNftIdx = tokenIds.length;
        tokenIds.push(_tokenId);
    }

    /// @notice Allows a user to withdraw his venfts from the managed venfts
    function undelegate(
        uint256 _withdrawTokenId,
        address _owner
    ) external onlyRole(MANAGER) {
        _requireOwnerOf(_withdrawTokenId, _owner);
        uint256 withdrawVeNftIdx = tokenIdToInfo[_withdrawTokenId].veNftIdx;
        uint256 lastTokenId = tokenIds[tokenIds.length - 1];

        tokenIdToInfo[lastTokenId].veNftIdx = withdrawVeNftIdx;
        tokenIds[withdrawVeNftIdx] = lastTokenId;
        tokenIds.pop();
        delete tokenIdToInfo[_withdrawTokenId];
    }

    /// @notice Makes a venft eligible to have its lock duration extended by a week
    function autoLock(
        uint256 _tokenId,
        bool _enable,
        address _owner
    ) external onlyRole(MANAGER) {
        _requireOwnerOf(_tokenId, _owner);
        tokenIdToInfo[_tokenId].autoLock = _enable;
    }

    /// @notice Extend duration of venfts
    /// @dev Be careful not to spam this
    function increaseDurationAll() public onlyRole(MANAGER) {
        for (uint256 i; i < tokenIds.length; i = _uncheckedInc(i)) {
            if (tokenIdToInfo[tokenIds[i]].autoLock) {
                _increaseDuration(tokenIds[i]);
            }
        }
    }

    /* ========== VOTE ========== */

    /// @notice Attempt to vote using all veNfts held by the contract
    function vote() public whenNotPaused onlyRole(MANAGER) {
        _removeRevokedNfts();
        for (uint256 i; i < tokenIds.length; i = _uncheckedInc(i)) {
            _vote(tokenIds[i], pairs, weights);
        }
    }

    /* ========== REWARDS ========== */

    /// @notice Attempt to claim for veNfts held
    function claimFees() public whenNotPaused onlyRole(MANAGER) {
        for (uint256 i; i < tokenIds.length; i = _uncheckedInc(i)) {
            _claimFees(tokenIds[i]);
        }
    }

    /// @notice For each token, try to swap to FLOW
    /// @dev To prepare for the incoming compounding, should store the amount of flow gotten
    function swapRewards() public onlyRole(MANAGER) {
        uint256 rewardBal;
        uint256 flowBalBefore;
        uint256 flowBalAfter;
        for (uint256 i; i < rewards.length(); i = _uncheckedInc(i)) {
            rewardBal = IERC20Upgradeable(rewards.at(i)).balanceOf(
                address(this)
            );
            flowBalBefore = IERC20Upgradeable(FLOW).balanceOf(address(this));
            _swap(rewards.at(i), FLOW, rewardBal);
            flowBalAfter = IERC20Upgradeable(FLOW).balanceOf(address(this));
            tokenToRewardInfo[rewards.at(i)].totalReceivedFlow =
                flowBalAfter -
                flowBalBefore;
        }
    }

    /// @notice Distribute available FLOW to grow the veNfts
    /// @dev Flow for 1 veNft = (nftReward1Share * 1e18 / reward1ReceivedTotal) + ()
    function compoundFlow() public onlyRole(MANAGER) {
        uint256 veNftRewardShare;
        uint256 totalReward;
        uint256 totalRewardFlow;
        uint256 veNftTotalFlow;

        for (uint256 i; i < tokenIds.length; i = _uncheckedInc(i)) {
            for (uint256 j = 0; j < rewards.length(); j = _uncheckedInc(j)) {
                //individual veNFT reward amount expressed in rewardToken
                veNftRewardShare = tokenIdToInfo[tokenIds[i]]
                    .tokenToRewardAmount[rewards.at(j)];
                //total amount of reward expressed in rewardToken
                totalReward = tokenToRewardInfo[rewards.at(j)].totalReceived;
                //total amount of reward expressed in flow
                totalRewardFlow = tokenToRewardInfo[rewards.at(j)]
                    .totalReceivedFlow;
                if (totalReward != 0) {
                    veNftTotalFlow +=
                        (veNftRewardShare * totalRewardFlow) /
                        totalReward;
                }
            }
            if (veNftTotalFlow != 0) {
                IVotingEscrow(VEFLOW).increase_amount(
                    tokenIds[i],
                    veNftTotalFlow
                );
                veNftTotalFlow = 0;
            }
        }
    }

    function rebase() public onlyRole(MANAGER) {
        VELOCIMETER_REWARDS_DISTRIBUTOR.claim_many(tokenIds);
    }

    function chargeFees() public onlyRole(MANAGER) {
        _chargeFees();
    }

    /* ========== ADMIN ========== */

    /// @notice Set balances tracked to 0
    function resetBalancesAll() external onlyRole(MANAGER) {
        for (uint256 i; i < rewards.length(); i = _uncheckedInc(i)) {
            for (uint256 j; j < tokenIds.length; j = _uncheckedInc(j)) {
                tokenIdToInfo[tokenIds[j]].tokenToRewardAmount[
                    rewards.at(i)
                ] = 0;
            }
            tokenToRewardInfo[rewards.at(i)].totalReceived = 0;
            tokenToRewardInfo[rewards.at(i)].totalReceivedFlow = 0;
        }
    }

    function synchronize() external onlyRole(MANAGER) {
        delete gauges;
        delete pairs;
        delete weights;
        // Set values
        treasury = manager.treasury();
        totalFee = manager.totalFee();
        nftCap = manager.nftCap();
        uint256 gaugesLength = manager.gaugesLength();

        // Derived values
        for (uint256 i; i < gaugesLength; i = _uncheckedInc(i)) {
            gauges.push(manager.gauges(i));
            weights.push(manager.weights(i));
            pairs.push(IGauge(gauges[i]).stake());
        }
        // Rewards from getRewards + swap path from rewards to FLOW
        address[] memory rewardsArray = manager.getRewards();
        for (uint256 i; i < rewardsArray.length; i = _uncheckedInc(i)) {
            rewards.add(rewardsArray[i]);
            swapPath[rewardsArray[i]][FLOW] = manager.getSwapPath(
                rewardsArray[i],
                FLOW
            );
        }

        // Swap path from FLOW to USDC
        swapPath[FLOW][USDC] = manager.getSwapPath(FLOW, USDC);
    }

    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    function unpause() external onlyRole(MANAGER) {
        _unpause();
    }

    /* ========== INTERNAL ========== */

    /// @notice vote with a single venft
    function _vote(
        uint256 _tokenId,
        address[] storage _pairs,
        uint256[] storage _weights
    ) internal {
        /// The voter will make the same verification, though as a required statement which would revert all attempts at voting
        /// We would rather do nothing than revert
        uint256 lastVoted = VELOCIMETER_VOTER.lastVoted(_tokenId);
        uint256 votingPower = IVotingEscrow(VEFLOW).balanceOfNFT(_tokenId);

        if ((block.timestamp / EPOCH) * EPOCH > lastVoted && votingPower != 0) {
            VELOCIMETER_VOTER.vote(_tokenId, _pairs, _weights);
        }
    }

    /// @notice claimFees for a single nft
    /// @dev For each feeContract, also called Internal Bribe, claims for both tokens associated
    function _claimFees(uint256 _tokenId) internal {
        /// Not having custody of the nfts means that we have to claim directly from the bribe contracts
        for (uint256 i; i < gauges.length; i = _uncheckedInc(i)) {
            address eBribe = VELOCIMETER_VOTER.external_bribes(gauges[i]); //bribes

            // Construct rewards for Internal Bribe, External Bribe
            uint256 eRewardsLen = IExternalBribe(eBribe).rewardsListLength();
            address[] memory eRewards = new address[](eRewardsLen);

            uint256[] memory eRewardsBalBefore = new uint256[](eRewardsLen);
            uint256 received;

            // Claiming: External Bribe
            for (uint256 j; j < eRewardsLen; j = _uncheckedInc(j)) {
                eRewards[j] = IExternalBribe(eBribe).rewards(j);
                eRewardsBalBefore[j] = IERC20Upgradeable(eRewards[j]).balanceOf(
                    address(this)
                );
            }
            IExternalBribe(eBribe).getReward(_tokenId, eRewards);
            for (uint256 j; j < eRewardsLen; j = _uncheckedInc(j)) {
                received =
                    IERC20Upgradeable(eRewards[j]).balanceOf(address(this)) -
                    eRewardsBalBefore[j];
                tokenIdToInfo[_tokenId].tokenToRewardAmount[
                    eRewards[j]
                ] += received;
                tokenToRewardInfo[eRewards[j]].totalReceived += received;
            }
        }
    }

    function _increaseDuration(uint256 _tokenId) internal {
        uint256 newUnlockTime = IVotingEscrow(VEFLOW).locked__end(_tokenId) +
            EPOCH;
        IVotingEscrow(VEFLOW).increase_unlock_time(_tokenId, newUnlockTime);
    }

    function _chargeFees() internal {
        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);
        uint256 usdcBalBefore = usdc.balanceOf(address(this));
        uint256 toSwap = (IERC20Upgradeable(FLOW).balanceOf(address(this)) *
            totalFee) / PERCENT_DIVISOR;
        _swap(FLOW, USDC, toSwap);
        uint256 usdcFee = (usdc.balanceOf(address(this))) - usdcBalBefore;

        if (usdcFee != 0) {
            usdc.safeTransfer(treasury, usdcFee);
        }

        // Adjust tokenToRewardInfo
        for (uint256 i; i < rewards.length(); i = _uncheckedInc(i)) {
            tokenToRewardInfo[rewards.at(i)].totalReceivedFlow -=
                (tokenToRewardInfo[rewards.at(i)].totalReceivedFlow *
                    totalFee) /
                PERCENT_DIVISOR;
        }
    }

    /// @dev Helper function to swap {_from} to {_to} given an {_amount}.
    function _swap(address _from, address _to, uint256 _amount) internal {
        if (_from == _to || _amount == 0) {
            return;
        }

        uint256 output;
        bool useStable;
        IRouter router = IRouter(VELOCIMETER_ROUTER);
        address[] storage path = swapPath[_from][_to];
        IRouter.route[] memory routes = new IRouter.route[](path.length - 1);
        uint256 prevRouteOutput = _amount;

        IERC20Upgradeable(_from).safeIncreaseAllowance(
            VELOCIMETER_ROUTER,
            _amount
        );
        for (uint256 i; i < routes.length; i = _uncheckedInc(i)) {
            (output, useStable) = router.getAmountOut(
                prevRouteOutput,
                path[i],
                path[i + 1]
            );
            routes[i] = IRouter.route({
                from: path[i],
                to: path[i + 1],
                stable: useStable
            });
            prevRouteOutput = output;
        }
        router.swapExactTokensForTokens(
            _amount,
            0,
            routes,
            address(this),
            block.timestamp
        );
    }

    function _removeRevokedNfts() internal {
        for (uint256 i; i < tokenIds.length; i = _uncheckedInc(i)) {
            if (
                !IVotingEscrow(VEFLOW).isApprovedOrOwner(
                    address(this),
                    tokenIds[i]
                )
            ) {
                uint256 withdrawVeNftIdx = tokenIdToInfo[tokenIds[i]].veNftIdx;
                uint256 lastTokenId = tokenIds[tokenIds.length - 1];

                tokenIdToInfo[lastTokenId].veNftIdx = withdrawVeNftIdx;
                tokenIds[withdrawVeNftIdx] = lastTokenId;
                tokenIds.pop();
                delete tokenIdToInfo[tokenIds[i]];
            }
        }
    }

    function _getFlowBalance()
        internal
        view
        returns (uint256 lockedTotal, uint256 votingPowerTotal)
    {
        IVotingEscrow.LockedBalance memory locked;
        for (uint256 i; i < tokenIds.length; i = _uncheckedInc(i)) {
            locked = IVotingEscrow(VEFLOW).locked(tokenIds[i]);
            votingPowerTotal += IVotingEscrow(VEFLOW).balanceOfNFT(tokenIds[i]);
            if (locked.amount >= 0) {
                lockedTotal += uint256(int256(locked.amount));
            }
        }
    }

    /// @notice For doing an unchecked increment of an index for gas optimization purposes
    /// @param i - The number to increment
    /// @return The incremented number
    function _uncheckedInc(uint256 i) internal pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    /* ========== PSEUDO MODIFIERS ========== */

    function _requireMinimumLockDuration(uint256 _tokenId) internal view {
        if (
            IVotingEscrow(VEFLOW).locked__end(_tokenId) <=
            block.timestamp + EPOCH
        ) {
            revert FlowVoteFarmer__TokenExpiresTooEarly();
        }
    }

    function _requireOwnerOf(uint256 _tokenId, address _owner) internal view {
        if (!IVotingEscrow(VEFLOW).isApprovedOrOwner(_owner, _tokenId)) {
            revert FlowVoteFarmer__Unauthorized();
        }
    }

    /* ========== UPGRADE ========== */

    /// @dev This function must be overriden simply for access control purposes.
    ///    Only MANAGER can upgrade the implementation once the timelock
    ///    has passed.
    function _authorizeUpgrade(address) internal override onlyRole(MANAGER) {}
}
