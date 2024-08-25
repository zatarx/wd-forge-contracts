// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {IPermit2} from "../src/Utils.sol";


contract SigUtils {
    IPermit2 private immutable i_permit2;

    constructor(IPermit2 permit2) {
        i_permit2 = permit2;
    }

    function hashTypedData(bytes32 dataHash) external view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    i_permit2.DOMAIN_SEPARATOR(),
                    dataHash
                )
            );
    }
}
