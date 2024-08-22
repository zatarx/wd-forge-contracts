// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

interface IPermit2 is ISignatureTransfer, IAllowanceTransfer {}
