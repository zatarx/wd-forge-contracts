// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import "forge-std/Test.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {GroupBillFactory} from "../../src/GroupBillFactory.sol";
// import {GroupBill} from "../../src/GroupBill.sol";
// import {TestDeployGroupBillFactory} from "../../script/GroupBillFactory.s.sol";
// import {MockToken} from "../../test/mocks/ERC20TokenMock.sol";

// contract GroupBillFactoryTest is Test {
//     function setUp() public {
//         string
//             memory testMnemonic = "test test test test test test test test test test test junk";
//         uint256 ownerPrivateKey = vm.deriveKey(testMnemonic, 0);
//         address ownerAddress = vm.addr(ownerPrivateKey);
//         vm.rememberKey(ownerPrivateKey);
//         // vm.Wallet memory testWallet = vm.createWallet(uint256(keccak256(bytes("1"))));
//         vm.setEnv("TEST_ETH_PRIVATE_KEY", vm.toString(ownerPrivateKey));
//         vm.setEnv("TEST_ETH_OWNER_ADDRESS", vm.toString(ownerAddress));
//         vm.setEnv("TEST_ETH_CONSUMER_EOA", vm.toString(ownerAddress));
//     }

//     function deployMockTokens(
//         uint tokensAmount
//     ) internal returns (ERC20[] memory, string memory) {
//         ERC20[] memory mockTokens = new ERC20[](tokensAmount);
//         string memory addressesEnvString = "";

//         for (uint i = 0; i < tokensAmount; i++) {
//             string memory tokenName = string.concat("TEST", vm.toString(i));
//             mockTokens[i] = new MockToken(tokenName, tokenName);

//             if (bytes(addressesEnvString).length == 0) {
//                 addressesEnvString = vm.toString(address(mockTokens[i]));
//             } else {
//                 addressesEnvString = string.concat(
//                     string.concat(addressesEnvString, ","),
//                     vm.toString(address(mockTokens[i]))
//                 );
//             }
//         }

//         return (mockTokens, addressesEnvString);
//     }

//     function deployGroupBillFactory(
//         uint tokensAmount
//     ) internal returns (GroupBillFactory, ERC20[] memory) {
//         TestDeployGroupBillFactory deployer = new TestDeployGroupBillFactory();
//         (
//             ERC20[] memory mockTokens,
//             string memory addressesEnvString
//         ) = deployMockTokens(tokensAmount);

//         vm.setEnv("TEST_ETH_ACCEPTED_TOKENS", addressesEnvString);

//         (address factoryAddress, ) = deployer.run();
//         GroupBillFactory factory = GroupBillFactory(factoryAddress);
//         return (factory, mockTokens);
//     }

//     function test_DeployGBFactoryWithTokens() public {
//         uint tokenAmount = 3;
//         (
//             GroupBillFactory factory,
//             ERC20[] memory mockTokens
//         ) = deployGroupBillFactory(tokenAmount);
//         address[] memory factoryTokens = factory.getAcceptedTokens();

//         console.log("Mock tokens length %d", mockTokens.length);
//         console.log("factory tokens length %d", factoryTokens.length);

//         assert(factoryTokens.length == tokenAmount);
//         for (uint i = 0; i < mockTokens.length; i++) {
//             assert(factoryTokens[i] == address(mockTokens[i]));
//         }
//     }

//     function testFail_IfNoTokensProvided() public {
//         vm.setEnv("TEST_ETH_ACCEPTED_TOKENS", " ");

//         TestDeployGroupBillFactory deployer = new TestDeployGroupBillFactory();
//         deployer.run();
//     }

//     function testFail_IfNotOwnerSetsAcceptedTokens() public {
//         uint tokenAmount = 4;
//         uint newTokenAmount = 2;

//         (GroupBillFactory factory, ) = deployGroupBillFactory(tokenAmount);
//         (ERC20[] memory newTokens, ) = deployMockTokens(newTokenAmount);
//         address[] memory tokenAddresses = new address[](newTokens.length);
//         for (uint i = 0; i < tokenAddresses.length; i++) {
//             tokenAddresses[i] = address(newTokens[i]);
//         }

//         vm.prank(vm.addr(1));
//         factory.setAcceptedTokens(tokenAddresses);
//     }

//     function test_CreateGroupBill() public {
//         uint tokenAmount = 4;
//         address testOwnerAddress = vm.addr(vm.envUint("TEST_ETH_PRIVATE_KEY"));

//         (GroupBillFactory factory, ) = deployGroupBillFactory(tokenAmount);
//         address[] memory initialParticipants = new address[](2); // array fuckery ahead!! address[2] memory != address[] memory
//         initialParticipants[0] = testOwnerAddress;
//         initialParticipants[1] = vm.addr(1);

//         vm.prank(testOwnerAddress);
//         GroupBill groupBill = factory.createNewGroupBill(
//             0,
//             initialParticipants
//         );
//         assert(groupBill.owner() == testOwnerAddress);
//         assert(groupBill.getConsumerEOA() == testOwnerAddress);

//         for (uint i = 0; i < initialParticipants.length; i++) {
//             vm.prank(initialParticipants[i]);
//             if (testOwnerAddress == initialParticipants[i]) {
//                 assert(
//                     groupBill.getParticipantState() ==
//                         GroupBill.JoinState.JOINED
//                 );
//             } else {
//                 assert(
//                     groupBill.getParticipantState() ==
//                         GroupBill.JoinState.PENDING
//                 );
//             }
//         }

//         GroupBill[] memory factoryTestOwnerBills = factory.getOwnerGroupBills(
//             testOwnerAddress
//         );
//         assert(factoryTestOwnerBills.length == 1);
//         assert(address(factoryTestOwnerBills[0]) == address(groupBill));
//     }

//     function testFail_CreateGroupBillIfTokenNotFound() public {
//         uint tokenAmount = 4;
//         address testOwnerAddress = vm.addr(vm.envUint("TEST_ETH_PRIVATE_KEY"));

//         (GroupBillFactory factory, ) = deployGroupBillFactory(tokenAmount);
//         address[] memory initialParticipants = new address[](1);
//         initialParticipants[0] = testOwnerAddress;

//         vm.prank(testOwnerAddress);
//         factory.createNewGroupBill(10, initialParticipants);
//     }

//     function testFail_CreateGroupBillIfParticipantsEmpty() public {
//         uint tokenAmount = 4;
//         address testOwnerAddress = vm.addr(vm.envUint("TEST_ETH_PRIVATE_KEY"));

//         (GroupBillFactory factory, ) = deployGroupBillFactory(tokenAmount);
//         address[] memory initialParticipants = new address[](0);

//         vm.prank(testOwnerAddress);
//         factory.createNewGroupBill(3, initialParticipants);
//     }
// }
