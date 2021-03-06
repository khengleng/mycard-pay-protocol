const { readJSONSync } = require("node-fs-extra");
const { existsSync } = require("fs");
const { resolve } = require("path");
const TrezorWalletProvider = require("trezor-cli-wallet-provider");
const TransparentUpgradeableProxy = require("@openzeppelin/upgrades-core/artifacts/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json");

const hre = require("hardhat");
const {
  upgrades: {
    deployProxy,
    upgradeProxy,
    erc1967: { getImplementationAddress },
  },
  ethers,
} = hre;

const networks = require("@ethersproject/networks/lib/index.js");

function patchNetworks() {
  let oldGetNetwork = networks.getNetwork;

  networks.getNetwork = function (network) {
    if (network === "sokol" || network === 77) {
      return { name: "sokol", chainId: 77 };
    } else {
      return oldGetNetwork(network);
    }
  };
}

function readAddressFile(network) {
  network = network === "hardhat" ? "localhost" : network;
  const addressesFile = resolve(
    __dirname,
    "..",
    "..",
    ".openzeppelin",
    `addresses-${network}.json`
  );
  if (!existsSync(addressesFile)) {
    throw new Error(`Cannot read from the addresses file ${addressesFile}`);
  }
  return readJSONSync(addressesFile);
}

function getHardhatTestWallet() {
  let provider = new ethers.getDefaultProvider("http://localhost:8545");
  // This is the default hardhat test mnemonic
  let wallet = new ethers.Wallet.fromMnemonic(
    "test test test test test test test test test test test junk"
  );
  return wallet.connect(provider);
}

async function makeFactory(contractName) {
  if (hre.network.name === "hardhat") {
    return await ethers.getContractFactory(contractName);
  } else if (hre.network.name === "localhost") {
    return (await ethers.getContractFactory(contractName)).connect(
      getHardhatTestWallet()
    );
  }
  return (await ethers.getContractFactory(contractName)).connect(getSigner());
}

function getSigner() {
  return getProvider().getSigner();
}

function getProvider() {
  const {
    network: {
      name: network,
      config: { chainId, url: rpcUrl, derivationPath },
    },
  } = hre;

  if (network === "localhost") {
    return new ethers.getDefaultProvider("http://localhost:8545");
  }

  const walletProvider = new TrezorWalletProvider(rpcUrl, {
    chainId: chainId,
    numberOfAccounts: 3,
    derivationPath,
  });

  return new ethers.providers.Web3Provider(walletProvider, network);
}

async function getDeployAddress() {
  if (hre.network.name === "hardhat") {
    let [signer] = await ethers.getSigners();
    return signer.address;
  } else if (hre.network.name === "localhost") {
    return getHardhatTestWallet().address;
  }
  const trezorSigner = getSigner();
  return await trezorSigner.getAddress();
}

function asyncMain(main) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

async function retry(cb, maxAttempts = 5) {
  let attempts = 0;
  do {
    try {
      attempts++;
      return await cb();
    } catch (e) {
      console.log(
        `received ${e.message}, trying again (${attempts} of ${maxAttempts} attempts)`
      );
    }
  } while (attempts < maxAttempts);

  throw new Error("Reached max retry attempts");
}

async function upgradeImplementation(contractName, proxyAddress) {
  await retry(async () => {
    let currentImplementationAddress = await getImplementationAddress(
      proxyAddress
    );
    let deployedCode = await getProvider().getCode(
      currentImplementationAddress
    );
    let artifact = artifacts.require(contractName);

    if (
      deployedCode &&
      deployedCode != "0x" &&
      deployedCode === artifact.deployedBytecode
    ) {
      console.log(
        `Deployed bytecode already matches for ${contractName}@${proxyAddress} - no need to deploy new version`
      );
    } else {
      console.log(
        `Bytecode changed for ${contractName}@${proxyAddress}... Upgrading`
      );

      let factory = await makeFactory(contractName);
      await upgradeProxy(proxyAddress, factory);
    }
  });
}

async function deployNewProxyAndImplementation(contractName, constructorArgs) {
  return await retry(async () => {
    try {
      console.log(`Creating factory`);
      let factory = await makeFactory(contractName);
      console.log(`Deploying proxy`);
      let instance = await deployProxy(factory, constructorArgs);
      console.log("Waiting for transaction");
      await instance.deployed();
      return instance;
    } catch (e) {
      console.log(e);
      throw new Error("It failed, retrying");
    }
  });
}

module.exports = {
  makeFactory,
  getSigner,
  getDeployAddress,
  patchNetworks,
  asyncMain,
  readAddressFile,
  retry,
  upgradeImplementation,
  deployNewProxyAndImplementation,
};
