// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/GroupBillFactory.sol";
import "../test/mocks/ERC20TokenMock.sol";
import {GroupBill} from "../src/GroupBill.sol";

contract DeployGroupBillFactory is Script {
    function run()
        external
        virtual
        returns (address factoryAddress, address[] memory tokens)
    {
        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("ETH_CONSUMER_EOA");

        tokens = vm.envAddress("ETH_ACCEPTED_TOKENS", ",");
        factoryAddress = deploy(
            deployerPrivateKey,
            deployerAddress,
            tokens,
            consumerEOA
        );
    }

    function deploy(
        uint256 deployerPrivateKey,
        address deployerAddress,
        address[] memory acceptedTokens,
        address consumerEOA
    ) internal returns (address factoryAddress) {
        vm.startBroadcast(deployerPrivateKey);
        bytes memory saltDonor = bytes("0xb8aa30d8f1d398883f0eeb5079777c42");
        bytes32 salt; // TODO: start exporting salt from the env vars and create if statement if salt is provided,
        // then execute with the salt, else just do pure contract creation (salt contract exec is to have the same address in consumer_api)
        assembly {
            salt := mload(add(saltDonor, 32))
        }

        GroupBillFactory gbf = new GroupBillFactory{salt: salt}(
            deployerAddress,
            consumerEOA
        );
        // uint a = 3;
        // GroupBillFactory gbf = new GroupBillFactory(
        //     deployerAddress,
        //     consumerEOA
        // );
        gbf.setAcceptedTokens(acceptedTokens);
        factoryAddress = address(gbf);
        console.log("Factory address:");
        console.logAddress(address(factoryAddress));

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
        factoryAddress = super.deploy(
            deployerPrivateKey,
            deployerAddress,
            tokens,
            consumerEOA
        );
    }
}

contract CreateGBContract is Script {
    function run() public {
        string
            memory testMnemonic = "test test test test test test test test test test test junk";

        (address participantAddress, ) = deriveRememberKey(testMnemonic, 1);

        GroupBillFactory gbf = GroupBillFactory(
            0x3F4BC9ddb63a9DAb307d86ffa266334da459F40C
        );
        address deployerAddress = vm.envAddress("ETH_OWNER_ADDRESS");
        address[] memory initialParticipants = new address[](1);
        initialParticipants[0] = deployerAddress;
        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        GroupBill groupBill = gbf.createNewGroupBill(0, initialParticipants);
        address[] memory newPeeps = new address[](1);
        newPeeps[0] = participantAddress;
        groupBill.addParticipants(newPeeps);
        // bytes32 expensesHash = groupBill.getExpensesHash();

        groupBill.addExpense(participantAddress, 1000000);
        vm.stopBroadcast();

        vm.startBroadcast(participantAddress);
        groupBill.join();
        groupBill.requestExpensePruning();

        // console.log("GroupBill state:");
        // console.logUint(uint(groupBill.getState()));
        // console.logUint(uint(groupBill.getParticipantState()));
        // console.logBool(
        //     groupBill.getParticipantState() == GroupBill.JoinState.JOINED
        // );
        vm.stopBroadcast();

        // vm.startBroadcast(deployerPrivateKey);
        // groupBill.requestExpensePruning();
        // vm.stopBroadcast();

        // groupBill.requestExpensePruning();

        // console.logAddress(address(groupBill));
    }
}
