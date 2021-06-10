# WalletSweeper

## Getting Started

```
make migrate
```

## Running tests
```
make test
```

Debug using Remix IDE: https://remix.ethereum.org/#optimize=false&evmVersion=null&version=soljson-v0.5.12+commit.7709ece9.js

### Linting and analyzing

```
npm install -g ethlint
solium -d contracts

docker run -v $(pwd):/tmp mythril/myth analyze /tmp/contracts/WalletSweeper.sol --solv 0.5.12
```

### Compilation

1. Create ABI
    ```
    docker run --rm -v $(pwd):/root ethereum/solc:0.5.12 --abi /root/contracts/WalletSweeper.sol -o /root/build
    ```
1. Compile
   ```
   docker run --rm -v $(pwd):/root ethereum/solc:0.5.12 --bin /root/contracts/WalletSweeper.sol -o /root/build
   ```
1. Combine into adapter file
   ```
   abigen --bin=./build/WalletSweeper.bin --abi=./build/WalletSweeper.abi --pkg=walletsweeper --out=/build/walletsweeper.go
   ```

### Learn more

- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [BitGo ETH MultiSig Wallet](https://github.com/BitGo/eth-multisig-v2)
- [ERC 777 vs ERC 20](https://medium.com/@vfoy9801376/is-erc-777-call-token-a-more-user-friendly-choice-than-erc20-7a11b38ff204)
- [Gemini Dollar Whitepaper](https://gemini.com/static/dollar/gemini-dollar-whitepaper.pdf)

