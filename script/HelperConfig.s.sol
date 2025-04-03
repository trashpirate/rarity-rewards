// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console, console2} from "forge-std/Script.sol";
import {FunctionsRouterMock} from "test/mocks/FunctionsRouterMock.sol";
import {ERC721AMock} from "@erc721a/contracts/mocks/ERC721AMock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

contract HelperConfig is Script {
    struct FunctionsConfig {
        string donID;
        address functionsRouter;
        address linkToken;
    }

    struct NetworkConfig {
        address collection;
        address functionsRouter;
        address link;
        bytes32 donID;
        uint64 subscriptionId;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public constant ANVIL_DEFAULT_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    constructor() {
        if (block.chainid == 8453 || block.chainid == 123) {
            activeNetworkConfig = _getMainnetConfig();
        } else if (block.chainid == 84532 || block.chainid == 84531) {
            activeNetworkConfig = _getTestnetConfig();
        } else if (block.chainid == 1337) {
            activeNetworkConfig = _getFunctionsAnvilConfig();
        } else {
            activeNetworkConfig = _getAnvilConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          CHAIN CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/

    function _getMainnetConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            collection: 0xE9e5d3F02E91B8d3bc74Cf7cc27d6F13bdfc0BB6,
            functionsRouter: 0xf9B8fc078197181C841c296C876945aaa425B278,
            link: 0x404460C6A5EdE2D891e8297795264fDe62ADBB75,
            donID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000,
            subscriptionId: 0,
            deployerKey: uint256(0x0)
        });
    }

    function _getTestnetConfig() internal view returns (NetworkConfig memory) {
        return NetworkConfig({
            collection: 0x77b6d8dEcfc2DfEdb53be9fA527D7939aF0e592c,
            functionsRouter: 0xf9B8fc078197181C841c296C876945aaa425B278,
            link: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
            donID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000,
            subscriptionId: 298,
            deployerKey: vm.envUint("ANVIL_DEFAULT_KEY")
        });
    }

    function _getFunctionsAnvilConfig() internal returns (NetworkConfig memory) {
        vm.startBroadcast();
        // Deploy NFT Collection
        ERC721AMock collection = new ERC721AMock("NFT Collection", "NFTC");
        vm.stopBroadcast();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/functions-toolkit/local-network/cf-network-config.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);

        FunctionsConfig memory config = abi.decode(data, (FunctionsConfig));

        console.log("--------------- Local Testnet Config ------------------");
        console.log("Link Token: ", config.linkToken);
        console.log("Functions Router: ", config.functionsRouter);
        console.log("DonID: ", config.donID);
        console.log("-------------------------------------------------------");

        return NetworkConfig({
            collection: address(collection),
            functionsRouter: config.functionsRouter,
            link: config.linkToken,
            donID: bytes32(bytes(config.donID)), // mock donID
            subscriptionId: 0,
            deployerKey: ANVIL_DEFAULT_KEY
        });
    }

    function _getAnvilConfig() internal returns (NetworkConfig memory) {
        uint32[] memory maxCallbackGasLimits = new uint32[](1);
        maxCallbackGasLimits[0] = 500000;

        vm.startBroadcast();

        // Deploy NFT Collection
        ERC721AMock collection = new ERC721AMock("NFT Collection", "NFTC");

        // Deploy LINK token
        LinkToken linkToken = new LinkToken();

        // Fund default address with some LINK
        linkToken.transfer(ANVIL_DEFAULT_ADDRESS, 100 ether);

        // Deploy mock router
        FunctionsRouterMock router = new FunctionsRouterMock(
            address(linkToken),
            FunctionsRouterMock.Config({
                maxConsumersPerSubscription: 100,
                adminFee: 1e16,
                handleOracleFulfillmentSelector: bytes4(keccak256("handleOracleFulfillment(bytes32,bytes,bytes)")),
                gasForCallExactCheck: 5000,
                maxCallbackGasLimits: maxCallbackGasLimits,
                subscriptionDepositMinimumRequests: 0,
                subscriptionDepositJuels: 0
            })
        );

        vm.stopBroadcast();

        return NetworkConfig({
            collection: address(collection),
            functionsRouter: address(router),
            link: address(linkToken),
            donID: 0x66756e2d626173652d6d61696e6e65742d310000000000000000000000000000, // mock donID
            subscriptionId: 0,
            deployerKey: ANVIL_DEFAULT_KEY
        });
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updateSubscriptionId(uint64 newSubId) public {
        activeNetworkConfig.subscriptionId = newSubId;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
