const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
const chaiBN = require("chai-bn");
const chaiExclude = require("chai-exclude");

const BN = require("bn.js");

// Enable and inject BN dependency
const { toBN, toChecksumAddress } = require("web3-utils");

// import web3 utils function
exports.toBN = toBN;
exports.toChecksumAddress = toChecksumAddress;

// setup chain for testing
// should use chain-bn before chain-as-promised
chai.use(chaiBN(BN));
chai.use(chaiExclude);
chai.use(chaiAsPromised);

chai.should();

exports.expect = chai.expect;
exports.assert = chai.assert;

// token detail
const TOKEN_DETAIL_DATA = ["DAI (CPXD)", "DAI.CPXD", 18];

exports.TOKEN_DETAIL_DATA = TOKEN_DETAIL_DATA;
