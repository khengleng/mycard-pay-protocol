const PrepaidCardManager = artifacts.require("PrepaidCardManager");
const RevenuePool = artifacts.require("RevenuePool");
const L2Token = artifacts.require("ERC677Token");

const {
  GNOSIS_SAFE_MASTER_COPY,
  GNOSIS_SAFE_FACTORY,
  TALLY,
} = require("./constants");

const MINIMUM_AMOUNT = process.env.MINIMUM_AMOUNT ?? 100; //minimum face value (in SPEND) for new prepaid card
const MAXIMUM_AMOUNT = process.env.MAXIMUM_AMOUNT ?? 100000 * 100; //maximum face value (in SPEND) for new prepaid card

module.exports = async function (_, network) {
  if (["ganache", "test", "soliditycoverage"].includes(network)) {
    return;
  }

  let prepaidCardManager = await PrepaidCardManager.deployed();
  let pool = await RevenuePool.deployed();
  let l2Token = await L2Token.deployed();
  let acceptedL2Tokens = [l2Token.address];

  await prepaidCardManager.setup(
    TALLY,
    GNOSIS_SAFE_MASTER_COPY,
    GNOSIS_SAFE_FACTORY,
    pool.address,
    acceptedL2Tokens,
    MINIMUM_AMOUNT,
    MAXIMUM_AMOUNT
  );
  console.log(`configured prepaid card manager:
  Tally contract address:              ${TALLY}
  Gnosis safe master copy:             ${GNOSIS_SAFE_MASTER_COPY}
  Gnosis safe factory:                 ${GNOSIS_SAFE_FACTORY}
  Revenue pool address:                ${pool.address}
  Prepaid card Accepted L2 tokens:     ${acceptedL2Tokens.join(", ")}
  Minimum new prepaid card face value: ${MINIMUM_AMOUNT} SPEND
  Maximum new prepaid card face value: ${MAXIMUM_AMOUNT} SPEND
`);
};
