# keep-awake.ps1
# Recommended: prevents system/display sleep without sending keystrokes.
# Press Ctrl+C in the console to stop, or close the window.

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Pow {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@

# Flags:
$ES_CONTINUOUS       = 0x80000000u
$ES_SYSTEM_REQUIRED  = 0x00000001u
$ES_DISPLAY_REQUIRED = 0x00000002u

# Combine flags to keep system + display awake continuously.
# (If you want only system awake and allow display to turn off, omit ES_DISPLAY_REQUIRED)
$flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED

try {
    [Pow]::SetThreadExecutionState($flags) | Out-Null
    Write-Host "System sleep/display sleep prevented. Press Ctrl+C to stop."
    while ($true) {
        Start-Sleep -Seconds 60
    }
}
finally {
    # On exit, clear the continuous state so normal behaviour resumes
    [Pow]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
    Write-Host "Restored normal power settings."
}
