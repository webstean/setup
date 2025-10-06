# nudge-mouse.ps1
# Moves mouse by 1 pixel and returns it. Minimal visual disturbance.
# Press Ctrl+C to stop.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$intervalSeconds = 60   # how often to nudge (adjust as needed)

Write-Host "Nudging mouse every $intervalSeconds second(s). Press Ctrl+C to stop."

while ($true) {
    $pos = [System.Windows.Forms.Cursor]::Position
    try {
        # move right by 1 pixel and back
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($pos.X + 1, $pos.Y)
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.Cursor]::Position = $pos
    }
    catch {
        # ignore any errors that occur when session not interactive
    }
    Start-Sleep -Seconds $intervalSeconds
}
