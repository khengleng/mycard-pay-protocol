pragma solidity 0.5.17;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "@openzeppelin/contract-upgradeable/contracts/math/SafeMath.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

import "./token/IERC677.sol";
import "./roles/PayableToken.sol";
import "./core/Safe.sol";
import "./core/Versionable.sol";
import "./RevenuePool.sol";

contract PrepaidCardManager is Initializable, Versionable, PayableToken, Safe {
  using SafeMath for uint256;
  struct CardDetail {
    address issuer;
    address issueToken;
    uint256 blockNumber;
    string customizationDID;
    bool reloadable;
    bool canPayNonMerchants;
  }
  event Setup();
  event CreatePrepaidCard(
    address issuer,
    address card,
    address token,
    uint256 amount,
    string customizationDID
  );
  event GasFeeCollected(
    address issuer,
    address card,
    address issuingToken,
    uint256 amount
  );
  event TransferredPrepaidCard(
    address prepaidCard,
    address previousOwner,
    address newOwner
  );

  bytes4 public constant SWAP_OWNER = 0xe318b52b; //swapOwner(address,address,address)
  bytes4 public constant TRANSFER_AND_CALL = 0x4000aea0; //transferAndCall(address,uint256,bytes)
  uint8 public constant MAXIMUM_NUMBER_OF_CARD = 15;
  uint256 public constant MINIMUM_MERCHANT_PAYMENT = 50; //in units of SPEND
  address payable public revenuePool;
  address payable public gasFeeReceiver;
  mapping(address => CardDetail) public cardDetails;
  uint256 public gasFeeInCARD;
  uint256 public maximumFaceValue;
  uint256 public minimumFaceValue;
  address public gasToken;

  /**
   * @dev Setup function sets initial storage of contract.
   * @param _gsMasterCopy Gnosis safe Master Copy address
   * @param _gsProxyFactory Gnosis safe Proxy Factory address
   * @param _revenuePool Revenue Pool address
   * @param _gasFeeReceiver The addres that will receive the new prepaid card gas fee
   * @param _gasFeeInCARD the amount to charge for the gas fee for new prepaid card in units of CARD wei
   * @param _payableTokens Payable tokens are allowed to use (these are created by the token bridge, specify them here if there are existing tokens breaked by teh bridge to use)
   * @param _minAmount The minimum face value of a new prepaid card in units of SPEND
   * @param _maxAmount The maximum face value of a new prepaid card in units of SPEND
   */
  function setup(
    address _gsMasterCopy,
    address _gsProxyFactory,
    address payable _revenuePool,
    address payable _gasFeeReceiver,
    uint256 _gasFeeInCARD,
    address[] calldata _payableTokens,
    address _gasToken,
    uint256 _minAmount,
    uint256 _maxAmount
  ) external onlyOwner {
    revenuePool = _revenuePool;
    gasFeeReceiver = _gasFeeReceiver;
    gasFeeInCARD = _gasFeeInCARD;

    Safe.setup(_gsMasterCopy, _gsProxyFactory);
    // set token list payable.
    for (uint256 i = 0; i < _payableTokens.length; i++) {
      _addPayableToken(_payableTokens[i]);
    }
    gasToken = _gasToken;
    // set limit of amount.
    minimumFaceValue = _minAmount;
    maximumFaceValue = _maxAmount;
    emit Setup();
  }

  /**
   * @dev onTokenTransfer(ERC677) - call when token send this contract.
   * @param from Supplier or Prepaid card address
   * @param amount number token them transfer.
   * @param data data encoded
   */
  function onTokenTransfer(
    address from, // solhint-disable-line no-unused-vars
    uint256 amount,
    bytes calldata data
  ) external isValidToken returns (bool) {
    (
      address owner,
      uint256[] memory cardAmounts,
      string memory customizationDID
    ) = abi.decode(data, (address, uint256[], string));
    require(
      owner != address(0) && cardAmounts.length > 0,
      "Prepaid card data invalid"
    );
    createMultiplePrepaidCards(
      owner,
      from,
      _msgSender(),
      amount,
      cardAmounts,
      customizationDID
    );
    return true;
  }

  /**
   * @dev get the price in the specified token (in units of wei) to acheive the
   * specified face value in units of SPEND. Note that the face value will drift
   * afterwards based on the exchange rate
   */
  function priceForFaceValue(address token, uint256 spendFaceValue)
    external
    view
    returns (uint256)
  {
    return
      (RevenuePool(revenuePool).convertFromSpend(token, spendFaceValue))
        .add(gasFee(token))
        .add(100); // this is to deal with any rounding errors
  }

  /**
   * @dev sell card for customer
   * @param prepaidCard Prepaid Card's address
   * @param newOwner the new owner of the prepaid card (the customer)
   * @param previousOwnerSignature Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
   */
  function sellCard(
    address payable prepaidCard,
    address newOwner,
    bytes calldata previousOwnerSignature
  ) external payable returns (bool) {
    address previousOwner = getPrepaidCardOwner(prepaidCard);
    require(
      cardDetails[prepaidCard].issuer == previousOwner,
      "Has already been transferred"
    );
    execTransaction(
      prepaidCard,
      prepaidCard,
      getSellCardData(prepaidCard, newOwner),
      addContractSignature(prepaidCard, previousOwnerSignature),
      address(0),
      address(0)
    );
    emit TransferredPrepaidCard(prepaidCard, previousOwner, newOwner);

    return true;
  }

  /**
   * @dev Returns the bytes that are hashed to be signed by owner
   * @param prepaidCard the prepaid card address
   * @param newOwner Customer's address
   */
  function getSellCardData(address payable prepaidCard, address newOwner)
    public
    view
    returns (bytes memory)
  {
    // Swap owner
    address previousOwner = getPrepaidCardOwner(prepaidCard);
    return
      abi.encodeWithSelector(
        SWAP_OWNER,
        address(this),
        previousOwner,
        newOwner
      );
  }

  /**
   * @dev Pay token to merchant
   * @param prepaidCard Prepaid Card's address
   * @param payableTokenAddr payable token address
   * @param merchantSafe Merchant's safe address
   * @param amount value to pay to merchant
   * @param infoDID the merchant's info DID for merchant registration
   * @param ownerSignature Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
   */
  function payForMerchant(
    address payable prepaidCard,
    address payableTokenAddr,
    address merchantSafe,
    uint256 amount,
    string calldata infoDID,
    bytes calldata ownerSignature
  ) external returns (bool) {
    require(gasToken != address(0), "gasToken not configured");
    require(
      cardDetails[prepaidCard].blockNumber < block.number,
      "Prepaid card used too soon"
    );
    uint256 amountInSPEND =
      RevenuePool(revenuePool).convertToSpend(payableTokenAddr, amount);
    require(
      amountInSPEND >= MINIMUM_MERCHANT_PAYMENT,
      "merchant payment too small"
    ); // protect against spamming contract with too low a price
    return
      execTransaction(
        prepaidCard,
        payableTokenAddr,
        getPayData(payableTokenAddr, merchantSafe, amount, infoDID),
        addContractSignature(prepaidCard, ownerSignature),
        gasToken,
        prepaidCard
      );
  }

  /**
   * @dev Returns the bytes that are hashed to be signed by owner.
   * @param token Token merchant
   * @param merchantSafe Merchant's safe address
   * @param amount amount need pay to merchant
   * @param infoDID the merchant's info DID for merchange registration
   */
  function getPayData(
    address token, // solhint-disable-line no-unused-vars
    address merchantSafe,
    uint256 amount,
    string memory infoDID
  ) public view returns (bytes memory) {
    return
      abi.encodeWithSelector(
        TRANSFER_AND_CALL,
        revenuePool,
        amount,
        abi.encode(merchantSafe, infoDID)
      );
  }

  /**
   * @dev Split Current Prepaid Card into Multiple Cards
   * @param prepaidCard Prepaid Card's address
   * @param cardAmounts Array of new card's amount
   * @param customizationDID the customization DID for the new prepaid cards
   * @param ownerSignature Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
   */
  function splitCard(
    address payable prepaidCard,
    uint256[] calldata cardAmounts,
    string calldata customizationDID,
    bytes calldata ownerSignature
  ) external payable returns (bool) {
    address owner = getPrepaidCardOwner(prepaidCard);
    require(
      cardDetails[prepaidCard].issuer == owner,
      "only issuer can split card"
    );
    address issuingToken = cardDetails[prepaidCard].issueToken;
    return
      execTransaction(
        prepaidCard,
        issuingToken,
        getSplitCardData(prepaidCard, cardAmounts, customizationDID),
        addContractSignature(prepaidCard, ownerSignature),
        address(0),
        address(0)
      );
  }

  /**
   * @dev Returns the bytes that are hashed to be signed by owner.
   * @param prepaidCard the prepaid card address
   * @param amounts Array of new prepaid card amounts to create
   * @param customizationDID the customization DID for the new prepaid cards
   */
  function getSplitCardData(
    address payable prepaidCard,
    uint256[] memory amounts,
    string memory customizationDID
  ) public view returns (bytes memory) {
    address owner = getPrepaidCardOwner(prepaidCard);
    uint256 total = 0;

    for (uint256 i = 0; i < amounts.length; i++) {
      total = total.add(amounts[i]);
    }

    // Transfer token to this contract and call _createMultiplePrepaidCards
    return
      abi.encodeWithSelector(
        TRANSFER_AND_CALL,
        address(this),
        total,
        abi.encode(owner, amounts, customizationDID)
      );
  }

  /**
   * @dev check amount of card want to create.
   * convert amount to spend and check.
   */
  function isValidAmount(address token, uint256 amount)
    public
    view
    returns (bool)
  {
    uint256 amountInSPEND =
      RevenuePool(revenuePool).convertToSpend(token, amount - gasFee(token));
    return (minimumFaceValue <= amountInSPEND &&
      amountInSPEND <= maximumFaceValue);
  }

  function gasFee(address token) public view returns (uint256) {
    if (gasFeeReceiver == address(0)) {
      return 0;
    } else {
      return RevenuePool(revenuePool).convertFromCARD(token, gasFeeInCARD);
    }
  }

  /**
   * @dev Split Prepaid card
   * @param owner Supplier address
   * @param depot The Supplier's depot safe
   * @param token Token address
   * @param amountReceived Amount to split
   * @param amountOfCard array which performing face value of card
   */
  function createMultiplePrepaidCards(
    address owner,
    address depot,
    address token,
    uint256 amountReceived,
    uint256[] memory amountOfCard,
    string memory customizationDID
  ) private returns (bool) {
    uint256 neededAmount = 0;
    uint256 numberCard = amountOfCard.length;
    require(
      numberCard <= MAXIMUM_NUMBER_OF_CARD,
      "Too many prepaid cards requested"
    );

    for (uint256 i = 0; i < numberCard; i++) {
      require(isValidAmount(token, amountOfCard[i]), "Amount below threshold");
      neededAmount = neededAmount.add(amountOfCard[i]);
    }

    require(
      amountReceived >= neededAmount,
      "Insufficient funds sent for requested amounts"
    );
    for (uint256 i = 0; i < numberCard; i++) {
      createPrepaidCard(owner, token, amountOfCard[i], customizationDID);
    }

    // refund the supplier any excess funds that they provided
    if (
      amountReceived > neededAmount &&
      // check to make sure ownerSafe address is a depot, so we can ensure it's
      // a trusted contract
      BridgeUtils(bridgeUtils).safes(depot) != address(0)
    ) {
      // the owner safe is a trusted contract (gnosis safe)
      IERC677(token).transfer(depot, amountReceived - neededAmount);
    }

    return true;
  }

  /**
   * @dev Create Prepaid card
   * @param owner owner address
   * @param token token address
   * @param amount amount of prepaid card
   * @return PrepaidCard address
   */
  function createPrepaidCard(
    address owner,
    address token,
    uint256 amount,
    string memory customizationDID
  ) private returns (address) {
    address[] memory owners = new address[](2);

    owners[0] = address(this);
    owners[1] = owner;

    address card = createSafe(owners, 2);

    // card was created
    cardDetails[card].issuer = owner;
    cardDetails[card].issueToken = token;
    cardDetails[card].customizationDID = customizationDID;
    cardDetails[card].blockNumber = block.number;
    cardDetails[card].reloadable = false; // future functionality
    cardDetails[card].canPayNonMerchants = false; // future functionality
    uint256 _gasFee = gasFee(token);
    if (gasFeeReceiver != address(0) && _gasFee > 0) {
      // The gasFeeReceiver is a trusted address that we control
      IERC677(token).transfer(gasFeeReceiver, _gasFee);
    }
    // The card is a trusted contract (gnosis safe)
    IERC677(token).transfer(card, amount - _gasFee);

    emit CreatePrepaidCard(
      owner,
      card,
      token,
      amount - _gasFee,
      customizationDID
    );
    emit GasFeeCollected(owner, card, token, _gasFee);

    return card;
  }

  /**
   * @dev adapter execTransaction for prepaid card(gnosis safe)
   * @param card Prepaid Card's address
   * @param to Destination address of Safe transaction
   * @param data Data payload of Safe transaction
   * @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
   */
  function execTransaction(
    address payable card,
    address to,
    bytes memory data,
    bytes memory signatures,
    address _gasToken,
    address payable _gasRecipient
  ) private returns (bool) {
    require(
      GnosisSafe(card).execTransaction(
        to,
        0,
        data,
        Enum.Operation.Call,
        0,
        0,
        0,
        _gasToken,
        _gasRecipient,
        signatures
      ),
      "safe transaction was reverted"
    );

    return true;
  }

  /**
   * We are using a Prevalidated Signature (v = 1) type of signature for
   * signing from this contract (as opposed to EIP-1271, v = 0).
   * https://docs.gnosis.io/safe/docs/contracts_signatures/#pre-validated-signatures
   * This particular type of signature is a "pre-approved" signature. This
   * signature is considered valid only when the sender of gnosis safe exec
   * txn is the address within the signature or a GnosisSafe.approveHash() has
   * been called from the address within the signature on the safe in
   * question. In our case, since this contract issues
   * GnosisSafe.execTransaction() (in the execTransaction() function), we can
   * take advantage of the fact that all gnosis safe txn's will be sent from
   * this contract's address.
   *
   * signature type == 1
   * s = ignored
   * r = contract address with padding to 32 bytes
   * {32-bytes r}{32-bytes s}{1-byte signature type}
   */
  function getContractSignature()
    internal
    view
    returns (bytes memory contractSignature)
  {
    // Create signature
    contractSignature = new bytes(65);
    bytes memory encodeData = abi.encode(this, address(0));
    for (uint256 i = 1; i <= 64; i++) {
      contractSignature[64 - i] = encodeData[encodeData.length.sub(i)];
    }
    bytes1 v = 0x01;
    contractSignature[64] = v;
  }

  /**
   * @dev Append the contract's own signature to the signature we received from
   * the safe owner
   * @param prepaidCard the prepaid card address
   * @param signature Owner's signature
   */
  function addContractSignature(
    address payable prepaidCard,
    bytes memory signature
  ) internal view returns (bytes memory signatures) {
    require(signature.length == 65, "Invalid signature!");

    address owner = getPrepaidCardOwner(prepaidCard);
    bytes memory contractSignature = getContractSignature();
    signatures = new bytes(130); // 2 x 65 bytes
    // Gnosis safe require signature must be sort by owner' address
    if (address(this) > owner) {
      for (uint256 i = 0; i < signature.length; i++) {
        signatures[i] = signature[i];
      }
      for (uint256 i = 0; i < contractSignature.length; i++) {
        signatures[i.add(65)] = contractSignature[i];
      }
    } else {
      // For test coverage, unsure how to test in this branch since the address
      // of this contract is pretty arbitrary
      for (uint256 i = 0; i < contractSignature.length; i++) {
        signatures[i] = contractSignature[i];
      }
      for (uint256 i = 0; i < signature.length; i++) {
        signatures[i.add(65)] = signature[i];
      }
    }
  }

  function getPrepaidCardOwner(address payable prepaidCard)
    internal
    view
    returns (address)
  {
    address[] memory owners = GnosisSafe(prepaidCard).getOwners();
    require(owners.length == 2, "unexpected number of owners for prepaid card");
    return owners[0] == address(this) ? owners[1] : owners[0];
  }
}
