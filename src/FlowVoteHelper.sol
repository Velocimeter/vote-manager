// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "./interfaces/IFlowVoteManager.sol";
import "./interfaces/IFlowVoteFarmer.sol";
import "./interfaces/IVotingEscrow.sol";

contract FlowVoteHelper {
    IFlowVoteManager public manager;
    IVotingEscrow public constant VEFLOW =
        IVotingEscrow(0x8E003242406FBa53619769F31606ef2Ed8A65C00);

    constructor(address _manager) {
        manager = IFlowVoteManager(_manager);
    }

    function getAPRForLog(uint256 log) external view returns (uint256 apr) {
        address[] memory strategies = _getStrategies();
        uint256 strategiesProcessed;
        for (uint256 i; i < strategies.length; i++) {
            if (IFlowVoteFarmer(strategies[i]).harvestLogLength() >= log) {
                apr += IFlowVoteFarmer(strategies[i]).calculateAPRForLog(log);
                strategiesProcessed++;
            }
        }
        apr = apr / strategiesProcessed;
    }

    function getMaxLogLength() public view returns (uint256 maxLength) {
        address[] memory strategies = _getStrategies();
        for (uint256 i; i < strategies.length; i++) {
            if (IFlowVoteFarmer(strategies[i]).harvestLogLength() > maxLength) {
                maxLength = IFlowVoteFarmer(strategies[i]).harvestLogLength();
            }
        }
    }

    function getTotalFlowLocked() external view returns (uint256 total) {
        address[] memory strategies = _getStrategies();
        for (uint256 i; i < strategies.length; i++) {
            total += _getTotalFlowLockedOfStrat(strategies[i]);
        }
    }

    function getTotalVotingPower() external view returns (uint256 total) {
        address[] memory strategies = _getStrategies();
        for (uint256 i; i < strategies.length; i++) {
            total += _getTotalVotingPowerOfStrat(strategies[i]);
        }
    }

    function getTotalFlowLockedForUser(
        address user
    ) external view returns (uint256 total) {
        uint256[] memory userTokens = getManagedTokensOfUser(user);
        for (uint256 i; i < userTokens.length; i++) {
            total += uint128(VEFLOW.locked(userTokens[i]).amount);
        }
    }

    function getTotalVotingPowerForUser(
        address user
    ) external view returns (uint256 total) {
        uint256[] memory userTokens = getManagedTokensOfUser(user);
        for (uint256 i; i < userTokens.length; i++) {
            total += VEFLOW.balanceOfNFT(userTokens[i]);
        }
    }

    function getManagedTokensOfUser(
        address user
    ) public view returns (uint256[] memory) {
        uint256 max = VEFLOW.balanceOf(user);
        uint256[] memory tokens = new uint256[](max);

        for (uint256 i; i < max; i++) {
            uint256 tokenId = VEFLOW.tokenOfOwnerByIndex(user, i);
            if (_isManaged(tokenId)) {
                tokens[i] = tokenId;
            }
        }

        return tokens;
    }

    function _getStrategies() internal view returns (address[] memory) {
        uint256 stratLen = manager.strategiesLength();
        address[] memory strategies = new address[](stratLen);
        for (uint256 i; i < stratLen; i++) {
            strategies[i] = manager.getStrategy(i);
        }
        return strategies;
    }

    function _getTotalFlowLockedOfStrat(
        address strategy
    ) internal view returns (uint256 total) {
        IFlowVoteFarmer strat = IFlowVoteFarmer(strategy);
        uint256 tokenIdsLen = strat.tokenIdsLength();
        for (uint256 i; i < tokenIdsLen; i++) {
            uint256 tokenId = strat.tokenIds(i);
            total += uint128(VEFLOW.locked(tokenId).amount);
        }
    }

    function _getTotalVotingPowerOfStrat(
        address strategy
    ) internal view returns (uint256 total) {
        IFlowVoteFarmer strat = IFlowVoteFarmer(strategy);
        uint256 tokenIdsLen = strat.tokenIdsLength();
        for (uint256 i; i < tokenIdsLen; i++) {
            uint256 tokenId = strat.tokenIds(i);
            total += VEFLOW.balanceOfNFT(tokenId);
        }
    }

    function _isManaged(uint256 tokenId) internal view returns (bool) {
        address[] memory strategies = _getStrategies();
        for (uint256 i; i < strategies.length; i++) {
            uint256 tokenIdsLen = IFlowVoteFarmer(strategies[i])
                .tokenIdsLength();
            for (uint256 j; j < tokenIdsLen; j++) {
                if (IFlowVoteFarmer(strategies[i]).tokenIds(j) == tokenId) {
                    return true;
                }
            }
        }
        return false;
    }
}
