// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FlowVoteManager} from "../src/FlowVoteManager.sol";

contract Deployment is Script {
    address payable private constant MANAGER =
        payable(0x5880f495cF0FAF6347354D8aCc41b49EDB51a9f7);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FlowVoteManager flowVoteManager = new FlowVoteManager();
        TransparentUpgradeableProxy(MANAGER).upgradeTo(
            address(flowVoteManager)
        );

        vm.stopBroadcast();
    }
}
