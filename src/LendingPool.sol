// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./BaseP2P.sol";
import "./PriceOracle.sol";

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

    uint256 public nextOfferId = 1;
    uint256 public nextRequestId = 1;

    mapping(uint256 => Offer) public offers;
    mapping(uint256 => Request) public requests;

    event LendingOfferCreated(uint256 indexed id, address indexed lender, address lendToken, uint256 amount);
    event LendingOfferCancelled(uint256 indexed id);
    event BorrowRequestCreated(uint256 indexed id, address indexed borrower, address collateralToken, uint256 collateralAmount);
    event BorrowRequestCancelled(uint256 indexed id);

    constructor(address _priceOracle) BaseP2P() {
        priceOracle = PriceOracle(_priceOracle);
    }

    function createLendingOffer(
        address lendToken,
        uint256 amount,
        uint256 interestRateBPS,
        uint256 durationSecs,
        address collateralToken,
        uint256 collateralRatioBPS
    ) external nonReentrant returns (uint256) {
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

    function cancelLendingOffer(uint256 offerId) external nonReentrant {
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
    ) external nonReentrant returns (uint256) {
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

    function cancelBorrowRequest(uint256 requestId) external nonReentrant {
        Request storage r = requests[requestId];
        require(r.active, "not active");
        require(r.borrower == msg.sender, "only borrower");

        r.active = false;
        _safeTransfer(IERC20(r.collateralToken), msg.sender, r.collateralAmount);
        emit BorrowRequestCancelled(requestId);
    }
}
