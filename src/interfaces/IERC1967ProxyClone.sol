pragma solidity ^0.8.0;

interface IERC1967ProxyClone {
    function initializeProxy(address _logic, bytes memory _data) external;

    function upgradeToAndCall(address _logic, bytes memory _data) external;
}
