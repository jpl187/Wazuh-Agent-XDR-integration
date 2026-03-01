#!/bin/bash

# ==============================
# Full MITRE Atomic MDR Demo
# Installs + Runs + Cleans + Removes
# ==============================

TARGET="192.168.1.50"
USER="Administrator"
PASS="Password123!"

echo "[*] Connecting to $TARGET"
echo "[*] Installing Atomic Red Team..."

evil-winrm -i $TARGET -u $USER -p $PASS <<'EOF'

# ------------------------------
# Setup Phase
# ------------------------------

$ErrorActionPreference = "SilentlyContinue"

# Save current execution policy
$oldPolicy = Get-ExecutionPolicy -Scope LocalMachine

Set-ExecutionPolicy Bypass -Scope Process -Force

# Install NuGet provider if missing
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Install Atomic Red Team module
Install-Module -Name AtomicRedTeam -Scope CurrentUser -Force

Import-Module AtomicRedTeam

# Download atomics
Install-AtomicRedTeam -getAtomics -Force

Write-Host "[+] Atomic Red Team Installed"

# ------------------------------
# Function to Run + Cleanup
# ------------------------------

function Run-AtomicClean {
    param (
        [string]$Technique,
        [int]$TestNumber
    )

    Write-Host "====================================="
    Write-Host "[*] Running $Technique"
    Write-Host "====================================="

    Invoke-AtomicTest $Technique -TestNumbers $TestNumber
    Start-Sleep -Seconds 5
    Invoke-AtomicTest $Technique -TestNumbers $TestNumber -Cleanup
    Start-Sleep -Seconds 3
}

# ------------------------------
# Demo Execution
# ------------------------------

Run-AtomicClean "T1059.001" 1    # Execution
Run-AtomicClean "T1547.001" 1    # Persistence
Run-AtomicClean "T1087.001" 1    # Discovery
Run-AtomicClean "T1003.001" 1    # Credential Access
Run-AtomicClean "T1562.001" 1    # Defense Evasion
Run-AtomicClean "T1113" 1        # Collection
Run-AtomicClean "T1071.001" 1    # C2
Run-AtomicClean "T1041" 1        # Exfiltration
Run-AtomicClean "T1490" 1        # Impact

Write-Host "[+] Demo Completed"

# ------------------------------
# Removal Phase
# ------------------------------

Write-Host "[*] Removing Atomic Red Team..."

# Remove module
Uninstall-Module -Name AtomicRedTeam -AllVersions -Force

# Remove downloaded atomics
$atomicPath = "$env:USERPROFILE\AtomicRedTeam"
if (Test-Path $atomicPath) {
    Remove-Item -Recurse -Force $atomicPath
}

# Restore execution policy
Set-ExecutionPolicy $oldPolicy -Scope LocalMachine -Force

Write-Host "[+] Atomic Red Team Removed"
Write-Host "[+] System returned close to original state"

EOF

echo
echo "====================================="
echo "[+] Full Demo Complete"
echo "====================================="
