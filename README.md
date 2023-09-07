# <h1 align="center"> All-In-One IGO </h1>

Dependency Contract used by IGO for registering users buy info and facilitates refund

## Install

```bash
yarn install && forge install
```

Each time a new dependency is added in `lib/` run `forge install`.

## Tests

-   Run without fuzz testing, use `forge test -vvv --via-ir`

### Generate Coverage Report

If `lcov` is not installed, run `brew install lcov`.
Then run: `yarn coverage`

### Run GitHub Actions Locally

1. Install [act](https://github.com/nektos/act)
2. Load env var `source .env`
3. Run a job: `act -j <job_name> -s SEED` (hit ENTER when asked `Provide value for 'SEED':`)

## Run Advanced Tests

### Slither

`slither .`

Note: Slither has been added to GitHub actions, so it will run automatically on every **push and pull requests**.

### Mythril

`myth a src/IGOVesting.sol --solc-json mythril.config.json` (you can use both `myth a` and `mythril analyze`)

### Manticore

1. Run Docker container:

```
docker run --rm -it --platform linux/amd64 \
-v $(pwd):/home/igo \
baolean/manticore:latest
```

2. Go to mounted volume location: `cd /home/igo`

3. Select Solidity version

```
solc-select install 0.8.17 && solc-select use 0.8.17
```

4. Run manticore:

```
manticore src/IGOVesting.sol --contract IGOVesting --solc-remaps="openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/ @openzeppelin-contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/"
```

### SuMo

After install yarn dependencies, run `yarn sumo test` to run mutation testing.

_Note: there issues as we can specificy `--ffi` parameter when compiling with forge_

## Best Practices to Follow

### Generics

-   Code formatter & linter: prettier, solhint, husky, lint-staged & husky
-   [Foundry](https://book.getfoundry.sh/tutorials/best-practices)

### Security

-   [Solidity Patterns](https://github.com/fravoll/solidity-patterns)
-   [Solcurity Codes](https://github.com/transmissions11/solcurity)
-   Secureum posts _([101](https://secureum.substack.com/p/security-pitfalls-and-best-practices-101) & [101](https://secureum.substack.com/p/security-pitfalls-and-best-practices-201): Security Pitfalls & Best Practice)_
-   [Smart Contract Security Verification Standard](https://github.com/securing/SCSVS)
-   [SWC](https://swcregistry.io)
