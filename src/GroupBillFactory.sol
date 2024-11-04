// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPermit2} from "./Utils.sol";
import {GroupBill} from "./GroupBill.sol";
import {MsgSigner} from "./MsgSigner.sol";

error GroupBillFactory__TokenNotFound(uint tokenId);
error GroupBillFactory__AcceptedTokensNotEmpty();


contract GroupBillFactory is Ownable, MsgSigner {
    mapping(address => GroupBill[]) public s_ownerGroupBills;

    IPermit2 private i_permit2;
    uint private s_acceptedTokensLength;
    address private immutable i_consumerEOA;
    address private immutable i_gbAccount;
    mapping(uint => IERC20) private s_acceptedTokens;

    event GroupBillCreation(address indexed contractId);

    constructor(
        address initialOwner,
        address consumerEOA,
        address gbfAccount,
        address gbAccount,
        IPermit2 permit2
    )
        Ownable(initialOwner)
        MsgSigner(gbfAccount)
    {
        i_consumerEOA = consumerEOA;
        i_permit2 = permit2;
        i_gbAccount = gbAccount;
    }

    function createNewGroupBill(
        uint tokenId,
        address[] memory initialParticipants
    ) public onlyTrustedAccount returns (GroupBill groupBill) {
        console.log("GROUP BILL FACTORY: createNewGroupBill function");
        IERC20 token = s_acceptedTokens[tokenId];
        if (address(s_acceptedTokens[tokenId]) == address(0)) {
            revert GroupBillFactory__TokenNotFound(tokenId);
        }

        groupBill = new GroupBill(s_msgSigner, token, initialParticipants, i_consumerEOA, i_gbAccount, i_permit2);
        s_ownerGroupBills[s_msgSigner].push(groupBill);

        emit GroupBillCreation(address(groupBill));
    }

    function setAcceptedTokens(address[] memory acceptedTokens) public onlyOwner {
        // TODO: deploy to sepolia and test out storing erc20 tokens vs address []
        if (acceptedTokens.length == 0) {
            revert GroupBillFactory__AcceptedTokensNotEmpty();
        }

        for (uint256 tokenId = 0; tokenId < s_acceptedTokensLength; tokenId++) {
            delete s_acceptedTokens[tokenId];
        }

        for (uint256 tokenId = 0; tokenId < acceptedTokens.length; tokenId++) {
            s_acceptedTokens[tokenId] = IERC20(acceptedTokens[tokenId]);
        }
        s_acceptedTokensLength = acceptedTokens.length;
    }

    function getOwnerGroupBills(address owner) public view returns (GroupBill[] memory) {
        return s_ownerGroupBills[owner];
    }

    function getAcceptedTokens() public view returns (address[] memory) {
        address[] memory tokens = new address[](s_acceptedTokensLength);
        for (uint tokenId = 0; tokenId < s_acceptedTokensLength; tokenId++) {
            tokens[tokenId] = address(s_acceptedTokens[tokenId]);
        }
        return tokens;
    }
}
