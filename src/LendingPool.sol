// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract LendingPool is ReentrancyGuard, Ownable {
    struct LendingPosition {
        uint256 amount;
        uint256 timestamp;
        uint256 interestRate;
    }

    struct BorrowPosition {
        uint256 amount;
        uint256 collateralAmount;
        uint256 timestamp;
        uint256 interestRate;
        address collateralToken;
    }

    mapping(address => mapping(address => LendingPosition)) public lendingPositions;
    mapping(address => mapping(address => BorrowPosition)) public borrowPositions;
    mapping(address => bool) public supportedTokens;
    uint256 public platformFee = 30;
    uint256 public constant OWNER_FEE_BPS = 10;
    uint256 public minCollateralRatio = 150;
    mapping(address => uint256) public ownerFees;

    event Deposit(address indexed token, address indexed user, uint256 amount, uint256 ownerFee);
    event Borrow(
        address indexed token,
        address indexed user,
        uint256 amount,
        address collateralToken,
        uint256 collateralAmount,
        uint256 ownerFee
    );
    event Repay(address indexed token, address indexed user, uint256 amount, uint256 ownerFee);
    event Withdraw(address indexed token, address indexed user, uint256 amount);
    event Liquidate(
        address indexed token, address indexed borrower, address liquidator, uint256 amount, uint256 ownerFee
    );
    event OwnerFeeClaimed(address indexed token, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        supportedTokens[token] = true;
    }

    function calculateOwnerFee(uint256 amount) public pure returns (uint256) {
        return (amount * OWNER_FEE_BPS) / 10000;
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");

        uint256 ownerFee = calculateOwnerFee(amount);
        uint256 depositAmount = amount - ownerFee;

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");

        ownerFees[token] += ownerFee;

        LendingPosition storage position = lendingPositions[token][msg.sender];
        position.amount += depositAmount;
        position.timestamp = block.timestamp;
        position.interestRate = calculateLendingRate(token);

        emit Deposit(token, msg.sender, depositAmount, ownerFee);
    }

    function borrow(address borrowToken, uint256 borrowAmount, address collateralToken, uint256 collateralAmount)
        external
        nonReentrant
    {
        require(supportedTokens[borrowToken], "Borrow token not supported");
        require(supportedTokens[collateralToken], "Collateral token not supported");
        require(borrowAmount > 0, "Borrow amount must be greater than 0");
        require(collateralAmount > 0, "Collateral amount must be greater than 0");

        uint256 ownerFee = calculateOwnerFee(borrowAmount);
        uint256 actualBorrowAmount = borrowAmount - ownerFee;

        require(
            isCollateralSufficient(borrowToken, actualBorrowAmount, collateralToken, collateralAmount),
            "Insufficient collateral"
        );

        bool collateralSuccess = IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        require(collateralSuccess, "Collateral transfer failed");

        bool borrowSuccess = IERC20(borrowToken).transfer(msg.sender, actualBorrowAmount);
        require(borrowSuccess, "Borrow token transfer failed");

        ownerFees[borrowToken] += ownerFee;

        BorrowPosition storage position = borrowPositions[borrowToken][msg.sender];
        position.amount = actualBorrowAmount;
        position.collateralAmount = collateralAmount;
        position.timestamp = block.timestamp;
        position.interestRate = calculateBorrowRate(borrowToken);
        position.collateralToken = collateralToken;

        emit Borrow(borrowToken, msg.sender, actualBorrowAmount, collateralToken, collateralAmount, ownerFee);
    }

    function repay(address token, uint256 amount) external nonReentrant {
        BorrowPosition storage position = borrowPositions[token][msg.sender];
        require(position.amount > 0, "No active borrow position");
        require(amount > 0, "Amount must be greater than 0");

        uint256 ownerFee = calculateOwnerFee(amount);
        uint256 repaymentAmount = amount - ownerFee;

        require(repaymentAmount <= position.amount, "Repayment exceeds borrow amount");

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Repayment transfer failed");

        ownerFees[token] += ownerFee;
        position.amount -= repaymentAmount;

        emit Repay(token, msg.sender, repaymentAmount, ownerFee);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        LendingPosition storage position = lendingPositions[token][msg.sender];
        require(position.amount >= amount, "Insufficient balance to withdraw");
        require(amount > 0, "Amount must be greater than 0");

        position.amount -= amount;

        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "Withdraw transfer failed");

        emit Withdraw(token, msg.sender, amount);
    }

    function liquidate(address borrowToken, address borrower) external nonReentrant {
        BorrowPosition storage position = borrowPositions[borrowToken][borrower];
        require(position.amount > 0, "No active borrow position");

        bool isUnderCollateralized =
            !isCollateralSufficient(borrowToken, position.amount, position.collateralToken, position.collateralAmount);
        require(isUnderCollateralized, "Position is sufficiently collateralized");

        uint256 ownerFee = calculateOwnerFee(position.amount);
        uint256 liquidationAmount = position.amount - ownerFee;

        ownerFees[borrowToken] += ownerFee;

        bool success = IERC20(position.collateralToken).transfer(msg.sender, position.collateralAmount);
        require(success, "Collateral transfer failed");

        delete borrowPositions[borrowToken][borrower];

        emit Liquidate(borrowToken, borrower, msg.sender, liquidationAmount, ownerFee);
    }

    function calculateInterest(address token, address user) public view returns (uint256) {
        LendingPosition storage position = lendingPositions[token][user];
        if (position.amount == 0) return 0;

        uint256 duration = block.timestamp - position.timestamp;
        return (position.amount * position.interestRate * duration) / (365 days * 100);
    }

    function updatePrices() external onlyOwner {
        // Implement price oracle integration
    }

    function calculateLendingRate(address token) public view returns (uint256) {
        return 5;
    }

    function calculateBorrowRate(address token) public view returns (uint256) {
        return 7;
    }

    function isCollateralSufficient(
        address borrowToken,
        uint256 borrowAmount,
        address collateralToken,
        uint256 collateralAmount
    ) public view returns (bool) {
        return true;
    }
}
