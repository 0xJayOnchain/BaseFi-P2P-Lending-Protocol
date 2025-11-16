// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./BaseP2P.sol";
import "./PriceOracle.sol";
import "./interfaces/ILoanPositionNFT.sol";

contract LendingPool is BaseP2P, ReentrancyGuard {
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

    event LendingOfferCreated(uint256 indexed id, address indexed lender, address lendToken, uint256 amount);
    event LendingOfferCancelled(uint256 indexed id);
    event BorrowRequestCreated(
        uint256 indexed id, address indexed borrower, address collateralToken, uint256 collateralAmount
    );
    event BorrowRequestCancelled(uint256 indexed id);

    constructor(address _priceOracle) BaseP2P() {
        priceOracle = PriceOracle(_priceOracle);
    }

    function setLoanPositionNFT(address _nft) external onlyOwner {
        loanPositionNFT = ILoanPositionNFT(_nft);
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
    ) external virtual nonReentrant returns (uint256) {
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

    function cancelLendingOffer(uint256 offerId) external virtual nonReentrant {
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
    ) external virtual nonReentrant returns (uint256) {
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

    function cancelBorrowRequest(uint256 requestId) external virtual nonReentrant {
        Request storage r = requests[requestId];
        require(r.active, "not active");
        require(r.borrower == msg.sender, "only borrower");

        r.active = false;
        _safeTransfer(IERC20(r.collateralToken), msg.sender, r.collateralAmount);
        emit BorrowRequestCancelled(requestId);
    }

    /// @notice Borrower accepts an existing lender offer. Borrower must provide collateral now.
    function acceptOfferByBorrower(uint256 offerId, uint256 collateralAmount) external nonReentrant returns (uint256) {
        Offer storage o = offers[offerId];
        require(o.active, "offer not active");

        // transfer collateral from borrower
        _safeTransferFrom(IERC20(o.collateralToken), msg.sender, address(this), collateralAmount);

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
    function acceptRequestByLender(uint256 requestId) external nonReentrant returns (uint256) {
        Request storage r = requests[requestId];
        require(r.active, "request not active");

        // transfer principal from lender to contract
        _safeTransferFrom(IERC20(r.borrowToken), msg.sender, address(this), r.amount);

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
        loans[loanId].collateralAmount = r.collateralAmount;
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
    function repayFull(uint256 loanId) external nonReentrant {
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
    function claimOwnerFees(address token) external onlyOwner nonReentrant {
        uint256 amt = ownerFees[token];
        require(amt > 0, "no fees");
        ownerFees[token] = 0;
        _safeTransfer(IERC20(token), owner(), amt);
        emit OwnerFeesClaimed(token, owner(), amt);
    }
}
