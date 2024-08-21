// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/GroupBillFactory.sol";
import {SigUtils} from "../src/SigUtils.sol";
import "../test/mocks/ERC20TokenMock.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {GroupBill, Expense} from "../src/GroupBill.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
// import {Permit2} from "permit2/src/Permit2.sol";

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
        // bytes memory saltDonor = bytes("0xb8aa30d8f1d398883f0eeb5079777c42");
        // bytes32 salt; // TODO: start exporting salt from the env vars and create if statement if salt is provided,
        // then execute with the salt, else just do pure contract creation (salt contract exec is to have the same address in consumer_api)
        // assembly {
        //     salt := mload(add(saltDonor, 32))
        // }

        GroupBillFactory gbf = new GroupBillFactory(
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

contract CreateGBContract is DeployGroupBillFactory {
    function run()
        public
        override
        returns (address factoryAddress, address[] memory tokens)
    {
        uint256 deployerPrivateKey = vm.envUint("TEST_ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("TEST_ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("TEST_ETH_CONSUMER_EOA");

        vm.prank(deployerAddress);
        MockPermitToken token = new MockPermitToken("TEST_TOKEN", "TST");

        tokens = new address[](1);
        tokens[0] = address(token);

        factoryAddress = super.deploy(
            deployerPrivateKey,
            deployerAddress,
            tokens,
            consumerEOA
        );

        string
            memory testMnemonic = "test test test test test test test test test test test junk";

        (address participantAddress, ) = deriveRememberKey(testMnemonic, 1);
        uint256 participantPrivateKey = vm.deriveKey(testMnemonic, 1);

        GroupBillFactory gbf = GroupBillFactory(factoryAddress);
        address[] memory initialParticipants = new address[](1);
        initialParticipants[0] = deployerAddress;

        vm.startBroadcast(deployerPrivateKey);
        // send to participant some of the mock tokens
        token.approve(participantAddress, 2e18);
        token.transfer(participantAddress, 2e18);

        console.log("Participant's token balance");
        console.log(token.balanceOf(participantAddress));

        GroupBill groupBill = gbf.createNewGroupBill(0, initialParticipants);
        groupBill.setName("Whistler trip");


        address[] memory newPeeps = new address[](1);
        newPeeps[0] = participantAddress;
        groupBill.addParticipants(newPeeps);
        // bytes32 expensesHash = groupBill.getExpensesHash();

        groupBill.addExpense(participantAddress, 1e18);

        vm.stopBroadcast();

        vm.startBroadcast(participantAddress);
        groupBill.join();
        groupBill.requestExpensePruning();
        vm.stopBroadcast();

        vm.startBroadcast(deployerAddress);
        // submit submitExpensesAfterPruning
        Expense[] memory expenses = new Expense[](1);
        expenses[0] = Expense({
            borrower: participantAddress,
            lender: deployerAddress,
            amount: 1e18
        });
        groupBill.submitExpensesAfterPruning(
            expenses,
            groupBill.getExpensesHash()
        );

        vm.stopBroadcast();

        vm.startBroadcast(participantAddress);

        uint256 totalParticipantLoan = groupBill.getSenderTotalLoan();
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: participantAddress,
            spender: address(groupBill),
            value: totalParticipantLoan +
                groupBill.getTxFee(token, totalParticipantLoan),
            nonce: token.nonces(participantAddress),
            deadline: vm.getBlockTimestamp() + 5 days
        });

        SigUtils utils = new SigUtils();
        bytes32 typedHash = utils.getTypedDataHash(
            permit,
            token.DOMAIN_SEPARATOR()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            participantPrivateKey,
            typedHash
        );
        console.log("permit deadline offchain (client side):");
        console.logUint(permit.deadline);
        groupBill.permit(permit, v, r, s);


        vm.stopBroadcast();

        // console.log(totalParticipantLoan);
        // console.logAddress(factoryAddress);
        // console.logAddress(address(groupBill));

        // vm.startBroadcast(deployerPrivateKey);
        // groupBill.requestExpensePruning();
        // vm.stopBroadcast();

        // groupBill.requestExpensePruning();

        // console.logAddress(address(groupBill));
    }
}

contract CheckGBScript is Script {
    function run() public {
        string
            memory testMnemonic = "test test test test test test test test test test test junk";

        (address participantAddress, ) = deriveRememberKey(testMnemonic, 1);
        GroupBill bill = GroupBill(0xa16E02E87b7454126E5E10d957A927A7F5B5d2be);

        console.logUint(uint(bill.getState()));
    }
}

contract ExpensePruningRequestContract is Script {
    function run() public {
        string
            memory testMnemonic = "test test test test test test test test test test test junk";

        (address participantAddress, ) = deriveRememberKey(testMnemonic, 1);
        GroupBill bill = GroupBill(0xa16E02E87b7454126E5E10d957A927A7F5B5d2be);

        // groupBill.addParticipants(newPeeps);
        // bytes32 expensesHash = groupBill.getExpensesHash();
        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        bill.addExpense(participantAddress, 2000000);
        vm.stopBroadcast();

        vm.startBroadcast(participantAddress);
        // groupBill.join();
        bill.requestExpensePruning();

        // console.log("GroupBill state:");
        // console.logUint(uint(groupBill.getState()));
        // console.logUint(uint(groupBill.getParticipantState()));
        // console.logBool(
        //     groupBill.getParticipantState() == GroupBill.JoinState.JOINED
        // );
        vm.stopBroadcast();
    }
}
