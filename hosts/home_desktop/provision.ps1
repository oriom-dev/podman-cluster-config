#Requires -RunAsAdministrator
<#
Creates or updates the home-desktop Hyper-V VM on desktop-1. Safe to re-run:
existing switch, NAT, disks and VM are kept; settings and ACLs are re-applied.

  powershell -ExecutionPolicy Bypass -File provision.ps1 -ImagePath C:\HyperV\home-desktop\image.vhdx

Isolation is enforced here, on the host, so root inside the VM cannot undo it:
the VM may open connections to the public Internet only. Every private, CGNAT
(Tailscale), link-local and multicast range is denied in both directions, which
covers desktop-1 itself, the home LAN, VPNs and the Windows tailnet. The single
exception is SSH from this host (10.250.0.1) to the VM for management.
#>
param(
    [string] $ImagePath,
    [string] $VmName = 'home-desktop',
    [string] $SystemDir = 'C:\HyperV\home-desktop',
    [string] $DataDir = 'S:\HyperV\home-desktop',
    [string] $SwitchName = 'oriom-node',
    [string] $Prefix = '10.250.0',
    [int] $ProcessorCount = 4,
    [long] $MemoryBytes = 8GB,
    [long] $SystemDiskBytes = 64GB,
    [long] $DataDiskBytes = 512GB
)
$ErrorActionPreference = 'Stop'

# --- Network: dedicated internal switch behind WinNAT -------------------------
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
}
$hostAlias = "vEthernet ($SwitchName)"
if (-not (Get-NetIPAddress -InterfaceAlias $hostAlias -IPAddress "$Prefix.1" -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceAlias $hostAlias -IPAddress "$Prefix.1" -PrefixLength 24 | Out-Null
}
if (-not (Get-NetNat -Name $SwitchName -ErrorAction SilentlyContinue)) {
    New-NetNat -Name $SwitchName -InternalIPInterfaceAddressPrefix "$Prefix.0/24" | Out-Null
}
# No IPv6 on the host side of the switch: no link-local path from the VM to the host.
Disable-NetAdapterBinding -Name $hostAlias -ComponentID ms_tcpip6

# --- Disks ---------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $SystemDir, $DataDir | Out-Null
$systemDisk = Join-Path $SystemDir "$VmName.vhdx"
if (-not (Test-Path $systemDisk)) {
    if (-not $ImagePath) { throw 'first run needs -ImagePath (nix build .#home-desktop-image)' }
    Copy-Item -Path $ImagePath -Destination $systemDisk
    Resize-VHD -Path $systemDisk -SizeBytes $SystemDiskBytes
}
$dataDisk = Join-Path $DataDir "$VmName-data.vhdx"
if (-not (Test-Path $dataDisk)) {
    New-VHD -Path $dataDisk -SizeBytes $DataDiskBytes -Dynamic | Out-Null
}

# --- VM ------------------------------------------------------------------------
if (-not (Get-VM -Name $VmName -ErrorAction SilentlyContinue)) {
    New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $MemoryBytes `
        -VHDPath $systemDisk -SwitchName $SwitchName -Path $SystemDir | Out-Null
    Add-VMHardDiskDrive -VMName $VmName -Path $dataDisk
}
Set-VM -Name $VmName -ProcessorCount $ProcessorCount -StaticMemory -MemoryStartupBytes $MemoryBytes `
    -AutomaticStartAction Start -AutomaticStartDelay 60 -AutomaticStopAction ShutDown `
    -CheckpointType Disabled
# Host workloads (research simulations) win under contention: half the default
# scheduling weight, and the VM can use at most 75% of its 4 vCPUs.
Set-VMProcessor -VMName $VmName -RelativeWeight 50 -Maximum 75
Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
# No host file copy into the guest. Matched by ID: display names are localised.
Get-VMIntegrationService -VMName $VmName |
    Where-Object { $_.Id -like '*6C09BB55-D683-4DA0-8931-C9BF705F6480' } |
    Disable-VMIntegrationService
Set-VMNetworkAdapter -VMName $VmName -DhcpGuard On -RouterGuard On -MacAddressSpoofing Off

# --- Port ACLs (host-enforced) -------------------------------------------------
Get-VMNetworkAdapterExtendedAcl -VMName $VmName | Remove-VMNetworkAdapterExtendedAcl
function Add-Acl([string] $Direction, [string] $Action, [string] $Remote, [int] $Weight,
                 [string] $Protocol = $null, [string] $LocalPort = $null, [bool] $Stateful = $false) {
    $acl = @{ VMName = $VmName; Direction = $Direction; Action = $Action;
               RemoteIPAddress = $Remote; Weight = $Weight }
    if ($Protocol) { $acl.Protocol = $Protocol }
    if ($LocalPort) { $acl.LocalPort = $LocalPort }
    if ($Stateful) { $acl.Stateful = $true; $acl.IdleSessionTimeout = 3600 }
    Add-VMNetworkAdapterExtendedAcl @acl
}
# Baseline: outbound TCP/UDP to anywhere (stateful, so replies come back), nothing
# unsolicited inbound.
Add-Acl Outbound Allow '0.0.0.0/0' 1 'TCP' -Stateful $true
Add-Acl Outbound Allow '0.0.0.0/0' 2 'UDP' -Stateful $true
Add-Acl Inbound Deny '0.0.0.0/0' 3
Add-Acl Outbound Deny '0.0.0.0/0' 4 'ICMPv4'
# Non-public ranges, both directions, above the baseline.
$denied = '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
          '172.16.0.0/12', '192.0.0.0/24', '192.168.0.0/16', '198.18.0.0/15',
          '224.0.0.0/4', '240.0.0.0/4'
$w = 10
foreach ($range in $denied) {
    Add-Acl Outbound Deny $range $w
    Add-Acl Inbound Deny $range ($w + 1)
    $w += 2
}
# No IPv6 at all: the switch has no IPv6 uplink, and link-local would reach the host.
Add-Acl Outbound Deny '::/0' 50
Add-Acl Inbound Deny '::/0' 51
# Management: SSH from the Windows host only (highest weight).
Add-Acl Inbound Allow "$Prefix.1/32" 100 'TCP' -LocalPort '22' -Stateful $true

Get-VMNetworkAdapterExtendedAcl -VMName $VmName |
    Sort-Object Weight -Descending |
    Format-Table Direction, Action, RemoteIPAddress, Protocol, LocalPort, Stateful, Weight -AutoSize
Get-VM -Name $VmName | Format-List Name, State, ProcessorCount, MemoryStartup, AutomaticStartAction
