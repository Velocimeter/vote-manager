// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

interface IFlowVoteManager {
    function treasury() external view returns (address);

    function totalFee() external view returns (uint256);

    function gauges(uint256) external view returns (address);

    function weights(uint256) external view returns (uint256);

    function nftCap() external view returns (uint256);

    function getSwapPath(
        address,
        address
    ) external view returns (address[] memory);

    function getRewards() external view returns (address[] memory);

    function gaugesLength() external view returns (uint256);

    function weightsLength() external view returns (uint256);

    function strategiesLength() external view returns (uint256);

    function getStrategy(uint256 id) external view returns (address);
}
