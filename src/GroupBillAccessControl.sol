// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

pragma solidity ^0.8.23;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// bytes32 constant PARTICIPANT_ROLE = keccak256("GROUP_BILL_PARTICIPANT");
// bytes32 constant GROUP_BILL_ROLE = keccak256("GROUP_BILL");

// Static Roles List
bytes32 constant PAYMASTER_COVERABLE_ROLE = keccak256("PAYMASTER_COVERABLE");
bytes32 constant PARTICIPANT_ROLE = keccak256("GROUP_BILL_PARTICIPANT");
bytes32 constant GROUP_BILL_CREATOR_ROLE = keccak256("GROUP_BILL_CREATOR");
bytes32 constant GROUP_BILL_ROLE = keccak256("GROUP_BILL");
bytes32 constant BLACKLIST_ROLE = keccak256("BLACKLIST");
bytes32 constant OWNER_ROLE = keccak256("OWNER");

contract GroupBillAccessControl is AccessControl {
    /// Static Roles
    // bytes32 public constant PAYMASTER_COVERABLE_ROLE = keccak256("PAYMASTER_COVERABLE");
    // bytes32 public constant PARTICIPANT_ROLE = keccak256("GROUP_BILL_PARTICIPANT");
    // bytes32 public constant GROUP_BILL_CREATOR_ROLE = keccak256("GROUP_BILL_CREATOR");
    // bytes32 public constant GROUP_BILL_ROLE = keccak256("GROUP_BILL");
    // bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST");
    // bytes32 public constant OWNER_ROLE = keccak256("OWNER");
    // add role to participant (keep counter of contracts)
    // if participant counter goes to 0, remove that role for that participant
    // gbf is the owner (can assign group bill role)
    // group bills can assign participant role and counter
    constructor() {
        // _grantRole(OWNER_ROLE, gbfAddress);
        // _grantRole(PAYABLE_ACCOUNT_ROLE, gbfAddress);
        _grantRole(OWNER_ROLE, msg.sender);

        _setRoleAdmin(GROUP_BILL_ROLE, OWNER_ROLE);
        _setRoleAdmin(BLACKLIST_ROLE, OWNER_ROLE);
        _setRoleAdmin(GROUP_BILL_CREATOR_ROLE, OWNER_ROLE);
        _setRoleAdmin(PARTICIPANT_ROLE, OWNER_ROLE);
        _setRoleAdmin(PAYMASTER_COVERABLE_ROLE, OWNER_ROLE);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
    }

    function grantOwnerRole(address account) public onlyRole(OWNER_ROLE) {
        _grantRole(OWNER_ROLE, account);
    }

    function grantGBParticipantRole(address account, address gbAddr) public onlyRole(GROUP_BILL_ROLE) {
        _grantRole(formGBParticipantRole(gbAddr), account);
    }

    function blacklistUser(address account) public onlyRole(OWNER_ROLE) {
        _grantRole(BLACKLIST_ROLE, account);
    }

    function grantGBCreatorRole(address account) public onlyRole(OWNER_ROLE) {
        _grantRole(GROUP_BILL_CREATOR_ROLE, account);
    }

    function grantPayableAccountRole(address account) public onlyRole(OWNER_ROLE) {
        _grantRole(PAYMASTER_COVERABLE_ROLE, account);
    }

    function formGBParticipantRole(address gbAddr) public pure returns (bytes32) {
        return keccak256(abi.encode("PARTICIPANT", gbAddr));
    }
}
