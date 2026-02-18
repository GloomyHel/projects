    # -------------------------
    # 1. INITIAL SETUP
    # -------------------------
    Import-Module "$PSScriptRoot\RaspberryPiTools.psm1"
    $LogPath = "C:\Users\hellz\OneDrive\Programing\powershell\projects\raspberryPi_auto_update\raspberryPi_update.log"
    $PiHost = "thewizard@blockmagic"
    $StartTime = Get-Date
    $Timestamp = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")

    "-----------------------------------`n RASPBERRY-PI AUTOMATIC UPDATE LOG `n-----------------------------------" | Out-File $LogPath
    "Last run: $Timestamp" | Out-File $LogPath -Append

    # -------------------------
    # 2. TEST SSH CONNECTION
    # -------------------------
    # Force PowerShell to treat SSH Output as UTF-8
    $OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $Output = ssh $PiHost "echo connected" 2>&1

    if ($LASTEXITCODE -eq 0) {
        "SSH login: successful`n" | Out-File $LogPath -Append
    }
    else {
        "SSH login: failed" | Out-File $LogPath -Append
        "Error: $($Output[0])" | Out-File $LogPath -Append
        "Automatic update failed (see Raspberry Pi logs)`n" | Out-File $LogPath -Append
        exit
    }
    #Debug: print raw Output to console
    $UpgradeResult = Invoke-SshCommand -TaskName "Package upgrades" `
                  -SshCommand 'bash -c "sudo apt upgrade -y 2>&1"' `
                  -PiHost $PiHost `
                  -LogPath $LogPath `
                  -SuccessOnly

    Write-Host "==== DEBUG UpgradeResult ===="
    $UpgradeResult | Format-List *   # <- add this
    Write-Host "============================="

    # -------------------------
    # 3. LOOP 1: MAINTENANCE REPORT
    # -------------------------
    "----------`n MAINTENANCE REPORT `n----------"  | Out-File $LogPath -Append

    Invoke-SshCommand -TaskName "Wipe logs" `
                  -SshCommand "sudo rm -rf /var/log/*" `
                  -PiHost $PiHost `
                  -LogPath $LogPath `
                  -SuccessOnly

    Invoke-SshCommand -TaskName "Check disk space" `
                  -OutputLabel "Disk space" `
                  -SshCommand "df -h /" `
                  -PiHost $PiHost `
                  -LogPath $LogPath
    
    Invoke-SshCommand -TaskName "Check uptime" `
                  -OutputLabel "Uptime" `
                  -SshCommand "uptime -p" `
                  -PiHost $PiHost `
                  -LogPath $LogPath
    
    Invoke-SshCommand -TaskName "Check temperature" `
                  -OutputLabel "Temperature" `
                  -SshCommand "vcgencmd measure_temp" `
                  -PiHost $PiHost `
                  -LogPath $LogPath

    Invoke-SshCommand -TaskName "Check throttling" `
                  -OutputLabel "Throttling" `
                  -SshCommand "vcgencmd get_throttled" `
                  -PiHost $PiHost `
                  -LogPath $LogPath

    Invoke-SshCommand -TaskName "Check Pi-hole status" `
                  -OutputLabel "Pi-hole status" `
                  -SshCommand "pihole status" `
                  -PiHost $PiHost `
                  -LogPath $LogPath
    
    # -------------------------
    # 4. LOOP 2: OS UPDATES REPORT
    # -------------------------
    "----------`n OS UPDATES REPORT `n----------"  | Out-File $LogPath -Append

    Invoke-SshCommand -TaskName "Check for package updates" `
                  -OutputLabel "Number of package updates available" `
                  -SshCommand "apt list --upgradeable 2>/dev/null | wc -l" `
                  -PiHost $PiHost `
                  -LogPath $LogPath
    
    
    # 1. Get list of upgradeable packages
    $ListResult = Invoke-SshCommand -TaskName "List upgradeable packages" `
                                    -SshCommand "apt list --upgradeable 2>/dev/null" `
                                    -PiHost $PiHost `
                                    -LogPath $LogPath `
                                    -SuccessOnly

    # 2. Build stable summary
    $UpgradeSummary = ConvertFrom-AptSummary -Output $ListResult.Output

    # 3. Perform the upgrade (output ignored)
    Invoke-SshCommand -TaskName "Package upgrades" `
                    -SshCommand "sudo apt upgrade -y" `
                    -PiHost $PiHost `
                    -LogPath $LogPath `
                    -SuccessOnly

    # 4. Log the summary
    Write-LogSummary -SummaryObject $UpgradeSummary -LogPath $LogPath


    # -------------------------
    # 5. LOOP 3: PI-HOLE UPDATES REPORT
    # -------------------------
    "----------`n PI-HOLE UPDATES REPORT `n----------"  | Out-File $LogPath -Append

    Invoke-SshCommand -TaskName "Check for Pi-hole updates" `
                  -OutputLabel "Pi-hole versions" `
                  -SshCommand "pihole -v" `
                  -PiHost $PiHost `
                  -LogPath $LogPath

    Invoke-SshCommand -TaskName "Pi-hole updates" `
                  -SshCommand "sudo pihole -up" `
                  -PiHost $PiHost `
                  -LogPath $LogPath `
                  -SuccessOnly

    # -------------------------
    # 6. REBOOT
    # -------------------------
    "----------`n RASPBERRY-PI REBOOT `n----------"  | Out-File $LogPath -Append  

   # Invoke-SshCommand -TaskName "Rebooting Raspberry Pi" `
   #               -SshCommand "sudo reboot" `
   #               -PiHost $PiHost `
   #               -LogPath $LogPath `
   #               -SuccessOnly

    # -------------------------
    # 10. FINAL SUMMARY AND RUNTIME CALCULATION
    # -------------------------
    "----------`n FINAL SUMMARY `n----------"  | Out-File $LogPath -Append

    # Calculate total runtime
    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime
    "Automatic update completed: $Timestamp`nTotal runtime: $Duration`n(see Raspberry Pi logs)" | Out-File $LogPath -Append