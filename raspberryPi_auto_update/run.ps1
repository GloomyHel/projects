    # -------------------------
    # 1. INITIAL SETUP
    # -------------------------
    $logPath = "C:\Users\hellz\OneDrive\Programing\powershell\projects\raspberryPi_auto_update\logs.txt"
    $piHost = "thewizard@blockmagic"
    $ssh = "ssh $piHost"
    $startTime = Get-Date
    $timestamp = $startTime.ToString("yyyy-MM-dd HH:mm:ss")

    "-----------------------------------`n RASPBERRY-PI AUTOMATIC UPDATE LOG `n-----------------------------------" | Out-File $logPath
    "Last run: $timestamp" | Out-File $logPath -Append

    # -------------------------
    # 2. TEST SSH CONNECTION
    # -------------------------
    # Force PowerShell to treat SSH output as UTF-8
    $OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $output = ssh $piHost "echo connected" 2>&1

    if ($LASTEXITCODE -eq 0) {
        "SSH login: successful`n" | Out-File $logPath -Append
    }
    else {
        "SSH login: failed" | Out-File $logPath -Append
        "Error: $($output[0])" | Out-File $logPath -Append
        "Automatic update failed (see Raspberry Pi logs)`n" | Out-File $logPath -Append
        exit
    }
    
    # -------------------------
    # 3. FUNCTION TO RUN SSH COMMANDS AND LOG OUTPUT
    # -------------------------
    function Run-SSH {
    param(
        [string]$taskName,
        [string]$sshCommand,
        [string]$outputLabel,
        [switch]$successOnly,
        [switch]$upgradeSummary
    )

    $output = ssh $piHost $sshCommand 2>&1
    # Split on any newline variant
    $output = $output -split "\r?\n"
    # Remove any remaining control characters
    $output = $output -replace "[\x00-\x1F\x7F]", ""
    # Trim whitespace from each line
    $output = $output | ForEach-Object { $_.Trim() }

    if ($LASTEXITCODE -eq 0) {
       
        #1. Log Success
        "{$taskName}: successful" | Out-File $logPath -Append

        # 2. If this task wants the apt summary, extract it        
        if ($upgradeSummary) {

            #Find "Summary"
            $summaryHeader = $output | Where-Object { $_ -match "^Summary:" }
            if ($summaryHeader) {
                $summaryIndex = $output.IndexOf($summaryHeader)
                $summaryBody = $output[$summaryIndex + 1]

                "SUMMARY: $summaryBody" | Out-File $logPath -Append
            }

            # Find "Not Upgrading:"
            $notUpgradingHeader = $output | Where-Object { $_ -match "Not upgrading:" }
            if ($notUpgradingHeader) {
                $notUpgradingIndex = $output.IndexOf($notUpgradingHeader)
                $notUpgradingBody = $output[$notUpgradingIndex + 1]

                "NOT UPGRADING: $notUpgradingBody`n" | Out-File $logPath -Append
            }
        }
               
        # 3. If NOT upgradeSummary, and NOT successOnly, print normal output
        if (-not $upgradeSummary -and -not $successOnly) {        
            # Decide label
            $label = $outputLabel
            if (-not $label) { $label = $taskName }
            # Format output
            if ($output.Count -gt 1) {
                $formattedOutput = $output -join "`n" 
            }
            else {
                $formattedOutput = $output[0]
            }  
            # Log output for multi-line, or single line
            if ($output.Count -gt 1) {
                #Multi-line output
                "{$label}:" | Out-File $logPath -Append
                "$formattedOutput`n" | Out-File $logPath -Append
            }
            else {  
                #Single-line output
                "{$label}: $formattedOutput`n" | Out-File $logPath -Append
            }
        }
    }
    else {
        "{$taskName}: failed" | Out-File $logPath -Append
        "ERROR: $($output[0])`n" | Out-File $logPath -Append
    }
}
    # -------------------------
    # 4. LOOP 1: MAINTENANCE REPORT
    # -------------------------
    "----------`n MAINTENANCE REPORT `n----------"  | Out-File $logPath -Append

    Run-SSH -taskName "Wipe logs" -sshCommand "sudo rm -rf /var/log/*" -SuccessOnly
    Run-SSH -taskName "Check disk space" -outputLabel "Disk space" -sshCommand "df -h /"
    Run-SSH -taskName "Check uptime" -outputLabel "Uptime" -sshCommand "uptime -p"
    Run-SSH -taskName "Check temperature" -outputLabel "Temperature" -sshCommand "vcgencmd measure_temp"
    Run-SSH -taskName "Check throttling" -outputLabel "Throttling" -sshCommand "vcgencmd get_throttled"
    Run-SSH -taskName "Check Pi-hole status" -outputLabel "Pi-hole status" -sshCommand "pihole status"
    
    # -------------------------
    # 5. LOOP 2: OS UPDATES REPORT
    # -------------------------
    "----------`n OS UPDATES REPORT `n----------"  | Out-File $logPath -Append

    Run-SSH -taskName "Check for package updates" -outputLabel "Number of package updates available" -sshCommand "apt list --upgradeable 2>/dev/null | wc -l"
    Run-SSH -taskName "Package upgrades" -sshCommand "sudo apt upgrade" -upgradeSummary

    # -------------------------
    # 6. LOOP 3: PI-HOLE UPDATES REPORT
    # -------------------------
    "----------`n PI-HOLE UPDATES REPORT `n----------"  | Out-File $logPath -Append

    Run-SSH -taskName "Check for Pi-hole updates" -outputLabel "Pi-hole versions" -sshCommand "pihole -v"
    Run-SSH -taskName "Pi-hole updates" -sshCommand "pihole -up" -successOnly

    # -------------------------
    # 7. REBOOT
    # -------------------------
    "----------`n RASPBERRY-PI REBOOT `n----------"  | Out-File $logPath -Append  

   # Run-SSH -taskName "Rebooting Raspberry Pi" -sshCommand "sudo reboot" -successOnly

    # -------------------------
    # 8. FINAL SUMMARY AND RUNTIME CALCULATION
    # -------------------------
    "----------`n FINAL SUMMARY `n----------"  | Out-File $logPath -Append

    # Calculate total runtime
    $endTime = Get-Date
    $duration = $endTime - $startTime
    "Automatic update completed: $timestamp`nTotal runtime: $duration`n(see Raspberry Pi logs)" | Out-File $logPath -Append