    # -------------------------
    # 1. INITIAL SETUP
    # -------------------------
    $logPath = "C:\Users\hellz\OneDrive\Programing\powershell\projects\raspberryPi_auto_update\logs.txt"
    $piHost = "thewizard@blockmagic"
    $ssh = "ssh $piHost"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    "-------------------------`n PIHOLE AUTOMATIC UPDATE LOG `n-------------------------" | Out-File $logPath -Append
    "Last run: $timestamp`n" | Out-File $logPath -Append

    # -------------------------
    # 2. TEST SSH CONNECTION
    # -------------------------
    $output = ssh $piHost "echo connected" 2>&1

    if ($LASTEXITCODE -eq 0) {
        "SSH login: successful" | Out-File $logPath -Append
    }
    else {
        "SSH login: failed`n" | Out-File $logPath -Append
        "Error: $($output[0])`n" | Out-File $logPath -Append
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
        [switch]$successOnly,
        [switch]$upgradeSummary
    )

    "{$taskName}:" | Out-File $logPath -Append

    $output = ssh $piHost $sshCommand 2>&1

    if ($LASTEXITCODE -eq 0) {
       
        #1. Log Success
        "{$taskName}: successful`n" | Out-File $logPath -Append

        # 2. If this task wants the apt summary, extract it        
        if ($upgradeSummary) {

            # Find "Not Upgrading:"
            $notUpgradingHeader = $output | Where-Object { $_ -match "Not Upgrading:" }
            if ($notUpgradingHeader) {
                $notUpgradingIndex = $output.IndexOf($notUpgradingHeader)
                $notUpgradingBody = $output[$notUpgradingIndex + 1]

                "Not Upgrading:`n" | Out-File $logPath -Append
                "$notUpgradingBody`n" | Out-File $logPath -Append
            }

            #Find "Summary"
            $summaryHeader = $output | Where-Object { $_ -match "^Summary:" }
            if ($summaryHeader) {
                $summaryIndex = $output.IndexOf($summaryHeader)
                $summaryBody = $output[$summaryIndex + 1]

                "Summary:`n" | Out-File $logPath -Append
                "$summaryBody`n" | Out-File $logPath -Append
            }
        }
               
        # 3. If NOT upgradeSummary, and NOT successOnly, print normal output
        if (-not $upgradeSummary -and -not $successOnly) {        
            "{$taskName}: $output`n" | Out-File $logPath -Append
        }
    }
    else {
        "{$taskName}: failed`n" | Out-File $logPath -Append
        "Error: $($output[0])`n" | Out-File $logPath -Append
    }
}
    # -------------------------
    # 4. LOOP 1: MAINTENANCE REPORT
    # -------------------------
    "----`n MAINTENANCE REPORT `n----"  | Out-File $logPath -Append

    Run-SSH -taskName "Wipe logs" -sshCommand "sudo rm -rf /var/log/*" -SuccessOnly
    Run-SSH -taskName "Check disk space" -sshCommand "df -h /"
    Run-SSH -taskName "Check uptime" -sshCommand "uptime -p"
    Run-SSH -taskName "Check temperature" -sshCommand "vcgencmd measure_temp"
    Run-SSH -taskName "Check throttling" -sshCommand "vcgencmd get_throttled"
    Run-SSH -taskName "Check Pi-hole status" -sshCommand "pihole status"
    
    # -------------------------
    # 5. LOOP 2: OS UPDATES REPORT
    # -------------------------
    "----`n OS UPDATES REPORT `n----"  | Out-File $logPath -Append

    Run-SSH -taskName "Number of package updates available" -sshCommand "sudo apt -update"
    Run-SSH -taskName "Package upgrades" -sshCommand "sudo apt upgrade" -upgradeSummary

  
