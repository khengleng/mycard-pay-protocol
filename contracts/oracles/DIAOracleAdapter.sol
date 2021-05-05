pragma solidity 0.5.17;

import "@openzeppelin/contract-upgradeable/contracts/ownership/Ownable.sol";
import "@openzeppelin/contract-upgradeable/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.5/interfaces/AggregatorV3Interface.sol";
import "./IPriceOracle.sol";
import "./IDIAOracle.sol";

contract DIAOracleAdapter is Ownable, IPriceOracle {
  using SafeMath for uint256;

  uint8 internal constant DECIMALS = 8;
  address internal oracle;
  string internal tokenSymbol;

  event DAIOracleSetup(address tokenUsdOracle, string tokenSymbol);

  function setup(address _oracle, string memory _tokenSymbol) public onlyOwner {
    require(_oracle != address(0), "oracle can't be zero address");
    oracle = _oracle;
    tokenSymbol = _tokenSymbol;

    emit DAIOracleSetup(oracle, _tokenSymbol);
  }

  function decimals() public view returns (uint8) {
    return DECIMALS;
  }

  function description() external view returns (string memory) {
    return tokenSymbol;
  }

  function usdPrice() external view returns (uint256 price, uint256 updatedAt) {
    return priceForPair(string(abi.encodePacked(tokenSymbol, "/USD")));
  }

  function ethPrice() external view returns (uint256 price, uint256 updatedAt) {
    return priceForPair(string(abi.encodePacked(tokenSymbol, "/ETH")));
  }

  function priceForPair(string memory pair)
    internal
    view
    returns (uint256 price, uint256 updatedAt)
  {
    require(oracle != address(0), "DIA oracle is not specified");
    (uint128 _price, uint128 _updatedAt) = IDIAOracle(oracle).getValue(pair);
    price = uint256(_price);
    updatedAt = uint256(_updatedAt);
  }
}