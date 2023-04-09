// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC1967ProxyClone} from "../src/ERC1967ProxyClone.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FlowVoteFarmer} from "../src/FlowVoteFarmer.sol";
import {FlowVoteManager} from "../src/FlowVoteManager.sol";
import {FlowVoteHelper} from "../src/FlowVoteHelper.sol";

contract Deployment is Script {
    address private constant TEAM_MULTI_SIG =
        0x13eeB8EdfF60BbCcB24Ec7Dd5668aa246525Dc51;
    address[] private STRATEGISTS = [
        0x13eeB8EdfF60BbCcB24Ec7Dd5668aa246525Dc51
    ];
    address private constant DEPLOYER =
        0xD93142ED5B85FcA4550153088750005759CE8318;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FlowVoteFarmer flowVoteFarmer = new FlowVoteFarmer();
        ERC1967ProxyClone flowVoteFarmerProxy = new ERC1967ProxyClone(
            address(flowVoteFarmer),
            ""
        );

        flowVoteFarmerProxy.initializeProxy(address(flowVoteFarmer), "");

        FlowVoteManager flowVoteManager = new FlowVoteManager();
        TransparentUpgradeableProxy flowVoteManagerProxyAddress = new TransparentUpgradeableProxy(
                address(flowVoteManager),
                DEPLOYER,
                abi.encodeWithSignature(
                    "initialize(address[],address,address,address)",
                    STRATEGISTS,
                    TEAM_MULTI_SIG,
                    address(flowVoteFarmerProxy),
                    address(flowVoteFarmer)
                )
            );

        FlowVoteHelper flowVoteHelper = new FlowVoteHelper(
            address(flowVoteManagerProxyAddress)
        );

        vm.stopBroadcast();
    }
}
