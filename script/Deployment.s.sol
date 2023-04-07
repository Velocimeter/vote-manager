// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC1967ProxyClone} from "../src/ERC1967ProxyClone.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlowVoteFarmer} from "../src/FlowVoteFarmer.sol";
import {FlowVoteManager} from "../src/FlowVoteManager.sol";
import {FlowVoteHelper} from "../src/FlowVoteHelper.sol";

contract Deployment is Script {
    // TODO: change address
    address private constant COUNCIL =
        0x06b16991B53632C2362267579AE7C4863c72fDb8;
    address private constant TEAM_MULTI_SIG =
        0x13eeB8EdfF60BbCcB24Ec7Dd5668aa246525Dc51;
    address private constant GOVERNOR =
        0x06b16991B53632C2362267579AE7C4863c72fDb8;
    address[] private STRATEGISTS = [
        0x06b16991B53632C2362267579AE7C4863c72fDb8
    ];

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FlowVoteFarmer flowVoteFarmer = new FlowVoteFarmer();
        ERC1967ProxyClone flowVoteFarmerProxyAddress = new ERC1967ProxyClone(
            address(flowVoteFarmer),
            ""
        );

        FlowVoteManager flowVoteManager = new FlowVoteManager();
        ERC1967Proxy flowVoteManagerProxyAddress = new ERC1967Proxy(
            address(flowVoteManager),
            abi.encodeWithSignature(
                "initialize(address[],address,address,address)",
                STRATEGISTS,
                TEAM_MULTI_SIG,
                flowVoteFarmerProxyAddress,
                address(flowVoteFarmer)
            )
        );

        FlowVoteHelper flowVoteHelper = new FlowVoteHelper(
            address(flowVoteManagerProxyAddress)
        );

        vm.stopBroadcast();
    }
}
