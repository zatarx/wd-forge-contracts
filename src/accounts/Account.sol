// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "forge-std/Script.sol";
import {IAccount} from "account-abstraction/contracts/interfaces/IAccount.sol";
import {IAccountExecute} from "account-abstraction/contracts/interfaces/IAccountExecute.sol";
import {PackedUserOperation} from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {GroupBill} from "../GroupBill.sol";

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
    address public entryPoint;

    constructor(address entryPointAddress) {
        entryPoint = entryPointAddress;
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public view onlyEntryPoint override returns (uint) {
        // check the signature of the wallet signer (user signs the transaction and we verify that it was the user who signed)
        // interpret calldata
        // assembly:
        // .method_signature(method_signature_params)

        // pass all the fields from PackedUserOperation except for the signature

        // TODO: make sure that the the msg.sender equals the entrypoint address
        // if (entryPoint != msg.sender) {
        //     revert Account__SenderIsNotAllowed(msg.sender);
        // }

        // TODO: <recovered> must be in the list of participants/allowed users of the group bill
        // REVISION: <recovered> is assigned to the contract msgSigner field and then the op gets called -->
        // --> if there're any modifiers on the function, they'll check that msgSigner/recovered is allowed

        // TODO: with GroupBillFactoryAccount, <recovered> can be anybody (request limit must be enforced)
        // set in gas manager node per address rules (50 requests per address)

        return 0; // return "successful validation" result
    }

    function executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) public onlyEntryPoint override {
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
        address[] memory allParticipants = gb.getParticipants();
        for (uint i = 0; i < allParticipants.length; i++) {
            console.log("participant");
            console.logAddress(allParticipants[i]);
        }
        // console.log(gb.getName());
        // gb.testMethod(bytes("32"));
        // https://ethereum.stackexchange.com/questions/6354/how-do-i-construct-a-call-to-another-contract-using-inline-assembly

        // execute user operation either by calling group bill factory or group bill
    }

    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) {
            revert AccountFactory__ActionNotAllowed(msg.sender);
        }
        _;
    }
}

contract GroupBillFactoryAccount is IAccount, IAccountExecute {
    address public entryPoint;

    constructor(address entryPointAddress) {
        entryPoint = entryPointAddress;
    }

    function executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) public override {
        (address groupBillAddress, bytes memory callData) = abi.decode(userOp.callData, (address, bytes));
        // https://ethereum.stackexchange.com/questions/6354/how-do-i-construct-a-call-to-another-contract-using-inline-assembly

        // execute user operation either by calling group bill factory or group bill
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public pure override returns (uint) {
        // check the signature of the wallet signer (user signs the transaction and we verify that it was the user who signed)
        // interpret calldata
        // assembly:
        // .method_signature(method_signature_params)

        // pass all the fields from PackedUserOperation except for the signature
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

        // TODO: <recovered> must be in the list of participants/allowed users of the group bill
        // TODO: with GroupBillFactoryAccount, <recovered> can be anybody (request limit must be enforced)
        // set in gas manager node per address rules (50 requests per address)

        return 0; // return "successful validation" result
    }
}

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




// contract GroupBillAccount is GroupBill, IAccount, IAccountExecute {
//     address private immutable i_trustedForwarder;

//     // constructor(
//     //     address groupBillOwner,
//     //     IERC20 coreToken,
//     //     address[] memory initialParticipants,
//     //     address consumerEOA,
//     //     IPermit2 permit2,
//     //     address trustedForwarder
//     // ) GroupBill(groupBillOwner, coreToken, initialParticipants, consumerEOA, permit2) {
//     //     i_trustedForwarder = trustedForwarder; // entrypoint address
//     // }

//     // function _msgSender() internal view returns (address payable signer) {
//     //     signer = msg.sender;
//     //     if (msg.data.length >= 20 && isTrustedForwarder(signer)) {
//     //         assembly {
//     //             signer := shr(96, calldataload(sub(calldatasize(), 20)))
//     //         }
//     //     }
//     // }

//     // function isTrustedForwarder(address forwarderAddress) private returns (bool) {
//     //     return forwarderAddress == i_trustedForwarder;
//     // }
//     function validateUserOp(
//         PackedUserOperation calldata userOp,
//         bytes32 userOpHash,
//         uint256 missingAccountFunds
//     ) public pure {
//         // check the signature of the wallet signer (user signs the transaction and we verify that it was the user who signed)
//         // interpret calldata
//         // assembly:
//         // .method_signature(method_signature_params)
//         return 0; // return "successful validation" result
//     }

//     function executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) public {
//         // execute user operation either by calling group bill factory or group bill
//     }
// }

// // gets deployed by the owner
// contract GroupBillFactoryAccount {
//     // constructor(
//     //     address initialOwner,
//     //     address consumerEOA,
//     //     IPermit2 permit2
//     // ) GroupBillFactory(initialOwner, consumerEOA, permit2) {}

//     function createGroupBillAccount(
//         address groupBillOwner,
//         IERC20 coreToken,
//         address[] memory initialParticipants,
//         address consumerEOA,
//         IPermit2 permit2
//     // ) external onlyOwner returns (address) {
//     ) external returns (address) {
//         GroupBillAccount acc = new GroupBillAccount(
//             groupBillOwner,
//             coreToken,
//             initialParticipants,
//             consumerEOA,
//             permit2
//         );

//         return address(acc);
//     }
// }

// WIP: TODO: integrate aa factory of factories to have a unique workflow of classes for each scenario (ref. Abstract Factory Pattern)
// contract AccountAbstractFactory is Ownable {
//     mapping(bytes => address) private immutable i_factoryMapping;

//     constructor(
//         address initialOwner,
//         bytes[] memory factoryTypes,
//         address[] memory factoryAddresses
//     ) Ownable(initialOwner) {
//         for (uint i = 0; i < factoryTypes.length; i++) {
//             i_factoryMapping[factoryTypes[i]] = factoryAddresses[i];
//         }
//     }

//     function createAccount(string factoryType, bytes calldata factoryCreationCalldata) public {
//         address factory = i_factoryMapping[factoryType];
//         // FactoryClass(factory) must make a call with factoryCreationCalldata (see how to do it with assembly)
//     }
// }