// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {CreateGBContract} from "./GroupBillFactory.s.sol";
import {GroupBill} from "../src/GroupBill.sol";

import {PackedUserOperation} from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {GroupBillAccount} from "../src/accounts/Account.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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

contract DeployEntryPoint is Script {
    address[] public participants;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");

        EntryPoint ep = new EntryPoint();

        GroupBillAccount acc = new GroupBillAccount(address(ep));
        CreateGBContract gbContract = new CreateGBContract();
        gbContract.setTrustedAccount(address(acc));

        (address factoryAddress, address gbAddress, ) = gbContract.run();
        console.log("---------EPTesting logs below----------");
        console.log("group bill address");
        console.logAddress(gbAddress);

        vm.startBroadcast(deployerPrivateKey);

        // bytes callData = abi.encode(address())
        string memory testMnemonic = "test test test test test test test test test test test junk";

        uint256 participantPrivateKey = vm.deriveKey(testMnemonic, 3);
        address participantAddress = vm.rememberKey(participantPrivateKey);

        console.log("New participant's address");
        console.log(participantAddress);

        participants.push(participantAddress);
        bytes memory encodedGBCall = abi.encodeCall(GroupBill.addParticipants, (participants));

        PackedUOWithoutSignature memory helperUO = PackedUOWithoutSignature({
            sender: address(acc),
            nonce: 1,
            initCode: abi.encode(),
            callData: abi.encode(
                gbAddress,
                // abi.encodeWithSignature("addParticipants(address[] memory)", vm.randomAddress())
                encodedGBCall
            ),
            accountGasLimits: bytes32("2000000"),
            preVerificationGas: 2000000,
            gasFees: bytes32("30000"),
            paymasterAndData: abi.encode()
            // signature: signature
        });
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encode(helperUO)));

        // bytes memory signature = ecrecover(digest, /* v */, /* r */, /* s */);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, bytes1(v));

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: helperUO.sender,
            nonce: helperUO.nonce,
            initCode: helperUO.initCode,
            callData: helperUO.callData,
            accountGasLimits: helperUO.accountGasLimits,
            preVerificationGas: helperUO.preVerificationGas,
            gasFees: helperUO.gasFees,
            paymasterAndData: helperUO.paymasterAndData,
            signature: signature
        });

        acc.validateUserOp(userOp, bytes32("fdsf"), 0);
        acc.executeUserOp(userOp, bytes32("fsdf"));

        // ep.handleOps();

        vm.stopBroadcast();
    }
}
