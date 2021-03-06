pragma solidity 0.5.17;

import "@openzeppelin/contract-upgradeable/contracts/token/ERC20/IERC20.sol";

contract IERC677 is IERC20 {
  function transferAndCall(
    address to,
    uint256 value,
    bytes memory data
  ) public returns (bool ok);

  function symbol() public view returns (string memory);

  function decimals() public view returns (uint8);

  event Transfer(
    address indexed from,
    address indexed to,
    uint256 value,
    bytes data
  );
}
