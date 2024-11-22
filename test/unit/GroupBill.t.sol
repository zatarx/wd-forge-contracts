// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import "forge-std/Test.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {GroupBillFactory} from "../../src/GroupBillFactory.sol";
// import {GroupBill} from "../../src/GroupBill.sol";
// import {TestDeployGroupBillFactory} from "../../script/GroupBillFactory.s.sol";
// import {MockToken} from "../../test/mocks/ERC20TokenMock.sol";

// contract GroupBillTest is Test {
//     GroupBillFactory factory;

//     function setUp() public {
//         string
//             memory testMnemonic = "test test test test test test test test test test test junk";
//         uint256 ownerPrivateKey = vm.deriveKey(testMnemonic, 0);
//         address ownerAddress = vm.addr(ownerPrivateKey);
//         vm.rememberKey(ownerPrivateKey);
//         vm.setEnv("TEST_ETH_PRIVATE_KEY", vm.toString(ownerPrivateKey));
//         vm.setEnv("TEST_ETH_OWNER_ADDRESS", vm.toString(ownerAddress));
//         vm.setEnv("TEST_ETH_CONSUMER_EOA", vm.toString(ownerAddress));

//         TestDeployGroupBillFactory deployer = new TestDeployGroupBillFactory();
//         MockToken token = new MockToken("TEST_TOKEN", "TST");

//         vm.setEnv("TEST_ETH_ACCEPTED_TOKENS", vm.toString(address(token)));

//         (address factoryAddress, ) = deployer.run();
//         factory = GroupBillFactory(factoryAddress);
//     }

//     // function test_Permit() public {
//     //     address testOwnerAddress = vm.addr(vm.envUint("TEST_ETH_PRIVATE_KEY"));

//     //     address[] memory initialParticipants = new address[](1);
//     //     initialParticipants[0] = testOwnerAddress;
//     //     GroupBill bill = factory.createNewGroupBill(0, initialParticipants);
//     //     address token = factory.getAcceptedTokens()[0];

//     // }
// }
