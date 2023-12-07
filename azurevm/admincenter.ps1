New-NetFirewallRule -DisplayName "Allow Windows Admin Center" -Direction Outbound -profile Domain -LocalPort 6516 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow Windows Admin Center" -Direction Inbound  -profile Domain -LocalPort 6516 -Protocol TCP -Action Allow
