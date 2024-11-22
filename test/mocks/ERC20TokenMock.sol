// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory tokenName, string memory tokenShortName) ERC20(tokenName, tokenShortName) {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals())));
    }
}
