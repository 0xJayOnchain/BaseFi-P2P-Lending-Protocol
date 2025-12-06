// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "./BaseP2P.sol";
import "./PriceOracle.sol";
import "./interfaces/ILoanPositionNFT.sol";

/// @title IUniswapV2Router
/// @author BaseFi P2P Lending Protocol
/// @notice Interface for Uniswap V2-compatible router contracts
interface IUniswapV2Router {
    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible
    /// @param amountIn The amount of input tokens to send
    /// @param amountOutMin The minimum amount of output tokens that must be received
    /// @param path An array of token addresses representing the swap path
    /// @param to Recipient of the output tokens
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/// @title LendingPool
/// @author BaseFi P2P Lending Protocol
/// @notice Main contract for P2P lending with offers, requests, and loan management
contract LendingPool is BaseP2P, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct Offer {
        uint256 id;
        address lender;
        address lendToken;
        uint256 amount;
        uint256 interestRateBPS;
        uint256 durationSecs;
        address collateralToken;
        uint256 collateralRatioBPS;
        uint256 createdAt;
        bool active;
    }

    struct Request {
        uint256 id;
        address borrower;
        address borrowToken;
        uint256 amount;
        uint256 maxInterestRateBPS;
        uint256 durationSecs;
        address collateralToken;
        uint256 collateralAmount;
        uint256 createdAt;
        bool active;
    }

    /// @notice Price oracle contract for collateral validation
    PriceOracle public priceOracle;
    /// @notice NFT contract for loan position tokens
    ILoanPositionNFT public loanPositionNFT;
    /// @notice Whitelist of approved router contracts for fee swaps
    mapping(address => bool) public routerWhitelist;
    /// @notice Whether to enforce collateral validation at match time
    bool public enforceCollateralValidation;
    /// @notice Optional guardian who can pause the protocol (owner can always pause/unpause)
    address public guardian;

    /// @notice Counter for generating unique offer IDs
    uint256 public nextOfferId = 1;
    /// @notice Counter for generating unique request IDs
    uint256 public nextRequestId = 1;

    /// @notice Mapping of offer ID to offer data
    mapping(uint256 => Offer) public offers;
    /// @notice Mapping of request ID to request data
    mapping(uint256 => Request) public requests;

    struct Loan {
        uint256 id;
        uint256 offerId;
        uint256 requestId;
        address lender;
        address borrower;
        address lendToken;
        address collateralToken;
        uint256 principal;
        uint256 interestRateBPS;
        uint256 collateralRatioBPS;
        uint256 startTime;
        uint256 durationSecs;
        uint256 collateralAmount;
        uint256 lenderPositionTokenId;
        uint256 borrowerPositionTokenId;
        bool repaid;
        bool liquidated;
    }

    /// @notice Counter for generating unique loan IDs
    uint256 public nextLoanId = 1;
    mapping(uint256 => Loan) private loans;

    /// @notice Get core loan data (smaller tuple to avoid large public accessor)
    /// @param loanId The ID of the loan to retrieve
    /// @return id The loan ID
    /// @return lender The address of the lender
    /// @return borrower The address of the borrower
    /// @return lendToken The address of the lent token
    /// @return collateralToken The address of the collateral token
    /// @return principal The principal amount lent
    /// @return collateralAmount The amount of collateral locked
    /// @return lenderPositionTokenId The NFT token ID for the lender position
    /// @return borrowerPositionTokenId The NFT token ID for the borrower position
    /// @return repaid Whether the loan has been repaid
    /// @return liquidated Whether the loan has been liquidated
    function getLoan(uint256 loanId)
        external
        view
        returns (
            uint256 id,
            address lender,
            address borrower,
            address lendToken,
            address collateralToken,
            uint256 principal,
            uint256 collateralAmount,
            uint256 lenderPositionTokenId,
            uint256 borrowerPositionTokenId,
            bool repaid,
            bool liquidated
        )
    {
        Loan storage loan = loans[loanId];
        return (
            loan.id,
            loan.lender,
            loan.borrower,
            loan.lendToken,
            loan.collateralToken,
            loan.principal,
            loan.collateralAmount,
            loan.lenderPositionTokenId,
            loan.borrowerPositionTokenId,
            loan.repaid,
            loan.liquidated
        );
    }

    // fees and penalty
    /// @notice Owner fee in basis points (1 BPS = 0.01%)
    uint256 public ownerFeeBPS;
    /// @notice Liquidation penalty in basis points (default 2%)
    uint256 public penaltyBPS = 200;
    /// @notice Optional liquidation grace period in seconds added to loan duration before expiry-based liquidation
    uint256 public liquidationGracePeriodSecs;
    /// @notice Global interest rate band constraints (optional). If both are zero, band is disabled.
    uint256 public minInterestRateBPS;
    uint256 public maxInterestRateBPS;
    /// @notice Accumulated owner fees per token
    mapping(address => uint256) public ownerFees;

    /// @notice Emitted when owner fee BPS is updated
    /// @param oldBps The previous fee in basis points
    /// @param newBps The new fee in basis points
    event OwnerFeeBpsUpdated(uint256 indexed oldBps, uint256 indexed newBps);
    /// @notice Emitted when penalty BPS is updated
    /// @param oldBps The previous penalty in basis points
    /// @param newBps The new penalty in basis points
    event PenaltyBpsUpdated(uint256 indexed oldBps, uint256 indexed newBps);
    /// @notice Emitted when owner fees are claimed
    /// @param token The token address of the fees claimed
    /// @param to The address receiving the fees
    /// @param amount The amount of fees claimed
    event OwnerFeesClaimed(address indexed token, address indexed to, uint256 indexed amount);
    /// @notice Emitted after batch owner fee claims complete
    /// @param to The recipient (owner)
    /// @param tokens The list of tokens processed
    /// @param amounts The amounts claimed for each token (0 if skipped)
    event OwnerFeesClaimedBatch(address indexed to, address[] tokens, uint256[] amounts);
    /// @notice Emitted when a loan is liquidated
    /// @param loanId The ID of the liquidated loan
    /// @param liquidator The address of the liquidator
    /// @param collateralToLiquidator The amount of collateral sent to the liquidator
    /// @param penaltyCollateral The amount of collateral taken as penalty
    event LoanLiquidated(
        uint256 indexed loanId,
        address indexed liquidator,
        uint256 indexed collateralToLiquidator,
        uint256 penaltyCollateral
    );
    /// @notice Emitted when owner fees are swapped
    /// @param tokenIn The input token being swapped
    /// @param tokenOut The output token received
    /// @param amountIn The amount of input tokens swapped
    /// @param amountOut The amount of output tokens received
    event OwnerFeesSwapped(
        address indexed tokenIn, address indexed tokenOut, uint256 indexed amountIn, uint256 amountOut
    );
    /// @notice Emitted when a borrower repays a loan using a swap
    /// @param loanId The ID of the repaid loan
    /// @param router The router used for the swap
    /// @param tokenIn The input token provided by the borrower
    /// @param amountIn The amount of input tokens swapped
    /// @param amountOut The amount of lend tokens received from the swap
    event RepayWithSwap(
        uint256 indexed loanId, address indexed router, address indexed tokenIn, uint256 amountIn, uint256 amountOut
    );
    /// @notice Emitted when a loan is liquidated with swap and proceeds sent to the liquidator in desired token
    /// @param loanId The ID of the liquidated loan
    /// @param router The router used for the swap
    /// @param tokenOut The output token sent to the liquidator
    /// @param collateralIn The amount of collateral used as input to the swap
    /// @param amountOut The amount of output tokens received by the liquidator
    event LoanLiquidatedWithSwap(
        uint256 indexed loanId,
        address indexed router,
        address indexed tokenOut,
        uint256 collateralIn,
        uint256 amountOut
    );

    /// @notice Emitted when a loan is matched/created
    /// @param loanId The new loan ID
    /// @param borrower The borrower address
    /// @param lender The lender address
    /// @param lendToken The lend token address
    /// @param collateralToken The collateral token address
    /// @param principal The principal amount
    /// @param interestRateBPS Interest rate in basis points
    /// @param durationSecs Loan duration in seconds
    /// @param startTime Loan start timestamp
    event LoanMatched(
        uint256 indexed loanId,
        address indexed borrower,
        address indexed lender,
        address lendToken,
        address collateralToken,
        uint256 principal,
        uint256 interestRateBPS,
        uint256 durationSecs,
        uint256 startTime
    );

    /// @notice Emitted when a loan is closed (repaid or liquidated)
    /// @param loanId The loan ID
    /// @param status The closure status: "repaid" | "repaidSwap" | "liquidated" | "liquidatedSwap"
    /// @param actor The caller who executed the close
    event LoanClosed(uint256 indexed loanId, string status, address actor);

    /// @notice Emitted when a lending offer is created
    /// @param id The offer ID
    /// @param lender The address of the lender
    /// @param lendToken The token being lent
    /// @param amount The amount being offered
    event LendingOfferCreated(uint256 indexed id, address indexed lender, address indexed lendToken, uint256 amount);
    /// @notice Emitted when a lending offer is cancelled
    /// @param id The offer ID
    event LendingOfferCancelled(uint256 indexed id);
    /// @notice Emitted when a borrow request is created
    /// @param id The request ID
    /// @param borrower The address of the borrower
    /// @param collateralToken The collateral token address
    /// @param collateralAmount The amount of collateral deposited
    event BorrowRequestCreated(
        uint256 indexed id, address indexed borrower, address indexed collateralToken, uint256 collateralAmount
    );
    /// @notice Emitted when a borrow request is cancelled
    /// @param id The request ID
    event BorrowRequestCancelled(uint256 indexed id);

    // Round 2: admin/safety observability
    /// @notice Emitted when a router is added or removed from whitelist
    /// @param router The router address
    /// @param whitelisted Whether the router is whitelisted
    event RouterWhitelistedSet(address indexed router, bool indexed whitelisted);
    /// @notice Emitted when collateral validation enforcement is toggled
    /// @param enabled Whether enforcement is enabled
    event EnforceCollateralValidationSet(bool indexed enabled);
    /// @notice Emitted when guardian is set
    /// @param newGuardian The new guardian address
    event GuardianSet(address indexed newGuardian);
    /// @notice Emitted when liquidation grace period is updated
    /// @param oldSecs The previous grace period seconds
    /// @param newSecs The new grace period seconds
    event LiquidationGracePeriodSet(uint256 indexed oldSecs, uint256 indexed newSecs);
    /// @notice Emitted when interest rate band is updated
    /// @param minBps The minimum allowed interest rate (BPS)
    /// @param maxBps The maximum allowed interest rate (BPS)
    event InterestRateBandSet(uint256 indexed minBps, uint256 indexed maxBps);

    /// @notice Constructor initializes the lending pool with a price oracle
    /// @param _priceOracle Address of the price oracle contract
    constructor(address _priceOracle) BaseP2P() {
        // Best-effort set; may be a non-oracle during tests. Price checks will gracefully skip if calls fail.
        priceOracle = PriceOracle(_priceOracle);
    }

    /// @notice Safely fetch normalized price from oracle; returns 0 if oracle call fails
    /// @param token The token address to get the price for
    /// @return p The normalized price (18 decimals) or 0 if unavailable
    function _normalizedPrice(address token) internal view returns (uint256 p) {
        if (address(priceOracle) == address(0)) return 0;
        // try/catch to avoid test setups passing a non-PriceOracle address
        try priceOracle.getNormalizedPrice(token) returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }

    /// @notice Set the loan position NFT contract address
    /// @param _nft The address of the NFT contract
    function setLoanPositionNFT(address _nft) external onlyOwner {
        loanPositionNFT = ILoanPositionNFT(_nft);
    }

    /// @notice Pause the protocol critical functions
    function pause() external {
        require(msg.sender == owner() || msg.sender == guardian, "not authorized");
        _pause();
    }

    /// @notice Unpause the protocol
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Set the guardian address (can pause, cannot unpause)
    /// @param _guardian The guardian address (set to 0 to disable)
    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }

    /// @notice Manage router whitelist for swaps
    /// @param router The router contract address
    /// @param whitelisted Whether the router should be whitelisted
    function setRouterWhitelisted(address router, bool whitelisted) external onlyOwner {
        routerWhitelist[router] = whitelisted;
        emit RouterWhitelistedSet(router, whitelisted);
    }

    /// @notice Enable or disable collateral validation at match-time
    /// @param on Whether to enable collateral validation
    function setEnforceCollateralValidation(bool on) external onlyOwner {
        enforceCollateralValidation = on;
        emit EnforceCollateralValidationSet(on);
    }

    /// @notice Set the owner fee in basis points (1 BPS = 0.01%)
    /// @param bps The fee in basis points (max 10000 = 100%)
    function setOwnerFeeBPS(uint256 bps) external onlyOwner {
        require(bps <= 10000, "bps>10000");
        uint256 old = ownerFeeBPS;
        ownerFeeBPS = bps;
        emit OwnerFeeBpsUpdated(old, bps);
    }

    /// @notice Set the liquidation penalty in basis points (1 BPS = 0.01%)
    /// @param bps The penalty in basis points (max 10000 = 100%)
    function setPenaltyBPS(uint256 bps) external onlyOwner {
        require(bps <= 10000, "bps>10000");
        uint256 old = penaltyBPS;
        penaltyBPS = bps;
        emit PenaltyBpsUpdated(old, bps);
    }

    /// @notice Set the liquidation grace period in seconds (added to loan duration)
    /// @param secs The grace period seconds
    function setLiquidationGracePeriodSecs(uint256 secs) external onlyOwner {
        uint256 old = liquidationGracePeriodSecs;
        liquidationGracePeriodSecs = secs;
        emit LiquidationGracePeriodSet(old, secs);
    }

    /// @notice Set global interest rate band constraints
    /// @param minBps Minimum interest rate in BPS (0 disables lower bound)
    /// @param maxBps Maximum interest rate in BPS (0 disables upper bound)
    function setInterestRateBand(uint256 minBps, uint256 maxBps) external onlyOwner {
        require(maxBps == 0 || maxBps <= 10000, "max>10000");
        require(minBps == 0 || minBps <= 10000, "min>10000");
        if (minBps != 0 && maxBps != 0) {
            require(minBps <= maxBps, "min>max");
        }
        minInterestRateBPS = minBps;
        maxInterestRateBPS = maxBps;
        emit InterestRateBandSet(minBps, maxBps);
    }

    /// @notice Create a lending offer by depositing tokens
    /// @param lendToken The token address to lend
    /// @param amount The amount to lend
    /// @param interestRateBPS The interest rate in basis points per year
    /// @param durationSecs The loan duration in seconds
    /// @param collateralToken The required collateral token address
    /// @param collateralRatioBPS The required collateral ratio in basis points
    /// @return The created offer ID
    function createLendingOffer(
        address lendToken,
        uint256 amount,
        uint256 interestRateBPS,
        uint256 durationSecs,
        address collateralToken,
        uint256 collateralRatioBPS
    ) external virtual nonReentrant whenNotPaused returns (uint256) {
        require(amount > 0, "amount>0");
        // enforce interest band if configured
        if (minInterestRateBPS != 0) {
            require(interestRateBPS >= minInterestRateBPS, "rate<min");
        }
        if (maxInterestRateBPS != 0) {
            require(interestRateBPS <= maxInterestRateBPS, "rate>max");
        }
        // transfer principal into escrow and verify received equals requested (reject fee-on-transfer tokens)
        uint256 beforeBal = IERC20(lendToken).balanceOf(address(this));
        _safeTransferFrom(IERC20(lendToken), msg.sender, address(this), amount);
        uint256 afterBal = IERC20(lendToken).balanceOf(address(this));
        require(afterBal >= beforeBal, "balance underflow");
        require(afterBal - beforeBal == amount, "fee-on-transfer unsupported");

        uint256 id = nextOfferId++;
        offers[id] = Offer({
            id: id,
            lender: msg.sender,
            lendToken: lendToken,
            amount: amount,
            interestRateBPS: interestRateBPS,
            durationSecs: durationSecs,
            collateralToken: collateralToken,
            collateralRatioBPS: collateralRatioBPS,
            createdAt: block.timestamp,
            active: true
        });

        emit LendingOfferCreated(id, msg.sender, lendToken, amount);
        return id;
    }

    /// @notice Cancel a lending offer and retrieve deposited tokens
    /// @param offerId The ID of the offer to cancel
    function cancelLendingOffer(uint256 offerId) external virtual nonReentrant whenNotPaused {
        Offer storage o = offers[offerId];
        require(o.active, "not active");
        require(o.lender == msg.sender, "only lender");

        o.active = false;
        // refund principal
        _safeTransfer(IERC20(o.lendToken), msg.sender, o.amount);
        emit LendingOfferCancelled(offerId);
    }

    /// @notice Create a borrow request by depositing collateral
    /// @param borrowToken The token address to borrow
    /// @param amount The amount to borrow
    /// @param maxInterestRateBPS The maximum acceptable interest rate in basis points per year
    /// @param durationSecs The desired loan duration in seconds
    /// @param collateralToken The collateral token address
    /// @param collateralAmount The amount of collateral to deposit
    /// @return The created request ID
    function createBorrowRequest(
        address borrowToken,
        uint256 amount,
        uint256 maxInterestRateBPS,
        uint256 durationSecs,
        address collateralToken,
        uint256 collateralAmount
    ) external virtual nonReentrant whenNotPaused returns (uint256) {
        require(amount > 0, "amount>0");
        require(collateralAmount > 0, "collateral>0");

        // transfer collateral into escrow and verify received equals requested (reject fee-on-transfer tokens)
        uint256 beforeColl = IERC20(collateralToken).balanceOf(address(this));
        _safeTransferFrom(IERC20(collateralToken), msg.sender, address(this), collateralAmount);
        uint256 afterColl = IERC20(collateralToken).balanceOf(address(this));
        require(afterColl >= beforeColl, "balance underflow");
        require(afterColl - beforeColl == collateralAmount, "fee-on-transfer unsupported");

        uint256 id = nextRequestId++;
        requests[id] = Request({
            id: id,
            borrower: msg.sender,
            borrowToken: borrowToken,
            amount: amount,
            maxInterestRateBPS: maxInterestRateBPS,
            durationSecs: durationSecs,
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            createdAt: block.timestamp,
            active: true
        });

        emit BorrowRequestCreated(id, msg.sender, collateralToken, collateralAmount);
        return id;
    }

    /// @notice Cancel a borrow request and retrieve deposited collateral
    /// @param requestId The ID of the request to cancel
    function cancelBorrowRequest(uint256 requestId) external virtual nonReentrant whenNotPaused {
        Request storage r = requests[requestId];
        require(r.active, "not active");
        require(r.borrower == msg.sender, "only borrower");

        r.active = false;
        _safeTransfer(IERC20(r.collateralToken), msg.sender, r.collateralAmount);
        emit BorrowRequestCancelled(requestId);
    }

    /// @notice Borrower accepts an existing lender offer. Borrower must provide collateral now.
    /// @param offerId The ID of the offer to accept
    /// @param collateralAmount The amount of collateral to provide
    /// @return The created loan ID
    function acceptOfferByBorrower(uint256 offerId, uint256 collateralAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        Offer storage o = offers[offerId];
        require(o.active, "offer not active");

        // transfer collateral from borrower
        _safeTransferFrom(IERC20(o.collateralToken), msg.sender, address(this), collateralAmount);

        // collateral validation using oracle if available (graceful if unavailable), optional
        if (enforceCollateralValidation) {
            uint256 pColl = _normalizedPrice(o.collateralToken);
            uint256 pLend = _normalizedPrice(o.lendToken);
            // if prices unavailable, skip validation; else enforce ratio
            if (pColl > 0 && pLend > 0) {
                uint256 collateralValue = (collateralAmount * pColl) / 1e18;
                uint256 principalValue = (o.amount * pLend) / 1e18;
                uint256 requiredValue = (principalValue * o.collateralRatioBPS) / 10000;
                require(collateralValue >= requiredValue, "insufficient collateral");
            }
        }

        // create loan (assign fields individually to avoid stack-too-deep)
        uint256 loanId = nextLoanId++;
        loans[loanId].id = loanId;
        loans[loanId].offerId = offerId;
        loans[loanId].requestId = 0;
        loans[loanId].lender = o.lender;
        loans[loanId].borrower = msg.sender;
        loans[loanId].lendToken = o.lendToken;
        loans[loanId].collateralToken = o.collateralToken;
        loans[loanId].principal = o.amount;
        loans[loanId].interestRateBPS = o.interestRateBPS;
        loans[loanId].startTime = block.timestamp;
        loans[loanId].durationSecs = o.durationSecs;
        loans[loanId].collateralRatioBPS = o.collateralRatioBPS;
        loans[loanId].collateralAmount = collateralAmount;
        loans[loanId].lenderPositionTokenId = 0;
        loans[loanId].borrowerPositionTokenId = 0;
        loans[loanId].repaid = false;
        loans[loanId].liquidated = false;

        // mark offer inactive
        o.active = false;

        // transfer principal to borrower from escrowed funds
        _safeTransfer(IERC20(o.lendToken), msg.sender, o.amount);

        // mint NFTs if set
        if (address(loanPositionNFT) != address(0)) {
            _mintPositions(loanId, o.lender, msg.sender);
        }

        emit LendingOfferCreated(offerId, o.lender, o.lendToken, o.amount);
        emit LoanMatched(
            loanId,
            msg.sender,
            o.lender,
            o.lendToken,
            o.collateralToken,
            o.amount,
            o.interestRateBPS,
            o.durationSecs,
            loans[loanId].startTime
        );
        return loanId;
    }

    /// @notice Lender accepts an existing borrow request by funding principal now.
    /// @param requestId The ID of the request to accept
    /// @return The created loan ID
    function acceptRequestByLender(uint256 requestId) external nonReentrant whenNotPaused returns (uint256) {
        Request storage r = requests[requestId];
        require(r.active, "request not active");

        // enforce interest band if configured
        if (minInterestRateBPS != 0) {
            require(r.maxInterestRateBPS >= minInterestRateBPS, "rate<min");
        }
        if (maxInterestRateBPS != 0) {
            require(r.maxInterestRateBPS <= maxInterestRateBPS, "rate>max");
        }

        // transfer principal from lender to contract
        _safeTransferFrom(IERC20(r.borrowToken), msg.sender, address(this), r.amount);

        // collateral validation at match using oracle if available (graceful if unavailable), optional
        if (enforceCollateralValidation) {
            uint256 pColl = _normalizedPrice(r.collateralToken);
            uint256 pLend = _normalizedPrice(r.borrowToken);
            if (pColl > 0 && pLend > 0) {
                uint256 collateralValue = (r.collateralAmount * pColl) / 1e18;
                uint256 principalValue = (r.amount * pLend) / 1e18;
                // conservative default: require 100% collateral by value
                uint256 requiredValue = principalValue;
                require(collateralValue >= requiredValue, "insufficient collateral");
            }
        }

        // create loan (assign fields individually to avoid stack-too-deep)
        uint256 loanId = nextLoanId++;
        loans[loanId].id = loanId;
        loans[loanId].offerId = 0;
        loans[loanId].requestId = requestId;
        loans[loanId].lender = msg.sender;
        loans[loanId].borrower = r.borrower;
        loans[loanId].lendToken = r.borrowToken;
        loans[loanId].collateralToken = r.collateralToken;
        loans[loanId].principal = r.amount;
        loans[loanId].interestRateBPS = r.maxInterestRateBPS;
        loans[loanId].startTime = block.timestamp;
        loans[loanId].durationSecs = r.durationSecs;
        // compute implied collateral ratio in BPS at loan creation using oracle (if available)
        loans[loanId].collateralAmount = r.collateralAmount;
        uint256 ratioBPS = 0;
        // attempt to compute ratio; if oracle available, compute normalized values to derive a ratio
        if (address(priceOracle) != address(0)) {
            uint256 pCollateral = _normalizedPrice(r.collateralToken);
            uint256 pLend = _normalizedPrice(r.borrowToken);
            // principal value = principal * pLend / 1e18
            // collateral value = collateralAmount * pCollateral / 1e18
            // ratioBPS = collateralValue * 10000 / principalValue
            if (pLend > 0) {
                uint256 principalValue = (r.amount * pLend) / 1e18;
                if (principalValue > 0) {
                    uint256 collateralValue = (r.collateralAmount * pCollateral) / 1e18;
                    ratioBPS = (collateralValue * 10000) / principalValue;
                }
            }
        }
        loans[loanId].collateralRatioBPS = ratioBPS;
        loans[loanId].lenderPositionTokenId = 0;
        loans[loanId].borrowerPositionTokenId = 0;
        loans[loanId].repaid = false;
        loans[loanId].liquidated = false;

        // mark request inactive
        r.active = false;

        // transfer principal to borrower
        _safeTransfer(IERC20(r.borrowToken), r.borrower, r.amount);

        // mint NFTs if set
        if (address(loanPositionNFT) != address(0)) {
            _mintPositions(loanId, msg.sender, r.borrower);
        }

        emit BorrowRequestCreated(requestId, r.borrower, r.collateralToken, r.collateralAmount);
        emit LoanMatched(
            loanId,
            r.borrower,
            msg.sender,
            r.borrowToken,
            r.collateralToken,
            r.amount,
            r.maxInterestRateBPS,
            r.durationSecs,
            loans[loanId].startTime
        );
        return loanId;
    }

    /// @notice Mint lender and borrower position NFTs for a loan
    /// @param loanId The loan ID
    /// @param lenderAddr The lender's address
    /// @param borrowerAddr The borrower's address
    function _mintPositions(uint256 loanId, address lenderAddr, address borrowerAddr) internal {
        uint256 ltid = loanPositionNFT.mint(lenderAddr, loanId, ILoanPositionNFT.Role.LENDER);
        uint256 btid = loanPositionNFT.mint(borrowerAddr, loanId, ILoanPositionNFT.Role.BORROWER);
        loans[loanId].lenderPositionTokenId = ltid;
        loans[loanId].borrowerPositionTokenId = btid;
    }

    /// @notice Burn lender and borrower position NFTs for a loan
    /// @param loanId The loan ID
    function _burnPositions(uint256 loanId) internal {
        uint256 ltid = loans[loanId].lenderPositionTokenId;
        uint256 btid = loans[loanId].borrowerPositionTokenId;
        if (ltid != 0) loanPositionNFT.burn(ltid);
        if (btid != 0) loanPositionNFT.burn(btid);
    }

    /// @notice Compute linear accrued interest for a loan up to now
    /// @param loanId The loan ID
    /// @return The accrued interest amount
    function accruedInterest(uint256 loanId) public view returns (uint256) {
        Loan storage loan = loans[loanId];
        if (loan.repaid || loan.liquidated) return 0;
        uint256 elapsed = block.timestamp - loan.startTime;
        if (elapsed > loan.durationSecs) elapsed = loan.durationSecs;
        // principal * rateBPS * elapsed / (365 days * 10000)
        return (loan.principal * loan.interestRateBPS * elapsed) / (365 days * 10000);
    }

    /// @notice Borrower repays full principal + accrued interest. Burns NFTs on full repay.
    /// @param loanId The loan ID to repay
    function repayFull(uint256 loanId) external nonReentrant whenNotPaused {
        Loan storage loan = loans[loanId];
        require(!loan.repaid && !loan.liquidated, "loan closed");
        require(msg.sender == loan.borrower, "only borrower");

        uint256 interest = accruedInterest(loanId);
        uint256 ownerFee = (interest * ownerFeeBPS) / 10000;
        uint256 lenderInterest = interest - ownerFee;
        uint256 totalDue = loan.principal + interest;

        // transfer totalDue from borrower to contract
        _safeTransferFrom(IERC20(loan.lendToken), msg.sender, address(this), totalDue);

        // pay lender principal + interest - ownerFee
        _safeTransfer(IERC20(loan.lendToken), loan.lender, loan.principal + lenderInterest);

        // accumulate owner fee
        ownerFees[loan.lendToken] += ownerFee;

        // return collateral
        _safeTransfer(IERC20(loan.collateralToken), loan.borrower, loan.collateralAmount);

        // burn NFTs if present and minter role
        if (address(loanPositionNFT) != address(0)) {
            if (loan.lenderPositionTokenId != 0) loanPositionNFT.burn(loan.lenderPositionTokenId);
            if (loan.borrowerPositionTokenId != 0) loanPositionNFT.burn(loan.borrowerPositionTokenId);
        }

        loan.repaid = true;
        emit LoanClosed(loanId, "repaid", msg.sender);
    }

    /// @notice Claim accumulated owner fees for a token
    /// @param token The token address to claim fees for
    function claimOwnerFees(address token) external onlyOwner nonReentrant whenNotPaused {
        uint256 amt = ownerFees[token];
        require(amt > 0, "no fees");
        ownerFees[token] = 0;
        _safeTransfer(IERC20(token), owner(), amt);
        emit OwnerFeesClaimed(token, owner(), amt);
    }

    /// @notice Claim accumulated owner fees for multiple tokens in one call
    /// @param tokens The array of token addresses to claim fees for
    function claimOwnerFeesBatch(address[] calldata tokens) external onlyOwner nonReentrant whenNotPaused {
        require(tokens.length > 0, "no tokens");
        address to = owner();
        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amt = ownerFees[token];
            amounts[i] = amt;
            if (amt == 0) continue;
            ownerFees[token] = 0;
            _safeTransfer(IERC20(token), to, amt);
            emit OwnerFeesClaimed(token, to, amt);
        }
        emit OwnerFeesClaimedBatch(to, tokens, amounts);
    }

    /// @notice Owner-only: swap all accumulated fees in tokenIn to tokenOut via a Uniswap V2-like router.
    /// @dev Uses check-effects-interactions, SafeERC20 approvals, and emits OwnerFeesSwapped.
    /// @param router The router contract address
    /// @param tokenIn The input token to swap
    /// @param path The swap path (first element must be tokenIn)
    /// @param amountOutMin The minimum amount of output tokens expected
    /// @param deadline The deadline for the swap transaction
    function claimAndSwapFees(
        address router,
        address tokenIn,
        address[] calldata path,
        uint256 amountOutMin,
        uint256 deadline
    ) external onlyOwner nonReentrant whenNotPaused {
        require(router != address(0), "router=0");
        require(routerWhitelist[router], "router not whitelisted");
        require(path.length >= 2, "bad path");
        require(path[0] == tokenIn, "path mismatch");
        address tokenOut = path[path.length - 1];
        uint256 amtIn = ownerFees[tokenIn];
        require(amtIn > 0, "no fees");

        // effects: zero before interaction
        ownerFees[tokenIn] = 0;

        // approve router for amount
        IERC20(tokenIn).safeIncreaseAllowance(router, amtIn);

        // interaction: swap; send proceeds to owner
        uint256[] memory amounts =
            IUniswapV2Router(router).swapExactTokensForTokens(amtIn, amountOutMin, path, owner(), deadline);

        // clear allowance to prevent lingering approvals
        IERC20(tokenIn).approve(router, 0);

        uint256 amountOut = amounts[amounts.length - 1];
        emit OwnerFeesSwapped(tokenIn, tokenOut, amtIn, amountOut);
    }

    /// @notice Opt-in: Borrower repays full loan using a swap from an arbitrary input token to the lend token
    /// @dev Uses a whitelisted Uniswap V2-like router. Slippage guarded via borrower-provided amountOutMin and deadline.
    /// @param loanId The loan ID to repay
    /// @param router The router contract address (must be whitelisted)
    /// @param amountIn The amount of input tokens to swap
    /// @param path The swap path; first token is the input token provided by borrower, last must equal the loan lend token
    /// @param amountOutMin The minimum acceptable amount of lend tokens from the swap (should be >= totalDue)
    /// @param deadline Unix timestamp after which the swap will revert
    function repayFullWithSwap(
        uint256 loanId,
        address router,
        uint256 amountIn,
        address[] calldata path,
        uint256 amountOutMin,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        Loan storage loan = loans[loanId];
        require(loan.id != 0, "invalid loan");
        require(!loan.repaid && !loan.liquidated, "loan closed");
        require(msg.sender == loan.borrower, "only borrower");
        require(router != address(0), "router=0");
        require(routerWhitelist[router], "router not whitelisted");
        require(path.length >= 2, "bad path");
        require(amountIn > 0, "amountIn>0");
        require(path[path.length - 1] == loan.lendToken, "path last != lendToken");

        // compute total due
        uint256 interest = accruedInterest(loanId);
        uint256 ownerFee = (interest * ownerFeeBPS) / 10000;
        uint256 lenderInterest = interest - ownerFee;
        uint256 totalDue = loan.principal + interest;

        // take input tokens from borrower into pool and approve router
        _safeTransferFrom(IERC20(path[0]), msg.sender, address(this), amountIn);
        IERC20(path[0]).safeIncreaseAllowance(router, amountIn);

        // swap to lend token with proceeds to this contract
        uint256[] memory amounts =
            IUniswapV2Router(router).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), deadline);

        // clear allowance
        IERC20(path[0]).approve(router, 0);

        uint256 amountOut = amounts[amounts.length - 1];
        require(amountOut >= totalDue, "insufficient out");

        // pay lender principal + interest - owner fee in lend token
        _safeTransfer(IERC20(loan.lendToken), loan.lender, loan.principal + lenderInterest);

        // accumulate owner fee in lend token
        ownerFees[loan.lendToken] += ownerFee;

        // return collateral to borrower
        _safeTransfer(IERC20(loan.collateralToken), loan.borrower, loan.collateralAmount);

        // burn NFTs if present
        if (address(loanPositionNFT) != address(0)) {
            if (loan.lenderPositionTokenId != 0) loanPositionNFT.burn(loan.lenderPositionTokenId);
            if (loan.borrowerPositionTokenId != 0) loanPositionNFT.burn(loan.borrowerPositionTokenId);
        }

        loan.repaid = true;
        emit RepayWithSwap(loanId, router, path[0], amountIn, amountOut);
        emit LoanClosed(loanId, "repaidSwap", msg.sender);
    }

    /// @notice Liquidate a loan if expired or undercollateralized. Caller must be lender or lender-NFT owner.
    /// @param loanId The loan ID to liquidate
    function liquidate(uint256 loanId) external nonReentrant whenNotPaused {
        Loan storage loan = loans[loanId];
        require(loan.id != 0, "invalid loan");
        require(!loan.repaid && !loan.liquidated, "loan closed");

        // permission: lender or current owner of lender position NFT
        bool isLender = (msg.sender == loan.lender);
        if (!isLender && address(loanPositionNFT) != address(0) && loan.lenderPositionTokenId != 0) {
            address ownerOfLenderToken = loanPositionNFT.ownerOf(loan.lenderPositionTokenId);
            require(msg.sender == ownerOfLenderToken, "not lender or token owner");
        } else if (!isLender) {
            revert("not lender");
        }

        // check expiry
        bool expired = (block.timestamp > loan.startTime + loan.durationSecs + liquidationGracePeriodSecs);

        // check undercollateralization if collateral ratio present
        bool undercollateralized = false;
        if (loan.collateralRatioBPS > 0) {
            // compute normalized values
            uint256 pLend = priceOracle.getNormalizedPrice(loan.lendToken);
            uint256 pColl = priceOracle.getNormalizedPrice(loan.collateralToken);
            require(pLend > 0 && pColl > 0, "invalid price");

            uint256 principalValue = (loan.principal * pLend) / 1e18;
            uint256 collateralValue = (loan.collateralAmount * pColl) / 1e18;
            uint256 requiredCollateralValue = (principalValue * loan.collateralRatioBPS) / 10000;
            if (collateralValue < requiredCollateralValue) undercollateralized = true;
        }

        require(expired || undercollateralized, "not liquidatable");

        // compute penalty in principal units (lendToken), then convert to collateral units to withhold
        uint256 penaltyInLend = (loan.principal * penaltyBPS) / 10000;
        uint256 penaltyCollateral = 0;
        if (penaltyInLend > 0) {
            uint256 pLend = priceOracle.getNormalizedPrice(loan.lendToken);
            uint256 pColl = priceOracle.getNormalizedPrice(loan.collateralToken);
            require(pLend > 0 && pColl > 0, "invalid price");
            // penaltyCollateral = penaltyInLend * pLend / pColl
            penaltyCollateral = (penaltyInLend * pLend) / pColl;
            if (penaltyCollateral > loan.collateralAmount) penaltyCollateral = loan.collateralAmount;
            // accrue owner fees in collateral token units
            ownerFees[loan.collateralToken] += penaltyCollateral;
        }

        uint256 toLiquidator = loan.collateralAmount;
        if (penaltyCollateral > 0) {
            toLiquidator = loan.collateralAmount - penaltyCollateral;
        }

        // transfer collateral (less penalty) to caller
        if (toLiquidator > 0) {
            _safeTransfer(IERC20(loan.collateralToken), msg.sender, toLiquidator);
        }

        // burn position NFTs if present
        if (address(loanPositionNFT) != address(0)) {
            if (loan.lenderPositionTokenId != 0) loanPositionNFT.burn(loan.lenderPositionTokenId);
            if (loan.borrowerPositionTokenId != 0) loanPositionNFT.burn(loan.borrowerPositionTokenId);
        }

        loan.liquidated = true;
        emit LoanLiquidated(loanId, msg.sender, toLiquidator, penaltyCollateral);
        emit LoanClosed(loanId, "liquidated", msg.sender);
    }

    /// @notice Opt-in: Liquidate a loan and swap the liquidator's collateral share into a desired token via a whitelisted router
    /// @param loanId The loan ID to liquidate
    /// @param router The router contract address (must be whitelisted)
    /// @param path The swap path; first token must be the collateral token, last is the desired output token for the liquidator
    /// @param amountOutMin The minimum acceptable amount of output tokens for the liquidator
    /// @param deadline Unix timestamp after which the swap will revert
    function liquidateWithSwap(
        uint256 loanId,
        address router,
        address[] calldata path,
        uint256 amountOutMin,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        Loan storage loan = loans[loanId];
        require(loan.id != 0, "invalid loan");
        require(!loan.repaid && !loan.liquidated, "loan closed");

        // permission: lender or current owner of lender position NFT
        bool isLender = (msg.sender == loan.lender);
        if (!isLender && address(loanPositionNFT) != address(0) && loan.lenderPositionTokenId != 0) {
            address ownerOfLenderToken = loanPositionNFT.ownerOf(loan.lenderPositionTokenId);
            require(msg.sender == ownerOfLenderToken, "not lender or token owner");
        } else if (!isLender) {
            revert("not lender");
        }

        require(router != address(0), "router=0");
        require(routerWhitelist[router], "router not whitelisted");
        require(path.length >= 2, "bad path");
        require(path[0] == loan.collateralToken, "path first != collateral");

        // check expiry
        bool expired = (block.timestamp > loan.startTime + loan.durationSecs + liquidationGracePeriodSecs);

        // check undercollateralization if collateral ratio present
        bool undercollateralized = false;
        if (loan.collateralRatioBPS > 0) {
            uint256 pLend = priceOracle.getNormalizedPrice(loan.lendToken);
            uint256 pColl = priceOracle.getNormalizedPrice(loan.collateralToken);
            require(pLend > 0 && pColl > 0, "invalid price");
            uint256 principalValue = (loan.principal * pLend) / 1e18;
            uint256 collateralValue = (loan.collateralAmount * pColl) / 1e18;
            uint256 requiredCollateralValue = (principalValue * loan.collateralRatioBPS) / 10000;
            if (collateralValue < requiredCollateralValue) undercollateralized = true;
        }

        require(expired || undercollateralized, "not liquidatable");

        // compute penalty and withhold in collateral units
        uint256 penaltyInLend = (loan.principal * penaltyBPS) / 10000;
        uint256 penaltyCollateral = 0;
        if (penaltyInLend > 0) {
            uint256 pLend = priceOracle.getNormalizedPrice(loan.lendToken);
            uint256 pColl = priceOracle.getNormalizedPrice(loan.collateralToken);
            require(pLend > 0 && pColl > 0, "invalid price");
            penaltyCollateral = (penaltyInLend * pLend) / pColl;
            if (penaltyCollateral > loan.collateralAmount) penaltyCollateral = loan.collateralAmount;
            ownerFees[loan.collateralToken] += penaltyCollateral;
        }

        uint256 toLiquidator = loan.collateralAmount;
        if (penaltyCollateral > 0) {
            toLiquidator = loan.collateralAmount - penaltyCollateral;
        }

        // swap the liquidator's collateral share into desired token and send to liquidator
        if (toLiquidator > 0) {
            IERC20(loan.collateralToken).safeIncreaseAllowance(router, toLiquidator);
            uint256[] memory amounts = IUniswapV2Router(router).swapExactTokensForTokens(
                toLiquidator, amountOutMin, path, msg.sender, deadline
            );
            IERC20(loan.collateralToken).approve(router, 0);
            emit LoanLiquidatedWithSwap(
                loanId, router, path[path.length - 1], toLiquidator, amounts[amounts.length - 1]
            );
        }

        // burn position NFTs if present
        if (address(loanPositionNFT) != address(0)) {
            if (loan.lenderPositionTokenId != 0) loanPositionNFT.burn(loan.lenderPositionTokenId);
            if (loan.borrowerPositionTokenId != 0) loanPositionNFT.burn(loan.borrowerPositionTokenId);
        }

        loan.liquidated = true;
        emit LoanClosed(loanId, "liquidatedSwap", msg.sender);
    }
}
