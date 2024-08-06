// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GroupBill} from "./GroupBill.sol";

error GroupBill__ParticipantsNotEmpty();
error GroupBill__TokenNotAllowed(IERC20 token);

contract GroupBillFactory is Ownable {
    error GroupBillFactory__AcceptedTokensNotEmpty();

    uint public i_acceptedTokensCount;
    address private immutable i_consumerEOA;
    mapping(uint => IERC20) private ACCEPTED_TOKENS;
    mapping(address => GroupBill[]) public s_ownerGroupBills;

    event GroupBillCreation(address contractId);

    constructor(
        address initialOwner,
        address consumerEOA
    ) Ownable(initialOwner) {
        i_consumerEOA = consumerEOA;
    }

    function createNewGroupBill(
        uint tokenId,
        address[] memory initialParticipants
    ) public returns (GroupBill groupBill) {
        IERC20 token = ACCEPTED_TOKENS[tokenId];
        if (address(ACCEPTED_TOKENS[tokenId]) == address(0)) {
            revert GroupBill__TokenNotAllowed(token);
        }
        groupBill = new GroupBill(
            msg.sender,
            token,
            initialParticipants,
            i_consumerEOA
        );
        s_ownerGroupBills[msg.sender].push(groupBill);
        emit GroupBillCreation(address(groupBill));
    }

    function setAcceptedTokens(address[] memory acceptedTokens) public onlyOwner {
        // TODO: deploy to sepolia and test out storing erc20 tokens vs address []
        if (acceptedTokens.length == 0) {
            revert GroupBillFactory__AcceptedTokensNotEmpty();
        }
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            ACCEPTED_TOKENS[i] = IERC20(acceptedTokens[i]);
        }
        i_acceptedTokensCount = acceptedTokens.length; 
    }

    function getOwnerGroupBills(
        address owner
    ) public view returns (GroupBill[] memory) {
        return s_ownerGroupBills[owner];
    }

    function getAcceptedTokens() public view returns (address[] memory) {
        address[] memory tokens = new address[](i_acceptedTokensCount);
        for (uint i = 0; i < i_acceptedTokensCount; i++) {
            tokens[i] = address(ACCEPTED_TOKENS[i]);
        }
        return tokens;
    }
}
