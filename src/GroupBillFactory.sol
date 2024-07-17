// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GroupBill} from "./GroupBill.sol";

error GroupBill__ParticipantsNotEmpty();
error GroupBill__TokenNotAllowed(address token);

contract GroupBillFactory {
    error GroupBillFactory__AcceptedTokensNotEmpty();

    mapping(IERC20 => bool) private i_acceptedTokens;
    mapping(address => GroupBill[]) public s_ownerGroupBills;

    constructor(IERC20[] memory acceptedTokens) {
        // TODO: IERC20[] vs address[] memory acceptedTokens passed
        if (!acceptedTokens.length) {
            revert GroupBillFactory__AcceptedTokensNotEmpty();
        }
        // i_acceptedTokens = acceptedTokens;

        // i_acceptedTokens = new IERC20[](0);
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            i_acceptedTokens[acceptedTokens[i]] = true;
        }
    }

    function createNewGroupBill(address desiredToken, address[] memory initialParticipants)
        public
        returns (GroupBill groupBill)
    {
        if (!i_acceptedTokens[IERC20(desiredToken)]) {
            revert GroupBill__TokenNotAllowed(desiredToken);
        }
        groupBill = new GroupBill(msg.sender, desiredToken, initialParticipants);
        s_ownerGroupBills[msg.sender].push(groupBill);
    }

    function getOwnerGroupBills(address owner) public returns (GroupBill[] memory) {
        return s_ownerGroupBills[owner];
    }

    function getAcceptedTokens() public returns (IERC20[] memory) {
        return i_acceptedTokens;
    }
}
