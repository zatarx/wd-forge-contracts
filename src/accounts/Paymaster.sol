// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {BasePaymaster} from "account-abstraction/contracts/core/BasePaymaster.sol";
import {IEntryPoint} from "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {PackedUserOperation} from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "../GroupBillAccessControl.sol";

event GBPaymaster__NewSenderAdded(address sender);

/**
 * @dev Paymaster for Group Bill arbitrary contract calldata execution
 * To elaborate, userOp provides the sender and calldata,
 * which contains <logicContractAddress>, <userDefinedCalldata> after decoding
 * both sender and <logicContractAddress> has to have been given permissions by the AC
 */
contract GroupBillPaymaster is BasePaymaster {
    GroupBillAccessControl private immutable i_ac;

    constructor(IEntryPoint _entryPoint, address ac) BasePaymaster(_entryPoint) {
        // s_allowedSenders = allowedSenders;
        i_ac = GroupBillAccessControl(ac);
    }

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal override returns (bytes memory context, uint256 validationData) {
        /// @dev make sure that both sender & uo user(signer) defined logic contract address gas can be covered

        (address logicContractAddress, ) = abi.decode(userOp.callData, (address, bytes));
        require(
            i_ac.hasRole(PAYMASTER_COVERABLE_ROLE, userOp.sender),
            "UserOp sender must have PAYMASTER_COVERABLE role"
        );
        require(
            i_ac.hasRole(PAYMASTER_COVERABLE_ROLE, logicContractAddress),
            "User defined calldata logic address has to have PAYMASTER_COVERABLE role"
        );

        // empty context and validationData
        (context, validationData) = (bytes(""), 0);
    }

    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        return;
    }
}
