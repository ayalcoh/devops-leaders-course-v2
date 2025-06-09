#!/bin/bash

# Script to run unit tests using pytest and report status
# Exit on any error
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================"
echo " Running Unit Tests with Pytest"
echo "============================"
echo

# Check if pytest is available
if ! command -v pytest &> /dev/null; then
    echo -e "${RED}❌ pytest is not installed${NC}"
    echo "Installing pytest..."
    pip install pytest
fi

# Run pytest with verbose output and capture exit code
echo -e "${YELLOW}Running pytest...${NC}"
echo

if pytest -v --tb=short; then
    echo
    echo -e "${GREEN}✅ All unit tests PASSED${NC}"
    echo -e "${GREEN}Status: SUCCESS${NC}"
    exit 0
else
    echo
    echo -e "${RED}❌ Some unit tests FAILED${NC}"
    echo -e "${RED}Status: FAILURE${NC}"
    exit 1
fi