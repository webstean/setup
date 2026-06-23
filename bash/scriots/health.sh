#!/bin/bash
# ~/clouddrive/scripts/resource-health.sh
# Checks resource health across all subscriptions

# Store the current subscription so we can switch back
ORIGINAL_SUB=$(az account show --query id -o tsv)

# Get all subscriptions
SUBS=$(az account list --query '[].id' -o tsv)

for sub in $SUBS; do
    SUB_NAME=$(az account show --subscription "$sub" --query name -o tsv)
    echo "=== $SUB_NAME ==="

    az account set --subscription "$sub"

    # Count resources by type
    az resource list --query '[].type' -o tsv | sort | uniq -c | sort -rn | head -10
    echo ""
done

# Switch back to original subscription
az account set --subscription "$ORIGINAL_SUB"
echo "Switched back to original subscription."
