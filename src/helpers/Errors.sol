// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

error GroupBill__NotParticipant(address sender);
error GroupBill__NotExpenseOwner(address sender);
error GroupBill__HasNotVoted(address sender);
error GroupBill__ParticipantsEmpty();
error GroupBill__NotAllowedToJoin(address sender);
error GroupBill__AddressIsNotTrusted(address sender);
error GroupBill__InvalidToken(address token);
error GroupBill__SettlementPermitNotValid(address owner, address token, address spender);
error GroupBill__SettlementPermitExpired(address owner, address spender, uint expiration);
error GroupBill__NotSufficientPermitAmount(address sender, uint256 amount, uint256 amountNeeded);
