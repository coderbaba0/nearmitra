param([Parameter(Mandatory=$true)][string]$ProgramPath)
$ErrorActionPreference = 'Stop'
try {
    $ProgramPath = (Resolve-Path -LiteralPath $ProgramPath).Path
    foreach ($protocol in @('TCP','UDP')) {
        $name = "NearMitra.Private.$protocol"
        Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule -Name $name -DisplayName "NearMitra Nearby ($protocol, private network)" -Program $ProgramPath -Direction Inbound -Action Allow -Protocol $protocol -Profile Private -RemoteAddress LocalSubnet | Out-Null
    }
    exit 0
} catch {
    Write-Error $_
    exit 1
}
