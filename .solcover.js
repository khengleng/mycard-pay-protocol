module.exports = {
  skipFiles: [
    // This contract is only used to pull in npm solidity artifacts used for
    // testing
    "contracts/dev/DevDependencies.sol",
  ],
  providerOptions: {
    total_accounts: 1000,
  },
};
