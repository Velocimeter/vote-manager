// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/contracts/proxy/Clones.sol";
import "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IFlowVoteFarmer.sol";
import "./interfaces/IERC1967ProxyClone.sol";

error FlowVoteManager__UpgradeCooldown();
error FlowVoteManager__Unauthorized();
error FlowVoteManager__WrongInput();

contract FlowVoteManager is
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    /* ========== STATE VARIABLES ========== */
    /// @dev Role
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");
    bytes32[] private cascadingAccess;

    /// @notice Time required after initiating an upgrade to do so
    uint256 public upgradeProposalTime;
    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant UPGRADE_TIMELOCK = 48 hours; // minimum 48 hours for RF
    uint256 public upgradeImplProposalTime;
    mapping(address => bool) public implUpgraded;

    address public treasury;
    address[] public strategists;

    IVotingEscrow public constant VEFLOW =
        IVotingEscrow(0x8E003242406FBa53619769F31606ef2Ed8A65C00);
    address public strategyProxy;
    address public strategyImpl;

    /// @notice
    /// {strategies} - strategies managing nfts and voting
    /// {tokenIdToStrat} - get strategy managing an nft
    EnumerableSetUpgradeable.AddressSet private strategies;
    mapping(uint256 => address) public tokenIdToStrat;
    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant MAX_WEIGHT = 10_000; // 100% voting power

    ///@dev Distribution of fees earned, expressed as % of the profit from each harvest.
    ///{totalFee} - divided by 10,000 to determine the % fee.
    uint256 public totalFee;

    /// @notice State shared accross clones
    /// @dev tokenA => (tokenB => swapPath config): returns best path to swap
    ///         tokenA to tokenB
    address[] public gauges;
    uint256[] public weights;
    mapping(address => mapping(address => address[])) public swapPath;
    EnumerableSetUpgradeable.AddressSet private rewards; // Rewards (to swap to Flow)
    uint256 public nftCap;
    address public constant FLOW = 0xB5b060055F0d1eF5174329913ef861bC3aDdF029;
    address public constant WCANTO = 0x826551890Dc65655a0Aceca109aB11AbDbD7a07B;
    address public constant USDC = 0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd;

    /// Events
    /// {TotalFeeUpdated} Event that is fired each time the total fee is updated.
    /// {SwapPathUpdated} Event that is fired each time a swap path is updated.
    event TotalFeeUpdated(uint256 newFee);
    event SwapPathUpdated(address from, address to);

    /* ========== CONSTRUCTOR ========== */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __FlowVoteManager_init(
        address[] memory _strategists
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __AccessControlEnumerable_init();
        __Pausable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        cascadingAccess = [DEFAULT_ADMIN_ROLE, STRATEGIST, KEEPER];
        for (uint256 i; i < _strategists.length; i = _uncheckedInc(i)) {
            _grantRole(STRATEGIST, _strategists[i]);
        }
        clearUpgradeCooldown();
    }

    function initialize(
        address[] memory _strategists,
        address _treasury,
        address _strategyProxy,
        address _strategyImpl
    ) public initializer {
        __FlowVoteManager_init(_strategists);
        strategists = _strategists;
        treasury = _treasury;
        strategyProxy = _strategyProxy;
        strategyImpl = _strategyImpl;
        nftCap = 10;
        swapPath[FLOW][USDC] = [FLOW, WCANTO, USDC];
    }

    /* ========== USER ACTIONS ========== */
    /// @notice Deposit venft, approval is transferred to underlying strategy
    /// @dev May want to communicate to users that a deposit means 2 addresses
    ///         will be approved to manage nft
    ///         (even if there is only one approval on front end)
    function delegate(uint256 _tokenId) external whenNotPaused {
        if (tokenIdToStrat[_tokenId] != address(0)) {
            revert FlowVoteManager__WrongInput();
        }

        (address strategy, bool strategiesFull) = selectDepositStrategy();
        if (strategy == address(0)) {
            // Question: should this be = instead of == ?
            strategy == _deployStrategy();
        } else if (strategiesFull == true) {
            _deployStrategy();
        }
        IFlowVoteFarmer(strategy).delegate(_tokenId, msg.sender);
        tokenIdToStrat[_tokenId] = strategy;
    }

    function undelegate(uint256 _tokenId) external {
        address strategy = tokenIdToStrat[_tokenId];
        IFlowVoteFarmer(strategy).undelegate(_tokenId, msg.sender);
        delete tokenIdToStrat[_tokenId];
    }

    /// @notice Makes a venft eligible to have its lock duration extended by a week on a recurring basis
    function autoLock(uint256 _tokenId, bool _enable) external {
        address strategy = tokenIdToStrat[_tokenId];
        IFlowVoteFarmer(strategy).autoLock(_tokenId, _enable, msg.sender);
    }

    function vote(uint256 start, uint256 end) external {
        _atLeastRole(KEEPER);
        _verifySlice(start, end);

        // Vote
        for (uint256 i = start; i < end; i = _uncheckedInc(i)) {
            IFlowVoteFarmer(strategies.at(i)).vote();
        }
    }

    function harvest(uint256 start, uint256 end) external {
        _atLeastRole(KEEPER);
        _verifySlice(start, end);

        // Harvest
        for (uint256 i = start; i < end; i = _uncheckedInc(i)) {
            IFlowVoteFarmer(strategies.at(i)).harvest();
        }
    }

    function resetBalancesAll(uint256 start, uint256 end) external {
        _atLeastRole(KEEPER);
        _verifySlice(start, end);

        // Reset balances
        for (uint256 i = start; i < end; i = _uncheckedInc(i)) {
            IFlowVoteFarmer(strategies.at(i)).resetBalancesAll();
        }
    }

    /* ========== ADMIN ========== */
    function setGaugesAndWeights(
        address[] calldata _gauges,
        uint256[] calldata _weights
    ) external {
        _atLeastRole(KEEPER);
        uint256 total;
        for (uint256 i; i < _weights.length; i = _uncheckedInc(i)) {
            total += _weights[i];
        }
        if (_gauges.length != _weights.length || total != MAX_WEIGHT) {
            revert FlowVoteManager__WrongInput();
        }
        delete gauges;
        delete weights;

        for (uint256 i; i < _weights.length; i = _uncheckedInc(i)) {
            gauges.push(_gauges[i]);
            weights.push(_weights[i]);
        }
    }

    function updateSwapPath(address[] memory _path) external {
        _atLeastRole(STRATEGIST);
        if (_path.length < 2 || _path[0] == _path[_path.length - 1]) {
            revert FlowVoteManager__WrongInput();
        }

        // Update global state
        // Set route
        swapPath[_path[0]][_path[_path.length - 1]] = _path;

        // Add to list of rewards if unknown token
        rewards.add(_path[0]);
        emit SwapPathUpdated(_path[0], _path[_path.length - 1]);
    }

    function updateTotalFee(uint256 _totalFee) external {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        if (_totalFee > MAX_FEE) {
            revert FlowVoteManager__WrongInput();
        }

        // Update global state
        totalFee = _totalFee;
        emit TotalFeeUpdated(totalFee);
    }

    function addReward(address _reward) external {
        _atLeastRole(STRATEGIST);

        // Update global state
        rewards.add(_reward);
    }

    function removeReward(address _reward) external {
        _atLeastRole(STRATEGIST);

        // Update global state
        rewards.remove(_reward);
    }

    function setNftCap(uint256 _cap) external {
        _atLeastRole(STRATEGIST);

        // Update global state
        nftCap = _cap;
    }

    function deployStrategy() external returns (address) {
        _atLeastRole(STRATEGIST);
        return _deployStrategy();
    }

    function forceSynchronization(uint256 start, uint256 end) external {
        _atLeastRole(STRATEGIST);
        _synchronizeStrategies(start, end);
    }

    function updateImplementation(
        address _newImplementation,
        bytes memory _data,
        uint256 start,
        uint256 end
    ) external {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        _requireImplCooldownOver();
        _verifySlice(start, end);

        strategyImpl = _newImplementation;
        for (uint256 i = start; i < end; i = _uncheckedInc(i)) {
            if (!implUpgraded[strategies.at(i)]) {
                IERC1967ProxyClone(strategies.at(i)).upgradeToAndCall(
                    strategyImpl,
                    _data
                );
                implUpgraded[strategies.at(i)] = true;
            }
        }

        _tryResettingCooldown();
    }

    /* ========== INTERNAL ========== */
    /// @dev Returns address of strat managing the lowest amount of nfts
    function selectDepositStrategy()
        public
        view
        returns (address depositStrategy, bool strategiesFull)
    {
        uint256 stratLen = strategies.length();
        for (uint256 i; i < stratLen; i = _uncheckedInc(i)) {
            if (IFlowVoteFarmer(strategies.at(i)).tokenIdsLength() < nftCap) {
                depositStrategy = strategies.at(i);
                if (
                    (i == stratLen - 1) &&
                    (IFlowVoteFarmer(strategies.at(i)).tokenIdsLength() ==
                        nftCap - 1)
                ) {
                    strategiesFull = true;
                }
                break;
            }
        }
    }

    function _deployStrategy() internal returns (address strategy) {
        strategy = Clones.clone(strategyProxy);
        IERC1967ProxyClone(strategy).initializeProxy(
            strategyImpl,
            new bytes(0)
        );
        IFlowVoteFarmer(strategy).initialize();
        strategies.add(strategy);
        _synchronizeStrategies(strategies.length() - 1, strategies.length());
    }

    /// @notice Notifies managed strats to fetch the global state
    function _synchronizeStrategies(uint256 start, uint256 end) internal {
        _verifySlice(start, end);
        for (uint256 i = start; i < end; i = _uncheckedInc(i)) {
            IFlowVoteFarmer(strategies.at(i)).synchronize();
        }
    }

    function _tryResettingCooldown() internal {
        uint256 stratLen = strategies.length();
        for (uint256 i; i < stratLen; i = _uncheckedInc(i)) {
            if (!implUpgraded[strategies.at(i)]) {
                /// A strategy has not been upgraded
                return;
            }
        }
        /// All strategies have been upgraded
        clearImplUpgradeCooldown();
    }

    /// @notice 0 <= startId <= endId < strategies.length()
    function _verifySlice(uint256 start, uint256 end) internal view {
        if (end > strategies.length() || start >= end) {
            revert FlowVoteManager__WrongInput();
        }
    }

    /* ========== VIEWS ========== */

    function getStrategy(uint256 id) external view returns (address strategy) {
        strategy = strategies.at(id);
    }

    function strategiesLength() external view returns (uint256 length) {
        length = strategies.length();
    }

    function getRewards() external view returns (address[] memory) {
        address[] memory rewardsArray = new address[](rewards.length());
        for (uint256 i; i < rewards.length(); i = _uncheckedInc(i)) {
            rewardsArray[i] = rewards.at(i);
        }
        return rewardsArray;
    }

    function getSwapPath(
        address from,
        address to
    ) external view returns (address[] memory) {
        return swapPath[from][to];
    }

    function gaugesLength() external view returns (uint256) {
        return gauges.length;
    }

    function weightsLength() external view returns (uint256) {
        return weights.length;
    }

    function averageAPRAcrossLastNHarvests(
        uint256 _n
    ) public view returns (uint256 yearly) {
        uint256 stratsProcessed;
        for (uint256 i; i < strategies.length(); i = _uncheckedInc(i)) {
            uint256 hLen = IFlowVoteFarmer(strategies.at(i)).harvestLogLength();
            if (hLen >= _n) {
                yearly += IFlowVoteFarmer(strategies.at(i))
                    .averageAPRAcrossLastNHarvests(_n);
                stratsProcessed = _uncheckedInc(stratsProcessed);
            }
        }
        yearly = yearly / stratsProcessed;
    }

    /* ========== PSEUDO MODIFIERS ========== */
    function _requireCooldownOver() internal view {
        if (upgradeProposalTime + UPGRADE_TIMELOCK > block.timestamp) {
            revert FlowVoteManager__UpgradeCooldown();
        }
    }

    function _requireImplCooldownOver() internal view {
        if (upgradeImplProposalTime + UPGRADE_TIMELOCK > block.timestamp) {
            revert FlowVoteManager__UpgradeCooldown();
        }
    }

    /// @notice Internal function that checks cascading role privileges. Any higher privileged role
    /// should be able to perform all the functions of any lower privileged role. This is
    /// accomplished using the {cascadingAccess} array that lists all roles from most privileged
    /// to least privileged.
    /// @param role - The role in bytes from the keccak256 hash of the role name
    function _atLeastRole(bytes32 role) internal view {
        uint256 numRoles = cascadingAccess.length;
        bool specifiedRoleFound = false;
        bool senderHighestRoleFound = false;

        // The specified role must be found in the {cascadingAccess} array.
        // Also, msg.sender's highest role index <= specified role index.
        for (uint256 i = 0; i < numRoles; i = _uncheckedInc(i)) {
            if (
                !senderHighestRoleFound &&
                hasRole(cascadingAccess[i], msg.sender)
            ) {
                senderHighestRoleFound = true;
            }
            if (role == cascadingAccess[i]) {
                specifiedRoleFound = true;
                break;
            }
        }

        if (!specifiedRoleFound || !senderHighestRoleFound) {
            revert FlowVoteManager__Unauthorized();
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

    /* ========== UPGRADE ========== */
    /// @dev DEFAULT_ADMIN_ROLE must call this function prior to upgrading the implementation
    ///     and wait UPGRADE_TIMELOCK seconds before executing the upgrade.
    function initiateUpgradeCooldown() external onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeProposalTime = block.timestamp;
    }

    /// @dev This function is called:
    ///     - in initialize()
    ///     - as part of a successful upgrade
    ///     - manually by DEFAULT_ADMIN_ROLE to clear the upgrade cooldown.
    function clearUpgradeCooldown() public onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeProposalTime = block.timestamp + (ONE_YEAR * 100);
    }

    /// @dev This function must be overriden simply for access control purposes.
    ///    Only DEFAULT_ADMIN_ROLE can upgrade the implementation once the timelock
    ///    has passed.
    function _authorizeUpgrade(
        address
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireCooldownOver();
        clearUpgradeCooldown();
    }

    /// @dev Mimics regular upgrade pattern, to change the implemenation of the
    ///     managed strategies
    function initiateImplUpgradeCooldown()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        upgradeImplProposalTime = block.timestamp;
    }

    function clearImplUpgradeCooldown() public onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeImplProposalTime = block.timestamp + (ONE_YEAR * 100);
        uint256 stratLen = strategies.length();
        for (uint256 i; i < stratLen; i = _uncheckedInc(i)) {
            implUpgraded[strategies.at(i)] = false;
        }
    }

    /* ========== PAUSE ========== */
    function pause(uint256 start, uint256 end) external {
        _atLeastRole(STRATEGIST);
        _verifySlice(start, end);

        _pause();
        for (uint256 i = start; i < end; i = _uncheckedInc(i)) {
            IFlowVoteFarmer(strategies.at(i)).pause();
        }
    }

    function unpause(uint256 start, uint256 end) external {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        _verifySlice(start, end);

        _unpause();
        for (uint256 i = start; i < end; i = _uncheckedInc(i)) {
            IFlowVoteFarmer(strategies.at(i)).unpause();
        }
    }
}
