
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/GroupBillAccessControl.sol";

// todo: rename it to just deploying ERC4337 accounts
contract DeployAccessControlContract is Script {

    function run() external returns (address acAddr) {
        console.log("--------ERC4337 Group Bill Access Control Contract Deployment--------");

        acAddr = vm.envOr("GROUP_BILL_AC_ADDRESS", address(0));

        uint256 deployerPrivateKey = vm.envUint("ETH_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GroupBillAccessControl ac;
        if (acAddr == address(0)) {
            // TODO: the deployer must be the master user
            ac = new GroupBillAccessControl();
            acAddr = address(ac);
        }
        vm.stopBroadcast();
        vm.setEnv("GROUP_BILL_AC_ADDRESS", vm.toString(acAddr));

        console.logAddress(acAddr);

        console.log("--------ERC4337 Group bill Access Control Contract Deployment--------");
    }
}