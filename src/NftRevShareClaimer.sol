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
 * @title NftRevShareClaimer
 * @author Nadina Oates
 * @notice Simple Chainlink Functions contract
 */
contract NftRevShareClaimer is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    enum Status {
        INACTIVE,
        ACTIVE
    }

    struct ClaimPeriod {
        address token;
        uint256 amount;
        uint256 claimed;
        uint256 startTime;
        uint256 endTime;
        Status status;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    string private constant TRAIT_TYPE = "Color";
    uint256 private constant NUM_TRAITS = 5;
    uint256 private constant TOTAL_SUPPLY = 1000;
    uint256 private constant PRECISION = 1e18;

    IERC721A private immutable i_collection;

    uint64 private immutable i_subId;
    uint32 private immutable i_gasLimit;
    bytes32 private immutable i_donID;
    string private i_source;

    bytes32 private s_lastRequestId;
    bytes private s_lastResponse;
    bytes private s_lastError;

    uint256 private s_claimDuration;
    uint256 private s_periodToBeClaimed;
    address private s_currentClaimer;

    mapping(uint256 period => ClaimPeriod) private s_period;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event RequestRevertedWithErrorMsg(string reason);
    event RequestRevertedWithoutErrorMsg(bytes data);
    event Withdrawal(address indexed token, uint256 indexed periodId, uint256 indexed amount);
    event Deposit(address indexed token, uint256 indexed periodId, uint256 indexed amount);
    event Claimed(address indexed claimer, uint256 periodId, uint256 amount);
    event Activated(uint256 indexed periodId);
    event Deactivated(uint256 indexed periodId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error UnexpectedRequestID(bytes32 requestId);
    error NftRevShareClaimer__ClaimPending();
    error NftRevShareClaimer__InvalidTokenOwner();
    error NftRevShareClaimer__InvalidTrait();
    error NftRevShareClaimer__ClaimPeriodExpired();
    error NftRevShareClaimer__InvalidTokenAddress();
    error NftRevShareClaimer__ClaimPeriodInactive();
    error NftRevShareClaimer__ClaimPeriodActive();
    error NftRevShareClaimer__NothingToWithdraw();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier noPendingClaim() {
        if (s_currentClaimer != address(0)) {
            revert NftRevShareClaimer__ClaimPending();
        }
        _;
    }

    modifier notExpired(uint256 period) {
        uint256 endTime = s_period[period].endTime;
        if (endTime > 0 && endTime < block.timestamp) {
            revert NftRevShareClaimer__ClaimPeriodExpired();
        }
        _;
    }

    modifier isActive(uint256 period) {
        uint256 endTime = s_period[period].endTime;
        if (endTime > 0 && endTime < block.timestamp) {
            s_period[period].status = Status.INACTIVE;
            revert NftRevShareClaimer__ClaimPeriodExpired();
        }
        if (s_period[period].status != Status.ACTIVE) {
            revert NftRevShareClaimer__ClaimPeriodInactive();
        }
        _;
    }

    modifier isInactive(uint256 period) {
        uint256 endTime = s_period[period].endTime;
        if (endTime > 0 && endTime < block.timestamp) {
            s_period[period].status = Status.INACTIVE;
        }
        if (s_period[period].status == Status.ACTIVE) {
            revert NftRevShareClaimer__ClaimPeriodActive();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address collection, address router, uint64 subId, bytes32 donId, string memory source)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        i_subId = subId;
        i_gasLimit = 300_000;
        i_donID = donId;
        i_source = source;

        i_collection = IERC721A(collection);

        s_claimDuration = 30 days;
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
    function deposit(uint256 periodId, address token, uint256 amount, uint256 startTime)
        external
        onlyOwner
        isInactive(periodId)
        notExpired(periodId)
    {
        ClaimPeriod memory period = s_period[periodId];

        if (period.amount > 0 && token != period.token) {
            revert NftRevShareClaimer__InvalidTokenAddress();
        }

        // update state variables
        period.amount += amount;
        period.startTime = startTime;
        period.endTime = startTime + s_claimDuration;
        period.token = token;

        s_period[periodId] = period;

        // transfer funds
        emit Deposit(period.token, periodId, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraws funds from specified period, only possible when period inactive
     * @param periodId The period to be withdrawn from
     */
    function withdraw(uint256 periodId) external onlyOwner isInactive(periodId) {
        ClaimPeriod memory period = s_period[periodId];

        uint256 amount = period.amount;
        if (amount == 0) {
            revert NftRevShareClaimer__NothingToWithdraw();
        }

        delete s_period[periodId];

        emit Withdrawal(period.token, periodId, amount);
        IERC20(period.token).safeTransfer(msg.sender, amount);
    }

    /**
     *  @notice Activate a claim period
     *  @param periodId The period to be activated
     */
    function activate(uint256 periodId) external onlyOwner notExpired(periodId) isInactive(periodId) {
        s_period[periodId].status = Status.ACTIVE;
        emit Activated(periodId);
    }

    /**
     * @notice Deactives a claim period
     * @param periodId Period to be deactivated
     */
    function deactivate(uint256 periodId) external onlyOwner isActive(periodId) {
        s_period[periodId].status = Status.INACTIVE;
        emit Deactivated(periodId);
    }

    /**
     *  @notice Send a simple request
     *  @param periodId period to claim from
     *  @param tokenId token id for NFT to claim rewards fro
     */
    function claim(uint256 periodId, uint256 tokenId)
        external
        notExpired(periodId)
        isActive(periodId)
        noPendingClaim
        returns (bytes32 requestId)
    {
        // retrieve owner of NFT
        address tokenOwner = i_collection.ownerOf(tokenId);

        // check owner is valid
        if (msg.sender != tokenOwner) {
            revert NftRevShareClaimer__InvalidTokenOwner();
        }
        s_currentClaimer = tokenOwner;

        // retrieve token uri
        string memory tokenUri = i_collection.tokenURI(tokenId);
        s_periodToBeClaimed = periodId;

        // prepare arguments
        string[] memory args = new string[](2);
        args[0] = tokenUri;
        args[1] = TRAIT_TYPE;

        // prepare request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(i_source);
        req.setArgs(args);

        // send request
        s_lastRequestId = _sendRequest(req.encodeCBOR(), i_subId, i_gasLimit, i_donID);
        emit RequestSent(requestId);

        return s_lastRequestId;
    }

    /**
     * @notice Send a pre-encoded CBOR request
     * @param request CBOR-encoded request data
     * @param subscriptionId Billing ID
     * @param gasLimit The maximum amount of gas the request can consume
     * @param donID ID of the job to be invoked
     * @return requestId The ID of the sent request
     */
    function sendRequestCBOR(bytes memory request, uint64 subscriptionId, uint32 gasLimit, bytes32 donID)
        external
        onlyOwner
        returns (bytes32 requestId)
    {
        s_lastRequestId = _sendRequest(request, subscriptionId, gasLimit, donID);
        return s_lastRequestId;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
        address claimer = s_currentClaimer;
        ClaimPeriod memory period = s_period[periodId];

        // calculate share based on trait
        // each trait gets 1 / 5 of amount
        // share = amount * 1 / NUM_TRAITS * 1 / i_traitSize[trait]
        uint256 payout = period.amount / (NUM_TRAITS * _getTraitSize(trait));
        if (period.amount - period.claimed < payout) {
            payout = period.amount - period.claimed;
        }

        // update state variables
        period.claimed += payout;
        s_period[periodId] = period;
        delete s_currentClaimer;

        // transfer funds
        emit Claimed(claimer, periodId, payout);
        IERC20(period.token).safeTransfer(claimer, payout);
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getTraitSize(string memory trait) private pure returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(trait));

        if (key == keccak256("GREEN")) return 790;
        if (key == keccak256("BLUE")) return 100;
        if (key == keccak256("YELLOW")) return 80;
        if (key == keccak256("RED")) return 20;
        if (key == keccak256("PURPLE")) return 10;

        revert NftRevShareClaimer__InvalidTrait();
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getClaimPeriod(uint256 periodId) external view returns (ClaimPeriod memory) {
        return s_period[periodId];
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
        return i_gasLimit;
    }

    function getDonID() external view returns (bytes32) {
        return i_donID;
    }

    function getSource() external view returns (string memory) {
        return i_source;
    }
}
