// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract SigUtils {
    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    // computes the hash of a permit
    function getStructHash(
        Permit memory _permit
    ) internal pure returns (bytes32) {
        // bytes32 structHash = keccak256(
        //     abi.encode(
        //         PERMIT_TYPEHASH,
        //         owner,
        //         spender,
        //         value,
        //         _useNonce(owner),
        //         deadline
        //     )
        // );
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(
        Permit memory _permit,
        bytes32 domainSeparator
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    domainSeparator,
                    getStructHash(_permit)
                )
            );
    }
}
