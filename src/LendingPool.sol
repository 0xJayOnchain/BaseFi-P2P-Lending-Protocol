// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IPriceFeed.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract LendingPool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    // P2P model structs (offers/requests/matches). Pool-style positions removed.

    struct LendingOffer {
        uint256 offerId;
        uint256 amount;
        uint256 minInterestRate;
        uint256 duration;
        bool active;
    }

    struct BorrowRequest {
        uint256 requestId;
        uint256 amount;
        uint256 maxInterestRate;
        address collateralToken;
        uint256 collateralAmount;
        uint256 duration;
        bool active;
    }

    struct Match {
        uint256 matchId;
        uint256 offerId;
        uint256 requestId;
        address lender;
        address borrower;
        uint256 amount;
        uint256 interestRate;
        uint256 startTime;
        uint256 duration;
        bool active;
    }

    // Counter for IDs
    uint256 private offerIdCounter;
    uint256 private requestIdCounter;
    uint256 private matchIdCounter;

     // Mappings for offers, requests, and matches
    mapping(address => mapping(address => LendingOffer[])) public lendingOffers; // token => user => offers
    mapping(address => mapping(address => BorrowRequest[])) public borrowRequests; // token => user => requests
    mapping(uint256 => Match) public matches; // matchId => Match

    mapping(address => bool) public supportedTokens;
    mapping(address => address) public priceFeeds; // token => price feed
    // Helper to fetch normalized price (1e18)
    function getNormalizedPrice(address token) public view returns (uint256) {
        address feed = priceFeeds[token];
        require(feed != address(0), "No price feed");
        uint8 decimals = IPriceFeed(feed).decimals();
        int256 price = IPriceFeed(feed).latestAnswer();
        require(price > 0, "Invalid price");
        // Normalize to 1e18
        return uint256(price) * (10 ** (18 - decimals));
    }
    // Configuration / fees
    uint256 public platformFee = 30;
    uint256 public constant OWNER_FEE_BPS = 10;
    uint256 public minCollateralRatio = 150;
    mapping(address => uint256) public ownerFees;

    // Events
    event LendingOfferCancelled(address indexed token, address indexed lender, uint256 offerId);
    event BorrowRequestCancelled(address indexed token, address indexed borrower, uint256 requestId);
    event OfferModified(address indexed token, address indexed lender, uint256 offerId);
    event RequestModified(address indexed token, address indexed borrower, uint256 requestId);
    event MatchCreated(uint256 indexed matchId, address indexed lender, address indexed borrower);
    event MatchClosed(uint256 indexed matchId);
    // P2P events (repay/liquidate reference a matchId)
    event Repay(uint256 indexed matchId, address indexed payer, uint256 amount, uint256 ownerFee);
    event Liquidate(uint256 indexed matchId, address indexed borrower, address liquidator, uint256 amount, uint256 ownerFee);
    event OwnerFeeClaimed(address indexed token, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function setPriceFeed(address token, address feed) external onlyOwner {
        require(token != address(0) && feed != address(0), "Invalid address");
        priceFeeds[token] = feed;
    }

    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        supportedTokens[token] = true;
    }

    function calculateOwnerFee(uint256 amount) public pure returns (uint256) {
        return (amount * OWNER_FEE_BPS) / 10000;
    }
    // P2P-related placeholders
    // TODO: Implement the P2P flows: createLendingOffer, cancelLendingOffer, createBorrowRequest,
    // acceptOfferByBorrower, acceptRequestByLender, repayLoan, liquidateLoan, claimOwnerFees, etc.

    function updatePrices() external onlyOwner {
        // price oracle integration hook for P2P valuation
    }

    // Minimal placeholder helpers kept for compatibility and future implementation
    function calculateLendingRate(address /*token*/) public view returns (uint256) {
        return 5; // placeholder
    }

    function calculateBorrowRate(address /*token*/) public view returns (uint256) {
        return 7; // placeholder
    }
}
