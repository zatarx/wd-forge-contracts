-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install transmissions11/solmate@v6 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --constructor-args 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy:
	@forge script script/GroupBillFactory.s.sol:DeployGroupBillFactory --rpc-url http://localhost:8545 --broadcast -vvvvv

tdeploy:
	@forge script script/GroupBillFactory.s.sol:TestDeployGroupBillFactory --rpc-url http://localhost:8545 --broadcast -vvvvv

checkgb:
	@forge script script/GroupBillFactory.s.sol:CheckGBScript --rpc-url http://localhost:8545 --broadcast -vvvvv

creategb:
	@forge script script/GroupBillFactory.s.sol:CreateGBContract --rpc-url http://localhost:8545 --broadcast -vvvvv

prune:
	@forge script script/GroupBillFactory.s.sol:ExpensePruningRequestContract --rpc-url http://localhost:8545 --broadcast -vvvvv

cast_call:
	@cast call 0xa91004C78f59Ef41472ac641F292F13cb1f9BDE5 "setAcceptedTokens(uint,address[])(GroupBill)" 0 "[0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266]" --trace --rpc-url http://localhost:8545

cast_another_call:
	cast call 0xa91004C78f59Ef41472ac641F292F13cb1f9BDE5 "createNewGroupBill(uint,address[])(GroupBill)" 0 "[0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266]" --trace --rpc-url http://localhost:8545
