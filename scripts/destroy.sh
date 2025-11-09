#!/bin/bash
set -e

# Destroy script for Pseudo CodeSpaces
# This script completely destroys the infrastructure

echo "========================================="
echo "DESTROY - Pseudo CodeSpaces"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Warning message
echo -e "${RED}WARNING: This will completely destroy all infrastructure!${NC}"
echo ""
echo "This action will:"
echo "  - Destroy all server instances"
echo "  - Delete all network resources"
echo "  - Remove all storage volumes"
echo "  - Delete all firewall rules"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""

# Confirmation prompt
echo -e "${YELLOW}To confirm, type 'destroy' and press Enter:${NC}"
read -r CONFIRMATION

if [ "$CONFIRMATION" != "destroy" ]; then
    echo ""
    echo "Destroy cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting destruction process...${NC}"
echo ""

# Step 1: Check if terraform directory exists
if [ ! -d "terraform" ]; then
    echo -e "${RED}Error: terraform directory not found${NC}"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Step 2: Destroy infrastructure
echo -e "${YELLOW}Destroying infrastructure...${NC}"
cd terraform

if [ ! -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}No terraform state found. Nothing to destroy.${NC}"
    exit 0
fi

terraform destroy -auto-approve

echo ""
echo -e "${YELLOW}Waiting for resources to be fully deleted...${NC}"
sleep 15

# Step 3: Clean up state files (optional)
echo ""
echo -e "${YELLOW}Do you want to clean up Terraform state files? (y/N):${NC}"
read -r CLEANUP

if [ "$CLEANUP" = "y" ] || [ "$CLEANUP" = "Y" ]; then
    echo "Removing Terraform state files..."
    rm -f terraform.tfstate*
    rm -rf .terraform
    echo "State files removed."
fi

echo ""
echo "========================================="
echo -e "${YELLOW}Infrastructure Destroyed${NC}"
echo "========================================="
echo ""
echo "All resources have been destroyed."
echo ""
