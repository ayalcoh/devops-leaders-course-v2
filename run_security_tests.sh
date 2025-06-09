#!/bin/bash

# Script to run linting, formatting, secret scanning, and vulnerability scanning
# Continue even if a command fails
set +e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Use regular arrays instead of associative arrays for better compatibility
results=()
result_names=()
errors=()

echo "=============================================="
echo " Security and Quality Test Suite"
echo "=============================================="
echo

# Function to check and install tools
install_if_missing() {
    local tool=$1
    local install_cmd=$2
    
    if ! command -v $tool &> /dev/null; then
        echo -e "${YELLOW}⚠️  $tool not found, installing...${NC}"
        eval $install_cmd
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Failed to install $tool${NC}"
            return 1
        fi
    fi
    return 0
}

# Function to record results
record_result() {
    local name=$1
    local result=$2
    result_names+=("$name")
    results+=($result)
}

# 1. LINTING AND FORMATTING
echo -e "${BLUE}--- 1. Linting and Formatting ---${NC}"
echo

# Check/install black for formatting
install_if_missing "black" "pip install black"
if [ $? -eq 0 ]; then
    echo "Running Black formatting check..."
    black --check --diff .
    rc=$?
    record_result "Formatting (Black)" $rc
    if [ $rc -ne 0 ]; then 
        errors+=("Formatting (Black)")
        echo -e "${RED}❌ Code formatting issues found${NC}"
    else
        echo -e "${GREEN}✅ Code formatting is correct${NC}"
    fi
else
    record_result "Formatting (Black)" 1
    errors+=("Formatting (Black)")
fi

echo

# Check/install flake8 for linting
install_if_missing "flake8" "pip install flake8"
if [ $? -eq 0 ]; then
    echo "Running Flake8 linting..."
    flake8 . --exclude=venv --max-line-length=88 --extend-ignore=E203,W503
    rc=$?
    record_result "Linting (Flake8)" $rc
    if [ $rc -ne 0 ]; then 
        errors+=("Linting (Flake8)")
        echo -e "${RED}❌ Linting issues found${NC}"
    else
        echo -e "${GREEN}✅ No linting issues found${NC}"
    fi
else
    record_result "Linting (Flake8)" 1
    errors+=("Linting (Flake8)")
fi

echo

# 2. SECRET SCANNING
echo -e "${BLUE}--- 2. Secret Scanning ---${NC}"
echo

# Check/install truffleHog for secret scanning
if ! command -v trufflehog &> /dev/null; then
    echo -e "${YELLOW}⚠️  TruffleHog not found, trying alternative secret scanning...${NC}"
    
    # Use detect-secrets as alternative
    install_if_missing "detect-secrets" "pip install detect-secrets"
    if [ $? -eq 0 ]; then
        echo "Running detect-secrets scan..."
        detect-secrets scan --all-files --exclude-files venv/ > /dev/null 2>&1
        rc=$?
        record_result "Secret Scanning (detect-secrets)" $rc
        if [ $rc -ne 0 ]; then 
            errors+=("Secret Scanning (detect-secrets)")
            echo -e "${RED}❌ Potential secrets found${NC}"
        else
            echo -e "${GREEN}✅ No secrets detected${NC}"
        fi
    else
        # Manual basic secret scanning using grep
        echo "Running basic secret pattern search..."
        if grep -r -i --exclude-dir=venv --exclude-dir=.git \
            -E "(password|passwd|secret|token|key|api_key).*=.*['\"][^'\"]{8,}" . > /dev/null 2>&1; then
            echo -e "${RED}❌ Potential secrets found in code${NC}"
            record_result "Secret Scanning (Basic)" 1
            errors+=("Secret Scanning (Basic)")
        else
            echo -e "${GREEN}✅ No obvious secrets detected${NC}"
            record_result "Secret Scanning (Basic)" 0
        fi
    fi
else
    echo "Running TruffleHog secret scan..."
    trufflehog filesystem . --exclude-paths=venv/
    rc=$?
    record_result "Secret Scanning (TruffleHog)" $rc
    if [ $rc -ne 0 ]; then 
        errors+=("Secret Scanning (TruffleHog)")
        echo -e "${RED}❌ Potential secrets found${NC}"
    else
        echo -e "${GREEN}✅ No secrets detected${NC}"
    fi
fi

echo

# 3. VULNERABILITY SCANNING  
echo -e "${BLUE}--- 3. Vulnerability Scanning ---${NC}"
echo

# Check/install bandit for security analysis
install_if_missing "bandit" "pip install bandit"
if [ $? -eq 0 ]; then
    echo "Running Bandit security analysis..."
    bandit -r . --exclude ./venv -f json -o bandit-report.json -lll
    rc=$?
    record_result "Security Analysis (Bandit)" $rc
    if [ $rc -ne 0 ]; then 
        errors+=("Security Analysis (Bandit)")
        echo -e "${RED}❌ Security issues found${NC}"
    else
        echo -e "${GREEN}✅ No security issues found${NC}"
    fi
else
    record_result "Security Analysis (Bandit)" 1
    errors+=("Security Analysis (Bandit)")
fi

echo

# Check/install pip-audit for dependency vulnerabilities
install_if_missing "pip-audit" "pip install pip-audit"
if [ $? -eq 0 ]; then
    echo "Running pip-audit dependency vulnerability scan..."
    pip-audit -r requirements.txt --format=json --output=pip-audit-report.json
    rc=$?
    record_result "Dependency Vulnerabilities (pip-audit)" $rc
    if [ $rc -ne 0 ]; then 
        errors+=("Dependency Vulnerabilities (pip-audit)")
        echo -e "${RED}❌ Vulnerable dependencies found${NC}"
    else
        echo -e "${GREEN}✅ No vulnerable dependencies found${NC}"
    fi
else
    record_result "Dependency Vulnerabilities (pip-audit)" 1
    errors+=("Dependency Vulnerabilities (pip-audit)")
fi

echo
echo "=============================================="
echo " Test Suite Summary"
echo "=============================================="

# Print results
for i in "${!result_names[@]}"; do
  if [ ${results[$i]} -eq 0 ]; then
    printf "${GREEN}[PASS]${NC} %s\n" "${result_names[$i]}"
  else
    printf "${RED}[FAIL]${NC} %s\n" "${result_names[$i]}"
  fi
done

# Final status
if [ ${#errors[@]} -ne 0 ]; then
  echo
  echo -e "${RED}❌ OVERALL STATUS: FAILURE${NC}"
  echo "The following checks failed:"
  for step in "${errors[@]}"; do
    echo " - $step"
  done
  exit 1
else
  echo
  echo -e "${GREEN}✅ OVERALL STATUS: SUCCESS${NC}"
  echo "All security and quality checks passed."
  exit 0
fi