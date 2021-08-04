pragma solidity 0.5.17;

import "@openzeppelin/contract-upgradeable/contracts/ownership/Ownable.sol";
import "@openzeppelin/contract-upgradeable/contracts/math/SafeMath.sol";
import "../RewardManager.sol";
import "../MerchantManager.sol";
import "../RevenuePool.sol";
import "../Exchange.sol";
import "../core/Versionable.sol";

contract RegisterRewardProgramHandler is Ownable, Versionable {
    using SafeMath for uint256;
    event Setup();
    event RewardProgramRegistrationFee(
        address prepaidCard,
        address issuingToken,
        uint256 issuingTokenAmount,
        uint256 spendAmount
    );
    address public merchantManager;
    address public revenuePoolAddress;
    address public exchangeAddress;
    address public actionDispatcher;
    address public prepaidCardManager;
    address public tokenManagerAddress;
    address public rewardManagerAddress;

    function setup(
        address _actionDispatcher,
        address _merchantManager,
        address _prepaidCardManager,
        address _revenuePoolAddress,
        address _exchangeAddress,
        address _tokenManagerAddress,
        address _rewardManagerAddress
    ) external onlyOwner returns (bool) {
        actionDispatcher = _actionDispatcher;
        revenuePoolAddress = _revenuePoolAddress;
        prepaidCardManager = _prepaidCardManager;
        merchantManager = _merchantManager;
        exchangeAddress = _exchangeAddress;
        tokenManagerAddress = _tokenManagerAddress;
        rewardManagerAddress = _rewardManagerAddress;
        emit Setup();
        return true;
    }

    /**
     * @dev onTokenTransfer(ERC677) - this is the ERC677 token transfer callback.
     * handle a merchant registration
     * @param from the token sender (should be the action dispatcher)
     * @param amount the amount of tokens being transferred
     * @param data the data encoded as (address prepaidCard, uint256 spendAmount, bytes actionData)
     * where actionData is encoded as (address infoDID)
     */
    function onTokenTransfer(
        address payable from,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        require(
            TokenManager(tokenManagerAddress).isValidToken(msg.sender),
            "calling token is unaccepted"
        );
        require(
            from == actionDispatcher,
            "can only accept tokens from action dispatcher"
        );
        RewardManager rewardManager = RewardManager(rewardManagerAddress);
        uint256 rewardProgramRegistrationFeeInSPEND =
            rewardManager.rewardProgramRegistrationFeeInSPEND();

        (address payable prepaidCard, , bytes memory actionData) =
            abi.decode(data, (address, uint256, bytes));

        (address admin, address rewardProgramID) =
            abi.decode(actionData, (address, address));

        uint256 rewardProgramRegistrationFeeInToken =
            Exchange(exchangeAddress).convertFromSpend(
                msg.sender, // issuing token address
                rewardProgramRegistrationFeeInSPEND
            );
        require(
            amount >= rewardProgramRegistrationFeeInToken,
            "Insufficient funds for reward program registration"
        );

        IERC677(msg.sender).transfer(
            rewardManager.rewardFeeReceiver(),
            rewardProgramRegistrationFeeInToken
        );

        uint256 refund = amount.sub(rewardProgramRegistrationFeeInToken);
        if (refund > 0) {
            IERC677(msg.sender).transfer(prepaidCard, refund);
        }

        emit RewardProgramRegistrationFee(
            prepaidCard,
            msg.sender,
            amount,
            rewardProgramRegistrationFeeInSPEND
        );
        RewardManager(rewardManagerAddress).registerRewardProgram(
            admin,
            rewardProgramID
        );
        return true;
    }
}
