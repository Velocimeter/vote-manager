// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

contract ERC1967ProxyClone is
    ERC1967Proxy,
    AccessControlEnumerable,
    Initializable
{
    constructor(
        address _logic,
        bytes memory _data
    ) ERC1967Proxy(_logic, _data) {}

    // This function serves as an alternative for clone contracts
    // that cannot use the ERC1967Proxy constructor
    // It should be called ASAP to so as to not be hijacked by another account
    function initializeProxy(
        address _logic,
        bytes memory _data
    ) external initializer {
        _upgradeToAndCall(_logic, _data, false);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function upgradeToAndCall(
        address _logic,
        bytes memory _data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _upgradeToAndCall(_logic, _data, false);
    }
}
