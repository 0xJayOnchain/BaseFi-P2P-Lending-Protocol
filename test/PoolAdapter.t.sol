// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";

contract PoolAdapterMock {
    LendingPool public pool;
    address public owner;

    constructor(LendingPool _pool) {
        pool = _pool;
        owner = msg.sender;
    }

    // called by test to create an offer from this contract
    function createOffer(address lendToken, uint256 amount) external returns (uint256) {
        // contract must approve LendingPool beforehand
        return pool.createLendingOffer(lendToken, amount, 600, 30 days, address(0), 15000);
    }
}

contract PoolAdapterTest is Test {
    MockERC20 lendToken;
    LendingPool pool;
    LoanPositionNFT nft;

    PoolAdapterMock adapter;

    address deployer = address(this);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        // deploy oracle as dummy
        address dummyOracle = address(0x1);
        pool = new LendingPool(dummyOracle);

        // deploy NFT and give MINTER_ROLE to deployer; later we'll grant to pool in test
        nft = new LoanPositionNFT("LoanPos", "LPOS");

        // adapter (a contract) will act as lender
        adapter = new PoolAdapterMock(pool);

        // mint tokens to adapter contract
        lendToken.mint(address(adapter), 500 ether);
    }

    function testContractLenderCanCreateOffer() public {
        // adapter must approve the pool to transfer tokens from adapter
        vm.prank(address(adapter));
        lendToken.approve(address(pool), 100 ether);

        // adapter calls createOffer
        uint256 id = adapter.createOffer(address(lendToken), 100 ether);

        // pool should hold tokens
        assertEq(lendToken.balanceOf(address(pool)), 100 ether);
        assertEq(id, 1);
    }

    function testGrantMinterRoleToPool() public {
        // default admin role is deployer (this), grant MINTER_ROLE to pool
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        // verify pool has role
        assertTrue(nft.hasRole(MINTER, address(pool)));
    }
}
