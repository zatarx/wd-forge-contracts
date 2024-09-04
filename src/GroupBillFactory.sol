// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPermit2} from "./Utils.sol";
import {GroupBill} from "./GroupBill.sol";

error GroupBillFactory__TokenNotFound(uint tokenId);
error GroupBillFactory__AcceptedTokensNotEmpty();

contract GroupBillFactory is Ownable {
    mapping(address => GroupBill[]) public s_ownerGroupBills;

    IPermit2 private i_permit2;
    uint private s_acceptedTokensLength;
    address private immutable i_consumerEOA;
    mapping(uint => IERC20) private s_acceptedTokens;

    event GroupBillCreation(address indexed contractId);

    constructor(
        address initialOwner,
        address consumerEOA,
        IPermit2 permit2
    ) Ownable(initialOwner) {
        i_consumerEOA = consumerEOA;
        i_permit2 = permit2;
    }

    function createNewGroupBill(
        uint tokenId,
        address[] memory initialParticipants
    ) public returns (GroupBill groupBill) {
        IERC20 token = s_acceptedTokens[tokenId];
        if (address(s_acceptedTokens[tokenId]) == address(0)) {
            revert GroupBillFactory__TokenNotFound(tokenId);
        }
        groupBill = new GroupBill(
            msg.sender,
            token,
            initialParticipants,
            i_consumerEOA,
            i_permit2
        );
        s_ownerGroupBills[msg.sender].push(groupBill);
        emit GroupBillCreation(address(groupBill));
    }

    function setAcceptedTokens(
        address[] memory acceptedTokens
    ) public onlyOwner {
        // TODO: deploy to sepolia and test out storing erc20 tokens vs address []
        if (acceptedTokens.length == 0) {
            revert GroupBillFactory__AcceptedTokensNotEmpty();
        }

        for (uint256 i = 0; i < s_acceptedTokensLength; i++) {
            delete s_acceptedTokens[i];
        }

        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            s_acceptedTokens[i] = IERC20(acceptedTokens[i]);
        }
        s_acceptedTokensLength = acceptedTokens.length;
    }

    function getOwnerGroupBills(
        address owner
    ) public view returns (GroupBill[] memory) {
        return s_ownerGroupBills[owner];
    }

    function getAcceptedTokens() public view returns (address[] memory) {
        address[] memory tokens = new address[](s_acceptedTokensLength);
        for (uint i = 0; i < s_acceptedTokensLength; i++) {
            tokens[i] = address(s_acceptedTokens[i]);
        }
        return tokens;
    }
}
