#!/bin/bash
# Admin configuration script for Base Sepolia deployment
# Run after deploying all three contracts and wiring them together

set -e

# Deployed contract addresses
PRICE_ORACLE="0x428EeAD1456C43EaA2BfF10E71509f2cCbAA5fFf"
LOAN_POSITION_NFT="0x950E723c8C75F925e5DB0aE388371621634920d0"
LENDING_POOL="0xE5cEdb79960ea461D778A130Da9cD279CD575331"

# Check required env vars
if [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
    echo "Error: BASE_SEPOLIA_RPC_URL not set"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set"
    exit 1
fi

echo "========================================="
echo "BaseFi P2P Lending - Admin Configuration"
echo "========================================="
echo ""
echo "Network: Base Sepolia (84532)"
echo "LendingPool: $LENDING_POOL"
echo ""

# ============================================
# 1. Set Guardian (optional emergency pause)
# ============================================
echo "📍 Step 1: Set Guardian Address"
echo "Current: Setting to deployer (you can change this to a multisig later)"
GUARDIAN="0x14842dFbD300253749a77C469f1D2913E3D556A4"  # Your deployer address

cast send $LENDING_POOL \
  "setGuardian(address)" \
  $GUARDIAN \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Guardian set to: $GUARDIAN"
echo ""
sleep 3

# ============================================
# 2. Set Owner Fee and Penalty BPS
# ============================================
echo "📍 Step 2: Set Owner Fee (1% = 100 BPS)"
# 1% owner fee on interest
cast send $LENDING_POOL \
  "setOwnerFeeBPS(uint256)" \
  100 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Owner fee set to 1% (100 BPS)"
echo ""
sleep 3

echo "📍 Step 3: Set Liquidation Penalty (2% = 200 BPS)"
# 2% penalty on liquidations
cast send $LENDING_POOL \
  "setPenaltyBPS(uint256)" \
  200 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Liquidation penalty set to 2% (200 BPS)"
echo ""
sleep 3

# ============================================
# 3. Set Interest Rate Band
# ============================================
echo "📍 Step 4: Set Interest Rate Band"
echo "Min: 1% (100 BPS), Max: 100% (10000 BPS)"
# Enforce rates between 1% and 100% APR
cast send $LENDING_POOL \
  "setInterestRateBand(uint256,uint256)" \
  100 10000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Interest rate band: 1% - 100% APR"
echo ""
sleep 3

# ============================================
# 4. Set Liquidation Grace Period
# ============================================
echo "📍 Step 5: Set Liquidation Grace Period"
echo "Grace period: 1 hour (3600 seconds)"
# 1 hour grace period after loan expires before liquidation
cast send $LENDING_POOL \
  "setLiquidationGracePeriodSecs(uint256)" \
  3600 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Grace period set to 1 hour"
echo ""
sleep 3

# ============================================
# 5. Set Global Active Principal Cap
# ============================================
echo "📍 Step 6: Set Global Active Principal Cap"
echo "Cap: 1,000,000 USDC (1000000 * 10^6 = 1e12 units)"
# 1M USDC total active principal cap (assuming 6 decimals)
cast send $LENDING_POOL \
  "setGlobalActivePrincipalCap(uint256)" \
  1000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Global cap set to 1M USDC equivalent"
echo ""
sleep 3

# ============================================
# 6. Set Max Duration
# ============================================
echo "📍 Step 7: Set Maximum Loan Duration"
echo "Max duration: 365 days (31536000 seconds)"
# 1 year maximum loan duration
cast send $LENDING_POOL \
  "setMaxDurationSecs(uint256)" \
  31536000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Max duration set to 365 days"
echo ""
sleep 3

# ============================================
# 7. Enable Collateral Validation
# ============================================
echo "📍 Step 8: Enable Collateral Validation"
cast send $LENDING_POOL \
  "setEnforceCollateralValidation(bool)" \
  true \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Collateral validation enabled"
echo ""
sleep 3

# ============================================
# 8. Whitelist Router (Example: Uniswap V2 on Base)
# ============================================
echo "📍 Step 9: Whitelist DEX Router"
echo "Note: Replace with actual Base Sepolia router address"
echo "Example placeholder: 0x0000000000000000000000000000000000000000"
echo ""
echo "⚠️  Skipping router whitelist - add your router address manually:"
echo "cast send $LENDING_POOL \\"
echo '  "setRouterWhitelisted(address,bool)" \'
echo '  <ROUTER_ADDRESS> true \'
echo "  --rpc-url \$BASE_SEPOLIA_RPC_URL \\"
echo "  --private-key \$PRIVATE_KEY"
echo ""

# ============================================
# 9. Oracle Configuration
# ============================================
echo "📍 Step 10: Configure Price Oracle"
echo "Setting max price age to 1 hour (3600 seconds)"
cast send $PRICE_ORACLE \
  "setMaxPriceAge(uint256)" \
  3600 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Oracle max price age set to 1 hour"
echo ""
echo "⚠️  Add price feeds for your assets manually:"
echo "cast send $PRICE_ORACLE \\"
echo '  "setPriceFeed(address,address)" \'
echo '  <TOKEN_ADDRESS> <CHAINLINK_AGGREGATOR_ADDRESS> \'
echo "  --rpc-url \$BASE_SEPOLIA_RPC_URL \\"
echo "  --private-key \$PRIVATE_KEY"
echo ""

# ============================================
# Summary
# ============================================
echo "========================================="
echo "✅ Configuration Complete!"
echo "========================================="
echo ""
echo "Summary of settings:"
echo "  - Guardian: $GUARDIAN"
echo "  - Owner Fee: 1% (100 BPS)"
echo "  - Liquidation Penalty: 2% (200 BPS)"
echo "  - Interest Rate Band: 1% - 50%"
echo "  - Grace Period: 1 hour"
echo "  - Global Cap: 1M USDC equivalent"
echo "  - Max Duration: 365 days"
echo "  - Collateral Validation: Enabled"
echo "  - Oracle Max Age: 1 hour"
echo ""
echo "Next steps:"
echo "  1. Whitelist DEX router(s) for swap functionality"
echo "  2. Add Chainlink price feeds to PriceOracle"
echo "  3. Optionally set per-asset caps with setAssetCap()"
echo "  4. Optionally set per-user caps with setBorrowerCap() and setLenderCap()"
echo ""
echo "🎉 Your protocol is ready for testing!"
echo ""
