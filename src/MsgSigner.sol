// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
error MsgSigner__AccountNotAllowed(address sender);

// ERC4337 message signer (eoa that initiates & signs a uo)

error MsgSigner__OperationExecutionFailed(string errorMessage);

abstract contract MsgSigner {
    address public s_msgSigner;
    address public s_trustedAccount;

    constructor(address trustedAccount) {
        s_trustedAccount = trustedAccount;
    }

    function executeOperation(
        bytes calldata userCalldata,
        address recovered
    ) public onlyTrustedAccount returns (bytes memory) {
        setSigner(recovered);

        (bool success, bytes memory data) = address(this).call(userCalldata);
        if (!success) {
            assembly {
                revert(add(data, 0x20), mload(data))
            }
            // string memory errorMessage = abi.decode(data, (string));
            // revert MsgSigner__OperationExecutionFailed(errorMessage);
        }
        setSigner(address(0));

        return data;
    }

    function setSigner(address signer) private {
        s_msgSigner = signer;
    }

    function setPerpetualSigner(address signer) external onlyTrustedAccount {
        /** @dev this method is for testing purposes only */
        setSigner(signer);
    }

    modifier onlyTrustedAccount() {
        if (msg.sender != s_trustedAccount) {
            revert MsgSigner__AccountNotAllowed(msg.sender);
        }
        _;
    }
}
