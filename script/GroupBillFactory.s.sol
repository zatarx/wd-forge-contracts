// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "../src/GroupBillFactory.sol";
import "../src/GroupBillAccessControl.sol";
import {SigUtils} from "../src/SigUtils.sol";
import {IPermit2} from "../src/Utils.sol";
import "../test/mocks/ERC20TokenMock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GroupBill, Expense, BorrowerAmount, LenderAmount, PostPruningBorrowerExpense} from "../src/GroupBill.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {GroupBillFactoryAccount, GroupBillAccount} from "../src/accounts/Account.sol";
import {GroupBillPaymaster} from "../src/accounts/Paymaster.sol";
import {DeployEntryPointAndAccounts} from "./ERC4337Accounts.s.sol";

import "account-abstraction/contracts/interfaces/IEntryPoint.sol";
error GBFDeploy__AccountConfigError(address gbfAccount, address gbAccount);

contract DeployGroupBillFactory is Script {
    function run() external virtual returns (address factoryAddress, address groupBill, address[] memory tokens) {
        console.log("--------Group Bill Factory Deployment--------");

        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("ETH_CONSUMER_EOA");
        // TODO: move permit2Address into deploy method
        address permit2Addr = vm.envOr("ETH_PERMIT2_ADDRESS", address(0));

        // ERC-4337 addresses
        // address entryPoint = vm.envOr("ENTRY_POINT_ADDRESS", address(0));
        address gbfAccount = vm.envOr("GB_FACTORY_ACCOUNT_ADDRESS", address(0));
        address gbAccount = vm.envOr("GROUP_BILL_ACCOUNT_ADDRESS", address(0));

        bool deployEPAndAccounts = vm.envOr("DEPLOY_EP_AND_ACCOUNTS", false);
        if (deployEPAndAccounts) {
            console.log("Deploying EP & Accounts");
            (gbfAccount, gbAccount) = (new DeployEntryPointAndAccounts()).run();
        }

        if (gbfAccount == address(0) || gbAccount == address(0)) {
            revert GBFDeploy__AccountConfigError(gbfAccount, gbAccount);
        }

        tokens = vm.envAddress("ETH_ACCEPTED_TOKENS", ",");
        factoryAddress = deploy(
            deployerPrivateKey,
            deployerAddress,
            tokens,
            consumerEOA,
            permit2Addr,
            gbfAccount,
            gbAccount
        );
    }

    function deploy(
        uint256 deployerPrivateKey,
        address deployerAddress,
        address[] memory acceptedTokens,
        address consumerEOA,
        address permit2Addr,
        address gbfAccount,
        address gbAccount
    ) internal returns (address factoryAddress) {
        IPermit2 permit2;

        bool deployEPAndAccounts = vm.envOr("DEPLOY_EP_AND_ACCOUNTS", false);
        if (deployEPAndAccounts) {
            console.log("Deploying EP & Accounts");
            (gbfAccount, gbAccount) = (new DeployEntryPointAndAccounts()).run();
        }

        if (gbfAccount == address(0) || gbAccount == address(0)) {
            revert GBFDeploy__AccountConfigError(gbfAccount, gbAccount);
        }

        if (permit2Addr == address(0)) {
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

        address paymaster = vm.envOr("PAYMASTER_ADDRESS", address(0));
        GroupBillAccessControl ac = GroupBillAccessControl(vm.envAddress("GROUP_BILL_AC_ADDRESS"));

        GroupBillFactory gbf = new GroupBillFactory(
            deployerAddress,
            consumerEOA,
            gbfAccount,
            gbAccount,
            address(ac),
            permit2
        );
        gbf.setAcceptedTokens(acceptedTokens);
        factoryAddress = address(gbf);

        ac.grantRole(OWNER_ROLE, factoryAddress);
        ac.grantRole(OWNER_ROLE, address(this));
        ac.grantRole(PAYMASTER_COVERABLE_ROLE, factoryAddress);

        console.log("Factory address:");
        console.logAddress(address(factoryAddress));

        if (paymaster == address(0)) {
            IEntryPoint entryPoint = IEntryPoint(GroupBillAccount(gbAccount).i_entryPoint());
            // address[] memory initialEditors = new address[](1);
            // initialEditors[0] = factoryAddress;
            paymaster = address(new GroupBillPaymaster(entryPoint, address(ac)));
        }
        vm.stopBroadcast();
    }
}

contract TestDeployGroupBillFactory is DeployGroupBillFactory {
    function run() external override returns (address factoryAddress, address gbAddress, address[] memory tokens) {
        uint256 deployerPrivateKey = vm.envUint("TEST_ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("TEST_ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("TEST_ETH_CONSUMER_EOA");

        tokens = vm.envAddress("TEST_ETH_ACCEPTED_TOKENS", ",");
        factoryAddress = super.deploy(
            deployerPrivateKey,
            deployerAddress,
            tokens,
            consumerEOA,
            address(0), // to manually create permit2 contract from its original bytescode
            address(0), // to manually create EntryPoint, GroupBillAccount and GroupBillFactoryAccount (ERC-4337)
            address(0)
        );
    }
}

// todo: put it in tests
contract GBE2ETest is DeployGroupBillFactory {
    using PermitHash for IAllowanceTransfer.PermitSingle;

    mapping(address => uint) private s_nonces;
    address private s_trustedAccount;

    function nonces(address user) public returns (uint nonce) {
        nonce = s_nonces[user];
        s_nonces[user] += 1;
    }

    function setTrustedAccount(address trustedAccount) public {
        s_trustedAccount = trustedAccount;
    }

    function run() public override returns (address factoryAddress, address gbAddress, address[] memory tokens) {
        uint256 deployerPrivateKey = vm.envUint("TEST_ETH_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("TEST_ETH_OWNER_ADDRESS");
        address consumerEOA = vm.envAddress("TEST_ETH_CONSUMER_EOA");

        string memory testMnemonic = "test test test test test test test test test test test junk";

        uint256 participantPrivateKey = vm.deriveKey(testMnemonic, 1);
        address participantAddress = vm.rememberKey(participantPrivateKey);

        console.log("Declaration of participant keys:");
        console.logUint(participantPrivateKey);
        console.logAddress(participantAddress);

        GroupBillFactory gbf = GroupBillFactory(vm.envAddress("GROUP_BILL_FACTORY_CONRACT_ID"));
        // factoryAddress = address(gbf);

        address[] memory initialParticipants = new address[](1);
        initialParticipants[0] = deployerAddress;

        vm.startPrank(deployerAddress);

        MockToken token = new MockToken("TEST_TOKEN", "TST");
        tokens = new address[](1);
        tokens[0] = address(token);

        console.log("deployer's balance");
        console.logUint(token.balanceOf(deployerAddress));

        gbf.setAcceptedTokens(tokens);
        // send to participant some of the mock tokens
        token.approve(participantAddress, 2e18);
        token.transfer(participantAddress, 2e18);

        console.log("Participant's token balance");
        console.log(token.balanceOf(participantAddress));
        console.log("deployer's balance");
        console.logUint(token.balanceOf(deployerAddress));

        vm.stopPrank();

        vm.startPrank(gbf.s_trustedAccount());

        // set signer as first deployer address
        gbf.setPerpetualSigner(deployerAddress);

        GroupBill groupBill = gbf.createNewGroupBill(0, initialParticipants);
        // address groupBillAddress = abi.decode(data, (address));
        // GroupBill groupBill = GroupBill(groupBillAddress);
        vm.stopPrank();

        vm.startPrank(groupBill.s_trustedAccount());

        groupBill.setPerpetualSigner(deployerAddress);

        groupBill.setName("Whistler trip");
        gbAddress = address(groupBill);

        // vm.stopPrank();

        // vm.startBroadcast(deployerPrivateKey);

        address[] memory newPeeps = new address[](1);
        newPeeps[0] = participantAddress;
        groupBill.addParticipants(newPeeps);

        // bytes32 expensesHash = groupBill.getExpensesHash();
        BorrowerAmount[] memory borrowerAmounts = new BorrowerAmount[](1);
        borrowerAmounts[0] = BorrowerAmount({borrower: participantAddress, amount: 1e18});

        groupBill.submitExpense(borrowerAmounts, "Booze");

        Expense[] memory expenses = groupBill.getFlatExpenses();
        console.log("GroupBillFactory.s.sol: Expenses length:");
        console.logUint(expenses.length);

        groupBill.setPerpetualSigner(participantAddress);
        groupBill.join();
        groupBill.requestExpensePruning();

        // @notice participant owes to deployer, participant - borrower, deployer - lender

        uint totalAmount = 1e18;
        LenderAmount[] memory las = new LenderAmount[](1);
        las[0] = LenderAmount({lender: deployerAddress, amount: totalAmount});

        PostPruningBorrowerExpense[] memory ppBorrowerExpenses = new PostPruningBorrowerExpense[](1);
        ppBorrowerExpenses[0] = PostPruningBorrowerExpense({
            borrower: participantAddress,
            totalAmount: totalAmount,
            lenderAmounts: las
        });

        bytes32 expensesHash = groupBill.getExpensesHash();

        groupBill.setPerpetualSigner(consumerEOA);

        console.log("Consumer EOA address from group bill");
        console.logAddress(groupBill.i_consumerEOA());

        groupBill.submitPostPruningBorrowerExpenses(ppBorrowerExpenses, expensesHash);

        groupBill.setPerpetualSigner(participantAddress);
        uint256 totalParticipantLoan = groupBill.getPostPruningSenderTotalLoan();

        console.log("total loan");
        console.logUint(totalParticipantLoan);

        IAllowanceTransfer.PermitDetails memory permitDetails = IAllowanceTransfer.PermitDetails({
            token: address(token),
            amount: uint160(totalParticipantLoan + groupBill.getTxFee()),
            expiration: uint48(vm.getBlockTimestamp() + 5 minutes),
            nonce: uint48(this.nonces(participantAddress))
        });
        IAllowanceTransfer.PermitSingle memory singlePermit = IAllowanceTransfer.PermitSingle({
            details: permitDetails,
            spender: address(groupBill),
            sigDeadline: uint256(permitDetails.expiration + 1 days)
        });
        vm.stopPrank();

        vm.startPrank(participantAddress);

        IPermit2 permit2 = groupBill.i_permit2();
        token.approve(address(permit2), type(uint160).max);

        vm.stopPrank();

        vm.startPrank(groupBill.s_trustedAccount());

        SigUtils utils = new SigUtils(permit2);
        bytes32 typedHash = utils.hashTypedData(singlePermit.hash());

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(participantPrivateKey, typedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        groupBill.setPerpetualSigner(participantAddress);
        // vm.broadcast(participantPrivateKey);

        groupBill.permit(singlePermit, signature);

        console.log("check message signer");
        console.logAddress(groupBill.s_msgSigner());
        console.logAddress(participantAddress);
        (uint160 amount, , ) = permit2.allowance(participantAddress, address(token), address(groupBill));
        console.logUint(amount);
        console.log("Group bill address");
        console.logAddress(address(groupBill));
        console.log("participant current token balance");
        console.logUint(token.balanceOf(participantAddress));

        // vm.startBroadcast(deployerAddress);
        groupBill.setPerpetualSigner(deployerAddress);
        groupBill.settle();

        console.logUint(groupBill.getCoreTokenBalance());
        console.logUint(token.balanceOf(deployerAddress));

        vm.stopPrank();
    }
}

contract CheckGBScript is Script {
    function run() public {
        string memory testMnemonic = "test test test test test test test test test test test junk";

        (address participantAddress, ) = deriveRememberKey(testMnemonic, 1);
        GroupBill bill = GroupBill(0xa16E02E87b7454126E5E10d957A927A7F5B5d2be);

        console.logUint(uint(bill.s_state()));
    }
}
