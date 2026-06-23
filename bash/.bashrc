# ~/.bashrc - Cloud Shell customization

# Useful aliases for common Azure operations
alias rg='az group list --output table'
alias vms='az vm list --output table --show-details'
alias subs='az account list --output table'
alias current='az account show --output table'

# Quick resource group switching
rgset() {
    # Set default resource group for subsequent commands
    az configure --defaults group="$1"
    echo "Default resource group set to: $1"
}

# Fast subscription switching
subswitch() {
    # Switch active subscription by name or ID
    az account set --subscription "$1"
    echo "Switched to: $(az account show --query name -o tsv)"
}

# List all resources in a resource group with their types
rglist() {
    az resource list \
      --resource-group "${1:-$(az configure --list-defaults --query '[?name==`group`].value' -o tsv)}" \
      --output table
}

# Environment variables
export EDITOR=vim
export AZURE_DEV_COLLECT_TELEMETRY=no

# Colored prompt showing current subscription
PS1='\[\e[36m\][$(az account show --query name -o tsv 2>/dev/null || echo "no-sub")]\[\e[0m\] \[\e[32m\]\w\[\e[0m\] $ '
