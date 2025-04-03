// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*//////////////////////////////////////////////////////////////
                                IMPORTS
//////////////////////////////////////////////////////////////*/
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {IERC721A} from "@erc721a/contracts/IERC721A.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RarityRewards
 * @author Nadina Oates
 * @notice Simple Chainlink Functions contract
 */
contract RarityRewards is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    enum Status {
        INACTIVE,
        ACTIVE,
        EXPIRED
    }

    struct ClaimPeriod {
        uint256 id;
        address token;
        uint256 amount;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        Status status;
    }

    struct Claims {
        uint256 periodId;
        address claimer;
        uint256 amount;
        uint256 numClaimed;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    string private constant TRAIT_TYPE = "Color";
    uint256 private constant NUM_TRAITS = 5;

    IERC721A private immutable i_collection;

    uint64 private immutable i_subId;
    bytes32 private immutable i_donID;
    string private i_source;

    uint32 private s_gasLimit;
    bytes32 private s_lastRequestId;
    bytes private s_lastResponse;
    bytes private s_lastError;

    uint256 private s_claimTime;
    uint256 private s_tokenIdToBeClaimed;
    uint256 private s_periodToBeClaimed;
    address private s_claimer;

    mapping(uint256 period => ClaimPeriod) private s_period;
    mapping(uint256 period => mapping(uint256 tokenId => bool)) private s_claimedTokenIds;
    mapping(uint256 period => mapping(address claimer => Claims)) private s_claims;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event Withdrawal(address indexed token, uint256 indexed periodId, uint256 indexed amount);
    event Deposit(address indexed token, uint256 indexed periodId, uint256 indexed amount);
    event Claimed(address indexed claimer, uint256 periodId, uint256 amount);
    event Activated(uint256 indexed periodId);
    event Deactivated(uint256 indexed periodId);
    event ClaimTimeSet(uint256 indexed time);
    event GasLimitSet(uint32 indexed gasLimit);
    event EmergencyWithdrawal(uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error UnexpectedRequestID(bytes32 requestId);
    error RarityRewards__ClaimPending();
    error RarityRewards__InvalidTokenOwner();
    error RarityRewards__InvalidTrait();
    error RarityRewards__ClaimPeriodExpired();
    error RarityRewards__InvalidTokenAddress();
    error RarityRewards__ClaimPeriodInactive();
    error RarityRewards__ClaimPeriodMustBeInactive(Status status);
    error RarityRewards__ClaimPeriodMustBeActive(Status status);
    error RarityRewards__ClaimPeriodActive();
    error RarityRewards__NothingToWithdraw();
    error RarityRewards__AlreadyClaimed();

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address collection, address router, uint64 subId, bytes32 donId, string memory source)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        i_collection = IERC721A(collection);

        i_subId = subId;
        i_donID = donId;
        i_source = source;
        s_gasLimit = 300_000;

        s_claimTime = 30 days;
    }

    // receive / fallback functions

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     *   @notice Deposits Revenue share
     *   @param periodId The period to be deposited to
     *   @param token The token to be deposited
     *   @param amount The amount to be deposited
     *   @param startTime The start time of the period
     */
    function deposit(uint256 periodId, address token, uint256 amount, uint256 startTime) external onlyOwner {
        _updateStatus(periodId);

        if (!_isInactive(periodId)) {
            revert RarityRewards__ClaimPeriodMustBeInactive(s_period[periodId].status);
        }

        if (s_period[periodId].amount > 0 && token != s_period[periodId].token) {
            revert RarityRewards__InvalidTokenAddress();
        }

        // update state variables
        s_period[periodId].amount += amount;
        s_period[periodId].startTime = startTime;
        s_period[periodId].endTime = startTime + s_claimTime;
        s_period[periodId].token = token;
        s_period[periodId].id = periodId;

        // transfer funds
        emit Deposit(s_period[periodId].token, periodId, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraws funds from specified period, only possible when period inactive
     * @param periodId The period to be withdrawn from
     */
    function withdraw(uint256 periodId) external onlyOwner {
        _updateStatus(periodId);

        if (_isActive(periodId)) {
            revert RarityRewards__ClaimPeriodMustBeInactive(s_period[periodId].status);
        }

        uint256 amount = s_period[periodId].amount;
        if (amount == 0) {
            revert RarityRewards__NothingToWithdraw();
        }

        address token = s_period[periodId].token;
        delete s_period[periodId];

        emit Withdrawal(token, periodId, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     *  @notice Activate a claim period
     *  @param periodId The period to be activated
     */
    function activate(uint256 periodId) external onlyOwner {
        _updateStatus(periodId);

        if (!_isInactive(periodId)) {
            revert RarityRewards__ClaimPeriodMustBeInactive(s_period[periodId].status);
        }

        s_period[periodId].status = Status.ACTIVE;
        emit Activated(periodId);
    }

    /**
     * @notice Deactives a claim period
     * @param periodId Period to be deactivated
     */
    function deactivate(uint256 periodId) external onlyOwner {
        _updateStatus(periodId);

        if (!_isActive(periodId)) {
            revert RarityRewards__ClaimPeriodMustBeActive(s_period[periodId].status);
        }

        s_period[periodId].status = Status.INACTIVE;
        emit Deactivated(periodId);
    }

    /**
     *  @notice Set the claim duration
     *  @param time The duration for claim periods.
     */
    function setClaimTime(uint256 time) external onlyOwner {
        s_claimTime = time;
        emit ClaimTimeSet(time);
    }

    /**
     *  @notice Set gas limit
     *  @param gasLimit gas limit
     */
    function setGasLimit(uint32 gasLimit) external onlyOwner {
        s_gasLimit = gasLimit;
        emit GasLimitSet(gasLimit);
    }

    /**
     *  @notice Withdraws funds from contract
     *  @dev DO NOT USE THIS WHEN CLAIMING IS RUNNING!
     *  @param token The token to be withdrawn
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));

        if (balance == 0) {
            revert RarityRewards__NothingToWithdraw();
        }

        emit EmergencyWithdrawal(balance);
        IERC20(token).safeTransfer(msg.sender, balance);
    }

    /**
     *  @notice Send a simple request
     *  @param periodId period to claim from
     *  @param tokenId token id for NFT to claim rewards for
     */
    function claim(uint256 periodId, uint256 tokenId) external returns (bytes32 requestId) {
        _updateStatus(periodId);

        if (!_isActive(periodId)) {
            revert RarityRewards__ClaimPeriodMustBeActive(s_period[periodId].status);
        }

        // check if claim is pending
        if (s_claimer != address(0)) {
            revert RarityRewards__ClaimPending();
        }

        // check if tokenId valid
        if (s_claimedTokenIds[periodId][tokenId]) {
            revert RarityRewards__AlreadyClaimed();
        }

        // or check if tokenId same
        s_tokenIdToBeClaimed = tokenId;

        // retrieve owner of NFT
        address tokenOwner = i_collection.ownerOf(tokenId);

        // check owner is valid
        if (msg.sender != tokenOwner) {
            revert RarityRewards__InvalidTokenOwner();
        }
        s_claimer = tokenOwner;

        // retrieve token uri
        s_periodToBeClaimed = periodId;

        // prepare arguments
        string[] memory args = new string[](2);
        args[0] = i_collection.tokenURI(tokenId);
        args[1] = TRAIT_TYPE;

        // prepare request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(i_source);
        req.setArgs(args);

        // send request
        requestId = _sendRequest(req.encodeCBOR(), i_subId, s_gasLimit, i_donID);
        s_lastRequestId = requestId;
        emit RequestSent(requestId);

        return requestId;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }

        s_lastResponse = response;
        s_lastError = err;
        emit Response(requestId, s_lastResponse, s_lastError);

        // read response
        string memory trait = string(response);

        uint256 periodId = s_periodToBeClaimed;
        uint256 tokenId = s_tokenIdToBeClaimed;
        address claimer = s_claimer;

        uint256 totalAmount = s_period[periodId].amount;
        uint256 totalClaimed = s_period[periodId].totalClaimed;
        address token = s_period[periodId].token;

        // calculate share based on trait
        // each trait gets 1 / 5 of amount
        // share = amount * 1 / NUM_TRAITS * 1 / i_traitSize[trait]
        uint256 payout = totalAmount / (NUM_TRAITS * _getTraitSize(trait));
        if (totalAmount - totalClaimed < payout) {
            payout = totalAmount - totalClaimed;
        }

        // update claims
        s_claims[periodId][claimer].periodId = periodId;
        s_claims[periodId][claimer].claimer = claimer;
        s_claims[periodId][claimer].amount += payout;
        s_claims[periodId][claimer].numClaimed++;

        // update period
        s_period[periodId].totalClaimed += payout;
        s_claimedTokenIds[periodId][tokenId] = true;

        delete s_periodToBeClaimed;
        delete s_tokenIdToBeClaimed;
        delete s_claimer;

        // transfer funds
        emit Claimed(claimer, periodId, payout);

        // check for balance in contract?
        IERC20(token).safeTransfer(claimer, payout);
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update status of claim period
     * @param periodId The period to be updated
     */
    function _updateStatus(uint256 periodId) private {
        uint256 startTime = s_period[periodId].startTime;
        uint256 endTime = s_period[periodId].endTime;
        if (endTime > 0 && endTime < block.timestamp) {
            s_period[periodId].status = Status.EXPIRED;
        } else if (startTime > 0 && startTime < block.timestamp) {
            s_period[periodId].status = Status.ACTIVE;
        }
    }

    /**
     * @notice Check if claim period is expired
     * @param periodId The period to be checked
     */
    function _isExpired(uint256 periodId) private view returns (bool) {
        return s_period[periodId].status == Status.EXPIRED;
    }

    /**
     * @notice Check if claim period is active
     * @param periodId The period to be checked
     */
    function _isActive(uint256 periodId) private view returns (bool) {
        return s_period[periodId].status == Status.ACTIVE;
    }

    /**
     * @notice Check if claim period is active
     * @param periodId The period to be checked
     */
    function _isInactive(uint256 periodId) private view returns (bool) {
        return s_period[periodId].status == Status.INACTIVE;
    }

    /**
     * @notice Get the size of a trait
     * @param trait The trait to be checked
     */
    function _getTraitSize(string memory trait) private pure returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(trait));

        if (key == keccak256("GREEN")) return 790;
        if (key == keccak256("BLUE")) return 100;
        if (key == keccak256("YELLOW")) return 80;
        if (key == keccak256("RED")) return 20;
        if (key == keccak256("PURPLE")) return 10;

        revert RarityRewards__InvalidTrait();
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getClaims(uint256 periodId, address claimer) external view returns (Claims memory) {
        return s_claims[periodId][claimer];
    }

    function getClaimPeriod(uint256 periodId) external view returns (ClaimPeriod memory) {
        return s_period[periodId];
    }

    function getClaimTime() external view returns (uint256) {
        return s_claimTime;
    }

    function getTraitSize(string memory trait) external pure returns (uint256) {
        return _getTraitSize(trait);
    }

    function getLastResponse() external view returns (bytes memory) {
        return s_lastResponse;
    }

    function getSubscriptionId() external view returns (uint64) {
        return i_subId;
    }

    function getGasLimit() external view returns (uint32) {
        return s_gasLimit;
    }

    function getDonID() external view returns (bytes32) {
        return i_donID;
    }

    function getSource() external view returns (string memory) {
        return i_source;
    }
}
