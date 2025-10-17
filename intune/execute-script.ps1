Get-ExecutionPolicy
## Scopes
## MachinePolicy       Undefined
## UserPolicy          Undefined
## Process             Undefined
## CurrentUser         Undefined
## LocalMachine        Undefined

## Options
## Undefined
## Bypass
## RemoteSigned

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Set-ExecutionPolicy Bypass -Scope Process
