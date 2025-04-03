// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RarityRewards} from "src/RarityRewards.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721AMock} from "@erc721a/contracts/mocks/ERC721AMock.sol";

contract MintMockNft is Script {
    uint256 public constant STARTING_DEPOSIT = 10 ether;

    function mintMockNft(address collection, uint256 deployerKey) public {
        console.log("---------------- Mint ------------------");
        console.log("Mint on ChainId: ", block.chainid);
        console.log("Using Mock NFT: ", collection);

        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        ERC721AMock(collection).mint(tx.origin, 100);
        vm.stopBroadcast();

        console.log("Mint completed to : ", tx.origin);
        console.log("Minted: ", ERC721AMock(collection).balanceOf(tx.origin));
        console.log("-------------------------------------------------------");
    }

    function mintMockNftUsingConfig(address collection) public {
        HelperConfig helperConfig = new HelperConfig();
        (,,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        mintMockNft(collection, deployerKey);
    }

    function run() external {
        address collection = DevOpsTools.get_most_recent_deployment("ERC721AMock", block.chainid);
        mintMockNftUsingConfig(collection);
    }
}

contract Deposit is Script {
    uint256 public constant STARTING_DEPOSIT = 10 ether;

    function deposit(address consumer, address link, uint256 deployerKey) public {
        console.log("---------------- DEPOSIT ------------------");
        console.log("Deposit on ChainId: ", block.chainid);
        console.log("Using Functions Consumer: ", consumer);

        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        IERC20(link).approve(consumer, STARTING_DEPOSIT);
        RarityRewards(consumer).deposit(0, link, STARTING_DEPOSIT, block.timestamp);
        RarityRewards(consumer).activate(0);
        vm.stopBroadcast();

        console.log("Deposit completed: ", STARTING_DEPOSIT);
        console.log("-------------------------------------------------------");
    }

    function depositUsingConfig(address consumer) public {
        HelperConfig helperConfig = new HelperConfig();
        (,, address link,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        deposit(consumer, link, deployerKey);
    }

    function run() external {
        address consumer = DevOpsTools.get_most_recent_deployment("RarityRewards", block.chainid);
        depositUsingConfig(consumer);
    }
}

contract Claim is Script {
    function claim(address consumer, uint256 deployerKey) public returns (bytes32) {
        console.log("---------------- CLAIMING SHARE ------------------");
        console.log("Sending Request on ChainId: ", block.chainid);
        console.log("Using Functions Consumer: ", consumer);

        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        bytes32 requestId = RarityRewards(consumer).claim(0, 1);
        vm.stopBroadcast();
        console.log("Request Sent; Request ID: ");
        console.logBytes32(requestId);
        console.log("-------------------------------------------------------");
        return requestId;
    }

    function claimUsingConfig(address consumer) public returns (bytes32) {
        HelperConfig helperConfig = new HelperConfig();
        (,,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        return claim(consumer, deployerKey);
    }

    function run() external returns (bytes32) {
        address consumer = DevOpsTools.get_most_recent_deployment("RarityRewards", block.chainid);
        return claimUsingConfig(consumer);
    }
}

contract GetLastResponse is Script {
    function getLastResponse(address consumer) public returns (bytes memory) {
        console.log("---------------- READING RESPONSE ------------------");
        console.log("Using Functions Consumer: ", consumer);

        vm.startBroadcast();
        bytes memory response = RarityRewards(consumer).getLastResponse();
        vm.stopBroadcast();
        console.log("Response: ", string(response));
        console.log("-------------------------------------------------------");
        return response;
    }

    function run() external returns (bytes memory) {
        address consumer = DevOpsTools.get_most_recent_deployment("RarityRewards", block.chainid);
        return getLastResponse(consumer);
    }
}
