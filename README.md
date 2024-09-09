## Settlement Contracts

#### Preface
This repo is composed of `GroupBillFactory` and `GroupBill` contracts. `GroupBillFactory` creates GroupBill contracts for a specific `msg.sender`. Here is a short workflow example:

1. User creates a `GroupBill` with the name `Japan Trip, Jun 2024` with 5 participants (5 corresponding addresses not including the creator). At this point, dai token address is exported through env vars and hardcoded into the contract.
2. Each user joins the contract and adds their corresponding expenses. After that, permit method is then called so that users who borrowed from someone else in the group could settle up + .5 dai static fee.
3. After everyone has approved their tokens as payback, collective settlement is triggered by one of the users.
4. Assuming everyone has sufficient balances, settlement is successfully executed.


#### Installation
Clone the repo:
```
git clone git@github.com:zatarx/forge-contracts.git && cd forge-contracts
```
Initialize submodules:
```
git submodule update --init --recursive
```
Run build to check the installation:
```
forge build
```
