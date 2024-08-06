// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/GroupBillFactory.sol";
import "../test/mocks/ERC20TokenMock.sol";

contract DeployGroupBillFactory is Script {
    function run()
        external virtual
        returns (address factoryAddress, address[] memory tokens)
    {
        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("ETH_CONSUMER_EOA");

        tokens = vm.envAddress("ETH_ACCEPTED_TOKENS", ",");
        factoryAddress = deploy(deployerPrivateKey, deployerAddress, tokens, consumerEOA);
    }

    function deploy(
        uint256 deployerPrivateKey,
        address deployerAddress,
        address[] memory acceptedTokens,
        address consumerEOA
    ) internal returns (address factoryAddress) {
        vm.startBroadcast(deployerPrivateKey);

        GroupBillFactory gbf = new GroupBillFactory(
            deployerAddress,
            consumerEOA
        );
        gbf.setAcceptedTokens(acceptedTokens);
        factoryAddress = address(gbf);

        vm.stopBroadcast();
    }
}


contract TestDeployGroupBillFactory is DeployGroupBillFactory {
    function run()
        external
        override
        returns (address factoryAddress, address[] memory tokens)
    {
        uint256 deployerPrivateKey = vm.envUint("TEST_ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("TEST_ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("TEST_ETH_CONSUMER_EOA");

        tokens = vm.envAddress("TEST_ETH_ACCEPTED_TOKENS", ",");
        factoryAddress = super.deploy(deployerPrivateKey, deployerAddress, tokens, consumerEOA);
    }
}