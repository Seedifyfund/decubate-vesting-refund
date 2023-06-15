import fs from 'fs';
import '@nomiclabs/hardhat-waffle';
import '@typechain/hardhat';
import { HardhatUserConfig, task } from 'hardhat/config';
import '@nomiclabs/hardhat-etherscan';
import '@nomicfoundation/hardhat-foundry';

// use .env vars
import * as dotenv from 'dotenv';
dotenv.config();

const config: HardhatUserConfig = {
    networks: {
        mumbai: {
            url: process.env.MUMBAI_RPC,
            accounts: {
                mnemonic: process.env.SEED,
            },
        },
    },
    etherscan: {
        apiKey: {
            bsc: process.env.BSC_KEY ?? '',
            polygonMumbai: process.env.POLYGON_KEY ?? '',
        },
    },
    solidity: {
        version: '0.8.17',
        settings: {
            optimizer: {
                enabled: true,
                runs: 20000,
            },
        },
    },
    paths: {
        artifacts: './artifacts',
        sources: 'src',
        tests: './test',
    },
};

export default config;
