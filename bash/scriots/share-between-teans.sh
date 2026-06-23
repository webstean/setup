# Create a local directory for synced team scripts
mkdir -p ~/team-scripts

# Download the current contents of the team file share
az storage file download-batch \
  --account-name "stcloudshellteam001" \
  --source "team-scripts" \
  --destination ~/team-scripts

# Add synced scripts to PATH
echo 'export PATH="$HOME/team-scripts:$PATH"' >> ~/.bashrc
