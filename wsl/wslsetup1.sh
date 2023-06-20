#!/usr/bin/bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

## Global environmment variables (editable)
sudo sh -c "echo export FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT=1  >  /etc/profile.d/global-variables.sh"
sudo sh -c "echo # export AW1=AW1       >>  /etc/profile.d/global-variables.sh"
# Turn off Microsoft telemetry for Azure Function Tools

# leave along at C.UTF-8 for maximum compatiblity
##sudo locale-gen "C.UTF-8"
##sudo update-locale LANG=C.UTF-8 LANGUAGE=C.UTF-8 LC_MESSAGES=C.UTF-8 LC_COLLATE= LC_CTYPE= LC_ALL=C

# the system will now reboot
