// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/GroupBillFactory.sol";
import {SigUtils} from "../src/SigUtils.sol";
import {IPermit2} from "../src/Utils.sol";
import "../test/mocks/ERC20TokenMock.sol";
import {GroupBill, Expense} from "../src/GroupBill.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";

contract DeployGroupBillFactory is Script {
    function run()
        external
        virtual
        returns (address factoryAddress, address[] memory tokens)
    {
        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("ETH_CONSUMER_EOA");
        address permit2Address = vm.envAddress("ETH_PERMIT2_ADDRESS");

        tokens = vm.envAddress("ETH_ACCEPTED_TOKENS", ",");
        factoryAddress = deploy(
            deployerPrivateKey,
            deployerAddress,
            tokens,
            consumerEOA,
            permit2Address
        );
    }

    function deploy(
        uint256 deployerPrivateKey,
        address deployerAddress,
        address[] memory acceptedTokens,
        address consumerEOA,
        address permit2Address
    ) internal returns (address factoryAddress) {
        IPermit2 permit2;

        if (permit2Address == address(0)) {
            address deployed;
            bytes memory bytecode = vm.getCode("Permit2.sol");

            vm.broadcast(deployerAddress);
            assembly {
                deployed := create(0, add(bytecode, 0x20), mload(bytecode))
            }
            vm.etch(0x000000000022D473030F116dDEE9F6B43aC78BA3, deployed.code);

            permit2 = IPermit2(deployed);
        } else {
            permit2 = IPermit2(vm.envAddress("ETH_PERMIT2_ADDRESS"));
        }
        vm.startBroadcast(deployerPrivateKey);

        GroupBillFactory gbf = new GroupBillFactory(
            deployerAddress,
            consumerEOA,
            permit2
        );
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
            consumerEOA,
            address(0) // to manually create permit2 contract from its original bytescode
        );
    }
}

contract CreateGBContract is DeployGroupBillFactory {
    using PermitHash for IAllowanceTransfer.PermitSingle;
    mapping(address => uint) private s_nonces;

    function nonces(address user) public returns (uint nonce) {
        nonce = s_nonces[user];
        s_nonces[user] += 1;
    }

    function run()
        public
        override
        returns (address factoryAddress, address[] memory tokens)
    {
        uint256 deployerPrivateKey = vm.envUint("TEST_ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("TEST_ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("TEST_ETH_CONSUMER_EOA");

        vm.broadcast(deployerPrivateKey);
        MockToken token = new MockToken("TEST_TOKEN", "TST");

        tokens = new address[](1);
        tokens[0] = address(token);

        factoryAddress = super.deploy(
            deployerPrivateKey,
            deployerAddress,
            tokens,
            consumerEOA,
            address(0)
        );

        string
            memory testMnemonic = "test test test test test test test test test test test junk";

        uint256 participantPrivateKey = vm.deriveKey(testMnemonic, 1);
        address participantAddress = vm.rememberKey(participantPrivateKey);
        console.log("Declaration of participant keys:");
        console.logUint(participantPrivateKey);
        console.logAddress(participantAddress);

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

        vm.startBroadcast(participantPrivateKey);
        groupBill.approveTokenSpend(type(uint160).max);

        uint256 totalParticipantLoan = groupBill.getSenderTotalLoan();
        IAllowanceTransfer.PermitDetails
            memory permitDetails = IAllowanceTransfer.PermitDetails({
                token: address(token),
                amount: uint160(
                    totalParticipantLoan +
                        groupBill.getTxFee(token, totalParticipantLoan)
                ),
                expiration: uint48(vm.getBlockTimestamp() + 5 minutes),
                nonce: uint48(this.nonces(participantAddress))
            });
        IAllowanceTransfer.PermitSingle memory singlePermit = IAllowanceTransfer
            .PermitSingle({
                details: permitDetails,
                spender: address(groupBill),
                sigDeadline: uint256(permitDetails.expiration + 1 days)
            });

        IPermit2 permit2 = groupBill.getPermit2();
        SigUtils utils = new SigUtils(permit2);
        bytes32 typedHash = utils.hashTypedData(singlePermit.hash());

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            participantPrivateKey,
            typedHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint160 amount, uint48 expiration, uint48 nonce) = permit2.allowance(
            participantAddress,
            address(token),
            address(groupBill)
        );
        console.log("script: nonces:");
        // console.logAddress(participantAddress);
        // permit2.permit(participantAddress, singlePermit, signature);
        // vm.stopBroadcast();

        // vm.broadcast(participantPrivateKey);
        vm.stopBroadcast();

        vm.broadcast(participantAddress);
        groupBill.permitEx(
            participantAddress,
            singlePermit,
            signature,
            permit2
        );

        // vm.stopBroadcast();

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
