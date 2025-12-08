#!/bin/bash
# Setup DEX routers and Chainlink price feeds for Base Sepolia
# Run after basic admin configuration is complete

set -e

# Deployed contract addresses
PRICE_ORACLE="0x428EeAD1456C43EaA2BfF10E71509f2cCbAA5fFf"
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
echo "BaseFi - Router & Price Feed Setup"
echo "========================================="
echo ""
echo "Network: Base Sepolia (84532)"
echo ""

# ============================================
# DEX Routers on Base Sepolia
# ============================================
echo "📍 Available DEX Routers on Base Sepolia:"
echo ""
echo "1. Uniswap V2 Router (if available)"
echo "2. Uniswap V3 SwapRouter (recommended)"
echo "   Address: 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4"
echo ""
echo "3. BaseSwap Router (Base-native DEX)"
echo "   Check: https://baseswap.fi/"
echo ""
echo "4. Aerodrome Router (popular on Base)"
echo "   Check: https://aerodrome.finance/"
echo ""

# For this example, we'll use Uniswap V3 SwapRouter
UNISWAP_V3_ROUTER="0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4"

echo "📍 Step 1: Whitelist Uniswap V3 Router"
echo "Router: $UNISWAP_V3_ROUTER"
echo ""

cast send $LENDING_POOL \
  "setRouterWhitelisted(address,bool)" \
  $UNISWAP_V3_ROUTER true \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ Uniswap V3 Router whitelisted"
echo ""
sleep 3

# ============================================
# Chainlink Price Feeds on Base Sepolia
# ============================================
echo "========================================="
echo "📍 Step 2: Add Chainlink Price Feeds"
echo "========================================="
echo ""
echo "Base Sepolia Chainlink Feeds (as of Dec 2024):"
echo ""
echo "ETH/USD:  0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1"
echo "USDC/USD: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165"
echo "DAI/USD:  Not available on Base Sepolia yet"
echo "LINK/USD: 0xb113F5A928BCfF189C998ab20d753a47F9dE5A61"
echo ""
echo "Full list: https://docs.chain.link/data-feeds/price-feeds/addresses?network=base-sepolia"
echo ""

# Common Base Sepolia token addresses (testnet)
# Note: These may change; verify on Base Sepolia block explorer
WETH_SEPOLIA="0x4200000000000000000000000000000000000006"  # Wrapped ETH on Base
# USDC on Base Sepolia - check latest address from Base docs or faucets

# ETH/USD feed
ETH_USD_FEED="0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1"

echo "Adding ETH/USD price feed..."
echo "Token (WETH): $WETH_SEPOLIA"
echo "Feed: $ETH_USD_FEED"
echo ""

cast send $PRICE_ORACLE \
  "setPriceFeed(address,address)" \
  $WETH_SEPOLIA $ETH_USD_FEED \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 100000

echo "✅ ETH/USD price feed added"
echo ""
sleep 3

# USDC/USD feed
USDC_USD_FEED="0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165"
# You'll need to find the actual USDC contract address on Base Sepolia
# Check: https://docs.base.org/tokens/list or Base Sepolia faucets

echo "📍 USDC/USD Feed Available"
echo "Feed: $USDC_USD_FEED"
echo ""
echo "⚠️  To add USDC feed, you need the USDC token address on Base Sepolia"
echo "Once you have it, run:"
echo ""
echo "cast send $PRICE_ORACLE \\"
echo '  "setPriceFeed(address,address)" \'
echo '  <USDC_TOKEN_ADDRESS> '"$USDC_USD_FEED"' \'
echo "  --rpc-url \$BASE_SEPOLIA_RPC_URL \\"
echo "  --private-key \$PRIVATE_KEY"
echo ""
sleep 2

# LINK/USD feed
LINK_USD_FEED="0xb113F5A928BCfF189C998ab20d753a47F9dE5A61"

echo "📍 LINK/USD Feed Available"
echo "Feed: $LINK_USD_FEED"
echo ""
echo "⚠️  To add LINK feed, you need the LINK token address on Base Sepolia"
echo "Once you have it, run:"
echo ""
echo "cast send $PRICE_ORACLE \\"
echo '  "setPriceFeed(address,address)" \'
echo '  <LINK_TOKEN_ADDRESS> '"$LINK_USD_FEED"' \'
echo "  --rpc-url \$BASE_SEPOLIA_RPC_URL \\"
echo "  --private-key \$PRIVATE_KEY"
echo ""

# ============================================
# Summary
# ============================================
echo "========================================="
echo "✅ Setup Complete!"
echo "========================================="
echo ""
echo "Configured:"
echo "  - Whitelisted Router: Uniswap V3 ($UNISWAP_V3_ROUTER)"
echo "  - Price Feed: ETH/USD"
echo ""
echo "Next steps:"
echo "  1. Get testnet USDC/LINK/other token addresses from Base Sepolia faucets"
echo "  2. Add their price feeds using the commands above"
echo "  3. Test creating offers/requests with these tokens"
echo ""
echo "Useful resources:"
echo "  - Base Sepolia Faucet: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet"
echo "  - Chainlink Feeds: https://docs.chain.link/data-feeds/price-feeds/addresses?network=base-sepolia"
echo "  - Base Sepolia Explorer: https://sepolia.basescan.org/"
echo ""
