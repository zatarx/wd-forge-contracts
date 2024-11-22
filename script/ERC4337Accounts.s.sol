// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {GroupBill} from "../src/GroupBill.sol";
import {DeployAccessControlContract} from "./AC.sol";

import {PackedUserOperation} from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {GroupBillAccount} from "../src/accounts/Account.sol";

import {GroupBillFactoryAccount, GroupBillAccount} from "../src/accounts/Account.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";


// todo: rename it to just deploying ERC4337 accounts
contract DeployEntryPointAndAccounts is Script {
    address[] public participants;

    function run() external returns (address gbfAccount, address gbAccount) {
        console.log("--------ERC4337 EntryPoint & Accounts Deployment--------");
        address acAddr = (new DeployAccessControlContract()).run();

        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");

        address entryPoint = vm.envOr("ENTRY_POINT_ADDRESS", address(0));

        gbfAccount = vm.envOr("GBF_ACCOUNT_ADDRESS", address(0));
        gbAccount = vm.envOr("GB_ACCOUNT_ADDRESS", address(0));

        console.log("Current EP & Accounts Config");
        console.log("EP: %o; gbfAccount: %o; gbAccount: %o", entryPoint, gbfAccount, gbAccount);

        console.log("Deploying...");
        vm.startBroadcast(deployerPrivateKey);

        if (entryPoint == address(0)) {
            entryPoint = address(new EntryPoint());
            console.log("Entry Point deployed");
            console.logAddress(entryPoint);
        }
        if (gbfAccount == address(0)) {
            gbfAccount = address(new GroupBillFactoryAccount(entryPoint, acAddr));
            console.log("GBFactory Account deployed");
            console.logAddress(gbfAccount);
        }
        if (gbAccount == address(0)) {
            gbAccount = address(new GroupBillAccount(entryPoint, acAddr));
            console.log("GB Account deployed");
            console.logAddress(gbAccount);
        }
        vm.stopBroadcast();

        console.log("--------ERC4337 EP & Accounts Deployment Completed Successfully--------");
    }
}
