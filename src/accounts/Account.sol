// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "forge-std/Script.sol";
import {IAccount} from "account-abstraction/contracts/interfaces/IAccount.sol";
import {IAccountExecute} from "account-abstraction/contracts/interfaces/IAccountExecute.sol";
import {PackedUserOperation} from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "../GroupBillAccessControl.sol";
import {GroupBill} from "../GroupBill.sol";
import {GroupBillFactory} from "../GroupBillFactory.sol";

error AccountFactory__ActionNotAllowed(address sender);
error Account__SenderIsNotAllowed(address sender);

struct PackedUOWithoutSignature {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    // bytes signature;
}

// ERC-4337 domain specific accounts
contract GroupBillAccount is IAccount, IAccountExecute {
    GroupBillAccessControl private immutable i_ac;
    address public immutable i_entryPoint;

    constructor(address entryPoint, address ac) {
        i_entryPoint = address(entryPoint);
        i_ac = GroupBillAccessControl(ac);
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public view override onlyEntryPoint returns (uint) {
        // TODO: with GroupBillFactoryAccount, <recovered> can be anybody (request limit must be enforced)
        // set in gas manager node per address rules (50 requests per address)
        bytes32 uoHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    userOp.sender,
                    userOp.nonce,
                    userOp.initCode,
                    userOp.callData,
                    userOp.accountGasLimits,
                    userOp.preVerificationGas,
                    userOp.gasFees,
                    userOp.paymasterAndData
                )
            )
        );
        address recovered = ECDSA.recover(uoHash, userOp.signature);

        // todo: maybe return 1
        require(
            i_ac.hasRole(PARTICIPANT_ROLE, recovered) && !i_ac.hasRole(BLACKLIST_ROLE, recovered),
            "Address either doesn't have sufficient participant permission or is blacklisted"
        );

        return 0; // return "successful validation" result
    }

    function executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) public override onlyEntryPoint {
        (address groupBillAddress, bytes memory userSignedCalldata) = abi.decode(userOp.callData, (address, bytes));

        console.log("group bill address");
        console.logAddress(groupBillAddress);

        bytes32 uoHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    PackedUOWithoutSignature({
                        sender: userOp.sender,
                        nonce: userOp.nonce,
                        initCode: userOp.initCode,
                        callData: userOp.callData,
                        accountGasLimits: userOp.accountGasLimits,
                        preVerificationGas: userOp.preVerificationGas,
                        gasFees: userOp.gasFees,
                        paymasterAndData: userOp.paymasterAndData
                    })
                )
            )
        );
        address recovered = ECDSA.recover(uoHash, userOp.signature);

        console.log("Calling group bill with calldata");

        GroupBill gb = GroupBill(groupBillAddress);
        gb.executeOperation(userSignedCalldata, recovered);

        // address[] memory allParticipants = gb.getParticipants();
        // for (uint i = 0; i < allParticipants.length; i++) {
        //     console.log("participant");
        //     console.logAddress(allParticipants[i]);
        // }
        // console.log(gb.getName());
        // gb.testMethod(bytes("32"));
        // https://ethereum.stackexchange.com/questions/6354/how-do-i-construct-a-call-to-another-contract-using-inline-assembly

        // execute user operation either by calling group bill factory or group bill
    }

    modifier onlyEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert AccountFactory__ActionNotAllowed(msg.sender);
        }
        _;
    }
}

contract GroupBillFactoryAccount is IAccount, IAccountExecute {
    GroupBillAccessControl private i_ac;
    address private immutable i_entryPoint;
    // address public entryPoint;

    constructor(address entryPoint, address ac) {
        i_entryPoint = address(entryPoint);
        i_ac = GroupBillAccessControl(ac);
    }

    function executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) public override {
        (address groupBillAddress, bytes memory userSignedCalldata) = abi.decode(userOp.callData, (address, bytes));
        // https://ethereum.stackexchange.com/questions/6354/how-do-i-construct-a-call-to-another-contract-using-inline-assembly

        bytes32 uoHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    userOp.sender,
                    userOp.nonce,
                    userOp.initCode,
                    userOp.callData,
                    userOp.accountGasLimits,
                    userOp.preVerificationGas,
                    userOp.gasFees,
                    userOp.paymasterAndData
                )
            )
        );
        address recovered = ECDSA.recover(uoHash, userOp.signature);

        (address gbfAddress, bytes memory callData) = abi.decode(userOp.callData, (address, bytes));
        GroupBillFactory gbf = GroupBillFactory(gbfAddress);

        gbf.executeOperation(userSignedCalldata, recovered);

        // TODO: <recovered> must be in the list of participants/allowed users of the group bill
        // TODO: with GroupBillFactoryAccount, <recovered> can be anybody (request limit must be enforced)
        // set in gas manager node per address rules (50 requests per address)
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public view override returns (uint) {
        bytes32 uoHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    userOp.sender,
                    userOp.nonce,
                    userOp.initCode,
                    userOp.callData,
                    userOp.accountGasLimits,
                    userOp.preVerificationGas,
                    userOp.gasFees,
                    userOp.paymasterAndData
                )
            )
        );
        address recovered = ECDSA.recover(uoHash, userOp.signature);
        require(
            (i_ac.hasRole(GROUP_BILL_CREATOR_ROLE, recovered) && !i_ac.hasRole(BLACKLIST_ROLE, recovered)),
            "User has to be a gb creator and not be blacklisted"
        );
        return 0; // return "successful validation" result
    }
}

/// @dev GBAccountFactory will not be required
/// initCode is 0, and sender is passed directly to the entryPoint once it's deployed
contract GBAccountFactory {
    address private s_entryPoint;

    address public groupBillAccount;
    address public groupBillFactoryAccount;

    constructor(address entryPointAddress, address _groupBillAccount, address _groupBillFactoryAccount) {
        s_entryPoint = entryPointAddress;

        groupBillAccount = _groupBillAccount;
        groupBillFactoryAccount = _groupBillFactoryAccount;
    }

    function getGroupBillAccount() public view returns (GroupBillAccount) {
        return GroupBillAccount(groupBillAccount);
    }

    function getGroupBillFactoryAccount() public view returns (GroupBillFactoryAccount) {
        return GroupBillFactoryAccount(groupBillFactoryAccount);
    }

    function setGroupBillAccount(address _groupBillAccount) public onlyEntryPoint {
        groupBillAccount = _groupBillAccount;
    }

    function setGroupBillFactoryAccount(address _groupBillFactoryAccount) public onlyEntryPoint {
        groupBillFactoryAccount = _groupBillFactoryAccount;
    }

    modifier onlyEntryPoint() {
        if (msg.sender != s_entryPoint) {
            revert AccountFactory__ActionNotAllowed(msg.sender);
        }
        _;
    }
}
