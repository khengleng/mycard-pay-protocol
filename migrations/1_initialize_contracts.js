const glob = require("glob");
const difference = require("lodash/difference");
const { writeJSONSync, readJSONSync, existsSync } = require("node-fs-extra");
const { verifyProxy, verifyImpl } = require("../lib/verify");
const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");
const PrepaidCardManager = artifacts.require("PrepaidCardManager");
const RevenuePool = artifacts.require("RevenuePool");
const BridgeUtils = artifacts.require("BridgeUtils");
const SPEND = artifacts.require("SPEND");
const Feed = artifacts.require("ManualFeed");
const ChainlinkOracle = artifacts.require("ChainlinkFeedAdapter");
const DIAOracle = artifacts.require("DIAOracleAdapter");

// we only maintain these migrations purely to measure the amount of gas it
// takes to perform a deployment for each contract
module.exports = async function (deployer, network, addresses) {
  if (["ganache", "test", "soliditycoverage"].includes(network)) {
    await Promise.all([
      deployer.deploy(PrepaidCardManager),
      deployer.deploy(RevenuePool),
      deployer.deploy(BridgeUtils),
      deployer.deploy(SPEND),
      deployer.deploy(Feed),
      deployer.deploy(ChainlinkOracle),
      deployer.deploy(DIAOracle),
    ]);
  } else {
    // Contract init details
    let contracts = {
      PrepaidCardManager: {
        contractName: "PrepaidCardManager",
        init: [addresses[0]],
      },
      RevenuePool: { contractName: "RevenuePool", init: [addresses[0]] },
      BridgeUtils: { contractName: "BridgeUtils", init: [addresses[0]] },
      SPEND: {
        contractName: "SPEND",
        init: [addresses[0], "RevenuePool.address"],
      },
      DAIOracle: { contractName: "ChainlinkFeedAdapter", init: [addresses[0]] },
      CARDOracle: { contractName: "DIAOracleAdapter", init: [addresses[0]] },
    };

    // Use manual feeds in sokol
    if (network === "sokol") {
      contracts["DAIUSDFeed"] = {
        contractName: "ManualFeed",
        init: [addresses[0]],
      };
      contracts["ETHUSDFeed"] = {
        contractName: "ManualFeed",
        init: [addresses[0]],
      };
      contracts["MockDIA"] = {
        contractName: "MockDIAOracle",
        init: [addresses[0]],
      };
    }

    const addressesFile = `./.openzeppelin/addresses-${network}.json`;
    let skipVerify = process.argv.includes("--skipVerify");
    let proxyAddresses = {};
    let newImpls = [];
    let previousImpls = implAddresses(network);
    if (existsSync(addressesFile)) {
      proxyAddresses = readJSONSync(addressesFile);
    }

    for (let [contractId, { contractName, init }] of Object.entries(
      contracts
    )) {
      let factory = artifacts.require(contractName);
      let proxyAddress;
      if (proxyAddresses[contractId]) {
        console.log(`upgrading ${contractId}...`);
        ({ proxy: proxyAddress } = proxyAddresses[contractId]);
        await upgradeProxy(proxyAddress, factory, { deployer });
      } else {
        console.log(`deploying new contract ${contractId}...`);
        init = init.map((i) => {
          if (typeof i !== "string") {
            return i;
          }
          let iParts = i.split(".");
          if (iParts.length === 1) {
            return i;
          }
          let [id, prop] = iParts;
          switch (prop) {
            case "address": {
              let address = proxyAddresses[id].proxy;
              if (address == null) {
                throw new Error(
                  `The address for contract ${id} has not been derived yet. Cannot initialize ${contractId} with ${i}`
                );
              }
              return address;
            }
            default:
              throw new Error(
                `Do not know how to handle property "${prop}" from ${i} when processing the init args for ${contractId}`
              );
          }
        });
        let instance = await deployProxy(factory, init, { deployer });
        ({ address: proxyAddress } = instance);
        proxyAddresses[contractId] = {
          proxy: proxyAddress,
          contractName,
        };
      }
      if (!skipVerify) {
        await verifyProxy(proxyAddress, network);
      }
      let unverifiedImpls = difference(implAddresses(network), [
        ...previousImpls,
        ...newImpls,
      ]);
      for (let impl of unverifiedImpls) {
        if (!skipVerify) {
          await verifyImpl(impl, contractName, network, "MIT");
        }
        newImpls.push(impl);
      }
    }

    writeJSONSync(addressesFile, proxyAddresses);
    console.log("Deployed Contracts:");
    for (let [name, { proxy: address }] of Object.entries(proxyAddresses)) {
      console.log(`  ${name}: ${address}`);
    }
  }
};

function implAddresses(network) {
  let networkId;
  switch (network) {
    case "sokol":
      networkId = 77;
      break;
    case "xdai":
      networkId = 100;
      break;
    default:
      throw new Error(`Do not know network ID for network ${network}`);
  }
  let [file] = glob.sync(`./.openzeppelin/*-${networkId}.json`);
  if (!file) {
    return [];
  }
  let json = readJSONSync(file);
  return Object.values(json.impls).map((i) => i.address);
}