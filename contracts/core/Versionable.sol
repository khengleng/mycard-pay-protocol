pragma solidity 0.5.17;

contract Versionable {
  function cardpayVersion() external pure returns (string memory) {
    return "0.6.7";
  }

  uint256[50] private ____gap;
}
