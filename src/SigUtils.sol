// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract SigUtils {
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private constant _HASHED_NAME = keccak256("Permit2");
    bytes32 private constant _TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    constructor() {
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(
            _TYPE_HASH,
            _HASHED_NAME
        );
    }

    /// @notice Returns the domain separator for the current chain.
    /// @dev Uses cached version if chainid and address are unchanged from construction.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == _CACHED_CHAIN_ID
                ? _CACHED_DOMAIN_SEPARATOR
                : _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME);
    }

    /// @notice Builds a domain separator using the current chainId and contract address.
    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(typeHash, nameHash, block.chainid, address(this))
            );
    }

    /// @notice Creates an EIP-712 typed data hash
    function hashTypedData(bytes32 dataHash) external view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), dataHash)
            );
    }

}
