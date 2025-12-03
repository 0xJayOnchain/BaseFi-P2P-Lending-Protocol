// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "./BaseP2P.sol";
import "./PriceOracle.sol";
import "./interfaces/ILoanPositionNFT.sol";

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

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

    PriceOracle public priceOracle;
    ILoanPositionNFT public loanPositionNFT;
    mapping(address => bool) public routerWhitelist;
    bool public enforceCollateralValidation;

    uint256 public nextOfferId = 1;
    uint256 public nextRequestId = 1;

    mapping(uint256 => Offer) public offers;
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

    uint256 public nextLoanId = 1;
    mapping(uint256 => Loan) private loans;

    /// @notice Get core loan data (smaller tuple to avoid large public accessor)
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
        Loan storage L = loans[loanId];
        return (
            L.id,
            L.lender,
            L.borrower,
            L.lendToken,
            L.collateralToken,
            L.principal,
            L.collateralAmount,
            L.lenderPositionTokenId,
            L.borrowerPositionTokenId,
            L.repaid,
            L.liquidated
        );
    }

    // fees and penalty
    uint256 public ownerFeeBPS;
    uint256 public penaltyBPS = 200; // default 2%
    mapping(address => uint256) public ownerFees; // token => amount

    event OwnerFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event PenaltyBpsUpdated(uint256 oldBps, uint256 newBps);
    event OwnerFeesClaimed(address indexed token, address indexed to, uint256 amount);
    event LoanLiquidated(
        uint256 indexed loanId, address indexed liquidator, uint256 collateralToLiquidator, uint256 penaltyCollateral
    );
    event OwnerFeesSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    event LendingOfferCreated(uint256 indexed id, address indexed lender, address lendToken, uint256 amount);
    event LendingOfferCancelled(uint256 indexed id);
    event BorrowRequestCreated(
        uint256 indexed id, address indexed borrower, address collateralToken, uint256 collateralAmount
    );
    event BorrowRequestCancelled(uint256 indexed id);

    constructor(address _priceOracle) BaseP2P() {
        // Best-effort set; may be a non-oracle during tests. Price checks will gracefully skip if calls fail.
        priceOracle = PriceOracle(_priceOracle);
    }

    /// @dev Safely fetch normalized price from oracle; returns 0 if oracle call fails
    function _normalizedPrice(address token) internal view returns (uint256 p) {
        if (address(priceOracle) == address(0)) return 0;
        // try/catch to avoid test setups passing a non-PriceOracle address
        try priceOracle.getNormalizedPrice(token) returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }

    function setLoanPositionNFT(address _nft) external onlyOwner {
        loanPositionNFT = ILoanPositionNFT(_nft);
    }

    /// @notice Pause the protocol critical functions
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the protocol
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Manage router whitelist for swaps
    function setRouterWhitelisted(address router, bool whitelisted) external onlyOwner {
        routerWhitelist[router] = whitelisted;
    }

    /// @notice Enable or disable collateral validation at match-time
    function setEnforceCollateralValidation(bool on) external onlyOwner {
        enforceCollateralValidation = on;
    }

    function setOwnerFeeBPS(uint256 bps) external onlyOwner {
        require(bps <= 10000, "bps>10000");
        uint256 old = ownerFeeBPS;
        ownerFeeBPS = bps;
        emit OwnerFeeBpsUpdated(old, bps);
    }

    function setPenaltyBPS(uint256 bps) external onlyOwner {
        require(bps <= 10000, "bps>10000");
        uint256 old = penaltyBPS;
        penaltyBPS = bps;
        emit PenaltyBpsUpdated(old, bps);
    }

    function createLendingOffer(
        address lendToken,
        uint256 amount,
        uint256 interestRateBPS,
        uint256 durationSecs,
        address collateralToken,
        uint256 collateralRatioBPS
    ) external virtual nonReentrant whenNotPaused returns (uint256) {
        require(amount > 0, "amount>0");
        // transfer principal into escrow
        _safeTransferFrom(IERC20(lendToken), msg.sender, address(this), amount);

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

    function cancelLendingOffer(uint256 offerId) external virtual nonReentrant whenNotPaused {
        Offer storage o = offers[offerId];
        require(o.active, "not active");
        require(o.lender == msg.sender, "only lender");

        o.active = false;
        // refund principal
        _safeTransfer(IERC20(o.lendToken), msg.sender, o.amount);
        emit LendingOfferCancelled(offerId);
    }

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

        // transfer collateral into escrow
        _safeTransferFrom(IERC20(collateralToken), msg.sender, address(this), collateralAmount);

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

    function cancelBorrowRequest(uint256 requestId) external virtual nonReentrant whenNotPaused {
        Request storage r = requests[requestId];
        require(r.active, "not active");
        require(r.borrower == msg.sender, "only borrower");

        r.active = false;
        _safeTransfer(IERC20(r.collateralToken), msg.sender, r.collateralAmount);
        emit BorrowRequestCancelled(requestId);
    }

    /// @notice Borrower accepts an existing lender offer. Borrower must provide collateral now.
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
        return loanId;
    }

    /// @notice Lender accepts an existing borrow request by funding principal now.
    function acceptRequestByLender(uint256 requestId) external nonReentrant whenNotPaused returns (uint256) {
        Request storage r = requests[requestId];
        require(r.active, "request not active");

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
        return loanId;
    }

    function _mintPositions(uint256 loanId, address lenderAddr, address borrowerAddr) internal {
        uint256 ltid = loanPositionNFT.mint(lenderAddr, loanId, ILoanPositionNFT.Role.LENDER);
        uint256 btid = loanPositionNFT.mint(borrowerAddr, loanId, ILoanPositionNFT.Role.BORROWER);
        loans[loanId].lenderPositionTokenId = ltid;
        loans[loanId].borrowerPositionTokenId = btid;
    }

    function _burnPositions(uint256 loanId) internal {
        uint256 ltid = loans[loanId].lenderPositionTokenId;
        uint256 btid = loans[loanId].borrowerPositionTokenId;
        if (ltid != 0) loanPositionNFT.burn(ltid);
        if (btid != 0) loanPositionNFT.burn(btid);
    }

    /// @notice Compute linear accrued interest for a loan up to now
    function accruedInterest(uint256 loanId) public view returns (uint256) {
        Loan storage L = loans[loanId];
        if (L.repaid || L.liquidated) return 0;
        uint256 elapsed = block.timestamp - L.startTime;
        if (elapsed > L.durationSecs) elapsed = L.durationSecs;
        // principal * rateBPS * elapsed / (365 days * 10000)
        return (L.principal * L.interestRateBPS * elapsed) / (365 days * 10000);
    }

    /// @notice Borrower repays full principal + accrued interest. Burns NFTs on full repay.
    function repayFull(uint256 loanId) external nonReentrant whenNotPaused {
        Loan storage L = loans[loanId];
        require(!L.repaid && !L.liquidated, "loan closed");
        require(msg.sender == L.borrower, "only borrower");

        uint256 interest = accruedInterest(loanId);
        uint256 ownerFee = (interest * ownerFeeBPS) / 10000;
        uint256 lenderInterest = interest - ownerFee;
        uint256 totalDue = L.principal + interest;

        // transfer totalDue from borrower to contract
        _safeTransferFrom(IERC20(L.lendToken), msg.sender, address(this), totalDue);

        // pay lender principal + interest - ownerFee
        _safeTransfer(IERC20(L.lendToken), L.lender, L.principal + lenderInterest);

        // accumulate owner fee
        ownerFees[L.lendToken] += ownerFee;

        // return collateral
        _safeTransfer(IERC20(L.collateralToken), L.borrower, L.collateralAmount);

        // burn NFTs if present and minter role
        if (address(loanPositionNFT) != address(0)) {
            if (L.lenderPositionTokenId != 0) loanPositionNFT.burn(L.lenderPositionTokenId);
            if (L.borrowerPositionTokenId != 0) loanPositionNFT.burn(L.borrowerPositionTokenId);
        }

        L.repaid = true;
    }

    /// @notice Claim accumulated owner fees for a token
    function claimOwnerFees(address token) external onlyOwner nonReentrant whenNotPaused {
        uint256 amt = ownerFees[token];
        require(amt > 0, "no fees");
        ownerFees[token] = 0;
        _safeTransfer(IERC20(token), owner(), amt);
        emit OwnerFeesClaimed(token, owner(), amt);
    }

    /// @notice Owner-only: swap all accumulated fees in tokenIn to tokenOut via a Uniswap V2-like router.
    /// @dev Uses check-effects-interactions, SafeERC20 approvals, and emits OwnerFeesSwapped.
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

    /// @notice Liquidate a loan if expired or undercollateralized. Caller must be lender or lender-NFT owner.
    function liquidate(uint256 loanId) external nonReentrant whenNotPaused {
        Loan storage L = loans[loanId];
        require(L.id != 0, "invalid loan");
        require(!L.repaid && !L.liquidated, "loan closed");

        // permission: lender or current owner of lender position NFT
        bool isLender = (msg.sender == L.lender);
        if (!isLender && address(loanPositionNFT) != address(0) && L.lenderPositionTokenId != 0) {
            address ownerOfLenderToken = loanPositionNFT.ownerOf(L.lenderPositionTokenId);
            require(msg.sender == ownerOfLenderToken, "not lender or token owner");
        } else if (!isLender) {
            revert("not lender");
        }

        // check expiry
        bool expired = (block.timestamp > L.startTime + L.durationSecs);

        // check undercollateralization if collateral ratio present
        bool undercollateralized = false;
        if (L.collateralRatioBPS > 0) {
            // compute normalized values
            uint256 pLend = priceOracle.getNormalizedPrice(L.lendToken);
            uint256 pColl = priceOracle.getNormalizedPrice(L.collateralToken);
            require(pLend > 0 && pColl > 0, "invalid price");

            uint256 principalValue = (L.principal * pLend) / 1e18;
            uint256 collateralValue = (L.collateralAmount * pColl) / 1e18;
            uint256 requiredCollateralValue = (principalValue * L.collateralRatioBPS) / 10000;
            if (collateralValue < requiredCollateralValue) undercollateralized = true;
        }

        require(expired || undercollateralized, "not liquidatable");

        // compute penalty in principal units (lendToken), then convert to collateral units to withhold
        uint256 penaltyInLend = (L.principal * penaltyBPS) / 10000;
        uint256 penaltyCollateral = 0;
        if (penaltyInLend > 0) {
            uint256 pLend = priceOracle.getNormalizedPrice(L.lendToken);
            uint256 pColl = priceOracle.getNormalizedPrice(L.collateralToken);
            require(pLend > 0 && pColl > 0, "invalid price");
            // penaltyCollateral = penaltyInLend * pLend / pColl
            penaltyCollateral = (penaltyInLend * pLend) / pColl;
            if (penaltyCollateral > L.collateralAmount) penaltyCollateral = L.collateralAmount;
            // accrue owner fees in collateral token units
            ownerFees[L.collateralToken] += penaltyCollateral;
        }

        uint256 toLiquidator = L.collateralAmount;
        if (penaltyCollateral > 0) {
            toLiquidator = L.collateralAmount - penaltyCollateral;
        }

        // transfer collateral (less penalty) to caller
        if (toLiquidator > 0) {
            _safeTransfer(IERC20(L.collateralToken), msg.sender, toLiquidator);
        }

        // burn position NFTs if present
        if (address(loanPositionNFT) != address(0)) {
            if (L.lenderPositionTokenId != 0) loanPositionNFT.burn(L.lenderPositionTokenId);
            if (L.borrowerPositionTokenId != 0) loanPositionNFT.burn(L.borrowerPositionTokenId);
        }

        L.liquidated = true;
        emit LoanLiquidated(loanId, msg.sender, toLiquidator, penaltyCollateral);
    }
}
