Enable-PSRemoting -force -SkipNetworkProfileCheck

Install-PackageProvider -name nuget -force -forcebootstrap -scope allusers
Update-Module PackageManagement,PowerShellGet -force

#run updates and installs in the background
Start-Job {Install-Module PSScriptTools,PSTeachingTools -force}
Start-Job {Install-Module PSReleaseTools -force; Install-PowerShell -mode quiet -enableremoting -EnableContextMenu}
Start-Job {Install-Module WTToolbox -force ; Install-WTRelease}
Start-Job -FilePath c:\scripts\install-vscodesandbox.ps1
Start-Job -FilePath c:\scripts\Set-SandboxDesktop.ps1

#wait for everything to finish
Get-Job | Wait-Job
