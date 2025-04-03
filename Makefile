
-include .env

.PHONY: all test clean deploy simulate

DEFAULT_ANVIL_ADDRESS := 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
	
all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install:; npm install && forge install --no-commit

install-deno:; curl -fsSL https://deno.land/install.sh | sh 

# update dependencies
update:; forge update

# compile
build:; forge build

# test
test :; forge test 

# test coverage
coverage:; @forge coverage --contracts src --ir-minimum
coverage-report:; @forge coverage --contracts src --report debug > coverage.txt --ir-minimum

# take snapshot
snapshot :; forge snapshot

# format
format :; forge fmt

# spin up local test network
anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# spin up fork
fork :; @anvil --fork-url ${RPC_MAIN} --fork-block-number <blocknumber> --fork-chain-id <fork id> --chain-id <custom id>

# security
slither :; slither ./src 

# deployment
deploy-local: 
	@forge script script/DeployRarityRewards.s.sol:DeployRarityRewards --rpc-url $(RPC_LOCALHOST) --private-key ${DEFAULT_ANVIL_KEY} --sender ${DEFAULT_ANVIL_ADDRESS} --broadcast -vv

deploy-token-testnet: 
	@forge script script/DeployMockERC20.s.sol:DeployMockERC20 --rpc-url $(RPC_TEST) --account ${ACCOUNT_NAME} --sender ${ACCOUNT_ADDRESS} --broadcast --verify --etherscan-api-key ${ETHERSCAN_KEY} -vvvv

deploy-tenderly: 
	@forge script script/DeployRarityRewards.s.sol:DeployRarityRewards --rpc-url $(RPC_TENDERLY) --account ${ACCOUNT_NAME} --sender ${ACCOUNT_ADDRESS} --broadcast --verify --etherscan-api-key ${TENDERLY_KEY} --verifier-url ${RPC_TENDERLY}/verify/etherscan -vvvv

deploy-testnet: 
	@forge script script/DeployRarityRewards.s.sol:DeployRarityRewards --rpc-url $(RPC_TEST) --account ${ACCOUNT_NAME} --sender ${ACCOUNT_ADDRESS} --broadcast --verify --etherscan-api-key ${ETHERSCAN_KEY} -vvvv

deploy-mainnet: 
	@forge script script/DeployRarityRewards.s.sol:DeployRarityRewards --rpc-url $(RPC_MAIN) --account ${ACCOUNT_NAME} --sender ${ACCOUNT_ADDRESS} --broadcast --verify --etherscan-api-key ${ETHERSCAN_KEY} -vvvv

# interactions
mint-mock:
	@forge script script/Interactions.s.sol:MintMockNft --rpc-url $(RPC_LOCALHOST) --private-key ${DEFAULT_ANVIL_KEY} --sender ${DEFAULT_ANVIL_ADDRESS} --broadcast -vv

claim:
	@forge script script/Interactions.s.sol:Claim --rpc-url $(RPC_LOCALHOST) --private-key ${DEFAULT_ANVIL_KEY} --sender ${DEFAULT_ANVIL_ADDRESS} --broadcast -vv

deposit:
	@forge script script/Interactions.s.sol:Deposit --rpc-url $(RPC_LOCALHOST) --private-key ${DEFAULT_ANVIL_KEY} --sender ${DEFAULT_ANVIL_ADDRESS} --broadcast -vv

# command line interaction
contract-call:
	@cast call <contract address> "FunctionSignature(params)(returns)" arguments --rpc-url ${<RPC>}

link-balance:
	@cast call 0x5587f8cf1D624ee675fE501f5630aA229e4E1BE9 "balanceOf(address)(uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url ${RPC_LOCALHOST}

get-claims:
	@cast call 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 "getClaims(uint256,address)(uint256,address,uint256,uint256)" 0 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url ${RPC_LOCALHOST}

get-period:
	@cast call 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 "getClaimPeriod(uint256)(uint256,address,uint256,uint256,uint256,uint256,uint256)" 0 --rpc-url ${RPC_LOCALHOST}

# chainlink function simulation
start-local-network :; npx ts-node functions-toolkit/local-network/start.ts
simulate-response :; npx ts-node functions-toolkit/local-network/simulate.ts $(ARGS)

# helpers
chainid:
	@forge script script/Helpers.s.sol:CheckActiveNetworkId --rpc-url $(RPC_LOCALHOST) -vv

cf-network-config:
	@forge script script/Helpers.s.sol:ReadCfNetworkConfig --rpc-url $(RPC_LOCALHOST) -vv

-include ${FCT_PLUGIN_PATH}/makefile-external