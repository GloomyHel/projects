    # -------------------------
    # 1. INITIAL SETUP
    # -------------------------
    $logPath = "C:\Users\hellz\OneDrive\Programing\powershell\projects\raspberryPi_auto_update\raspberryPi_update.log"
    $piHost = "thewizard@blockmagic"
    $startTime = Get-Date
    $timestamp = $startTime.ToString("yyyy-MM-dd HH:mm:ss")

    "-----------------------------------`n RASPBERRY-PI AUTOMATIC UPDATE LOG `n-----------------------------------" | Out-File $logPath
    "Last run: $timestamp" | Out-File $logPath -Append

    # -------------------------
    # 2. TEST SSH CONNECTION
    # -------------------------
    # Force PowerShell to treat SSH output as UTF-8
    $outputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
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
            [switch]$successOnly
        )

        # Run the SSH command
        $output = ssh $piHost $sshCommand 2>&1
        # Ensure output is a single string before splitting
        if ($output -is [System.Array]) {
            $output = $output -join "`n"
        }
        $output = $output -split "\r?\n"
        $output = @($output | ForEach-Object { $_.TrimStart() })

        $success = $LASTEXITCODE -eq 0

        # Log success or failure
        if ($success) {
            "{$taskName}: successful" | Out-File $logPath -Append
        }
        else {
            "{$taskName}: failed" | Out-File $logPath -Append
            "ERROR: $($output[0])`n" | Out-File $logPath -Append
        }

        # Log normal output (single or multi-line)
        if ($success -and -not $successOnly) {

            $label = $outputLabel
            if (-not $label) { $label = $taskName }

            if ($output.Count -gt 1) {
                "{$label}:" | Out-File $logPath -Append
                $indented = $output | ForEach-Object { "    $_" }
                ($indented -join "`n") | Out-File $logPath -Append
                "" | Out-File $logPath -Append
            }
            else {
                "{$label}: $($output[0])`n" | Out-File $logPath -Append
            }
        }

        # Return structured object
        return [PSCustomObject]@{
            Success = $success
            Output  = $output
            Error   = if ($success) { $null } else { $output[0] }
        }
    }

    # -------------------------
    # 4. FUNCTION TO PARSE APT UPGRADE SUMMARY
    # -------------------------

    function Parse-AptSummary {
    param(
        [string[]]$keys,
        [string[]]$output
    )

    $result = @{}
    $errors = @()

    foreach ($key in $keys) {

        $keyLower = $key.ToLower()

        # Find the header line (first match only)
        $header = ($output | Where-Object { $_.ToLower().Contains($keyLower) }) | Select-Object -First 1

        if (-not $header) {
            $errors += "No match found for '$key'"
            $result[$key] = $null
            continue
        }

        $index = $output.IndexOf($header)

        # If header is last line → error
        if ($index -ge ($output.Count - 1)) {
            $errors += "No value found after header '$key'"
            $result[$key] = $null
            continue
        }

        # Collect all lines after header until:
        # - blank line
        # - OR next header-like line (contains ':')
        $lines = @()
        for ($i = $index + 1; $i -lt $output.Count; $i++) {

            $line = $output[$i].Trim()

            # Stop at blank line
            if ([string]::IsNullOrWhiteSpace($line)) { break }

            # Stop at next header (e.g., "Summary:")
            if ($line -match "^\S.*:$") { break }

            # Split the line into individual package names
            #$tokens = $line -split "\s+" | Where-Object { $_ -ne "" }
            #$lines += $tokens
            $lines += $line
        }

        if ($lines.Count -eq 0) {
            $errors += "Empty value found for '$key'"
            $result[$key] = $null
            continue
        }


        # Join multiple lines into a single comma-separated line
        # but always store as an array so Write-Summary prints it as a block
        if ($lines.Count -gt 1) {
            $result[$key] = @(($lines -join ", "))
        }
        else {
            $result[$key] = @($lines[0])
        }
    }

    # Convert keys to Title Case with spaces preserved
    $final = @{}
    foreach ($k in $result.Keys) {
        $title = ($k -split " " | ForEach-Object {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }) -join " "
        $final[$title] = $result[$k]
    }

    $final["Errors"] = $errors

    return [PSCustomObject]$final
}

    # -------------------------
    # 5. FUNCTION TO WRITE SUMMARY OBJECT TO LOG
    # -------------------------

    function Write-Summary {
        param(
            [pscustomobject]$summaryObject
        )

        foreach ($property in $summaryObject.PSObject.Properties) {

            if ($property.Name -eq "Errors") { continue }

            $label = $property.Name
            $value = $property.Value

            # Multi-line value (array)
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                "{$label}:" | Out-File $logPath -Append
                $value | ForEach-Object { "    $_" | Out-File $logPath -Append }
                continue
            }

            # Single-line value
            if ($null -ne $value) {
                "{$label}: $value" | Out-File $logPath -Append
            }
            else {
                "{$label}: <no value>" | Out-File $logPath -Append
            }
        }

        # Print errors if any
        if ($summaryObject.Errors -and $summaryObject.Errors.Count -gt 0) {
            "Summary extraction errors:" | Out-File $logPath -Append
            foreach ($err in $summaryObject.Errors) {
                "    $err" | Out-File $logPath -Append
            }
        }
}

    # -------------------------
    # 6. LOOP 1: MAINTENANCE REPORT
    # -------------------------
    "----------`n MAINTENANCE REPORT `n----------"  | Out-File $logPath -Append

    Run-SSH -taskName "Wipe logs" -sshCommand "sudo rm -rf /var/log/*" -SuccessOnly
    Run-SSH -taskName "Check disk space" -outputLabel "Disk space" -sshCommand "df -h /"
    Run-SSH -taskName "Check uptime" -outputLabel "Uptime" -sshCommand "uptime -p"
    Run-SSH -taskName "Check temperature" -outputLabel "Temperature" -sshCommand "vcgencmd measure_temp"
    Run-SSH -taskName "Check throttling" -outputLabel "Throttling" -sshCommand "vcgencmd get_throttled"
    Run-SSH -taskName "Check Pi-hole status" -outputLabel "Pi-hole status" -sshCommand "pihole status"
    
    # -------------------------
    # 7. LOOP 2: OS UPDATES REPORT
    # -------------------------
    "----------`n OS UPDATES REPORT `n----------"  | Out-File $logPath -Append

    Run-SSH -taskName "Check for package updates" -outputLabel "Number of package updates available" -sshCommand "apt list --upgradeable 2>/dev/null | wc -l"
    # Run the upgrade command, but don't log the full raw output
    $upgradeResult = Run-SSH -taskName "Package upgrades" -sshCommand "sudo apt upgrade" -successOnly
    # Parse the summary from the raw output
    $upgradeSummary = Parse-AptSummary -keys @("summary","not upgrading") -output $upgradeResult.Output
    # Write the summary in your existing style
    Write-Summary $upgradeSummary

    # -------------------------
    # 8. LOOP 3: PI-HOLE UPDATES REPORT
    # -------------------------
    "----------`n PI-HOLE UPDATES REPORT `n----------"  | Out-File $logPath -Append

    Run-SSH -taskName "Check for Pi-hole updates" -outputLabel "Pi-hole versions" -sshCommand "pihole -v"
    Run-SSH -taskName "Pi-hole updates" -sshCommand "sudo pihole -up" -successOnly

    # -------------------------
    # 9. REBOOT
    # -------------------------
    "----------`n RASPBERRY-PI REBOOT `n----------"  | Out-File $logPath -Append  

   # Run-SSH -taskName "Rebooting Raspberry Pi" -sshCommand "sudo reboot" -successOnly

    # -------------------------
    # 10. FINAL SUMMARY AND RUNTIME CALCULATION
    # -------------------------
    "----------`n FINAL SUMMARY `n----------"  | Out-File $logPath -Append

    # Calculate total runtime
    $endTime = Get-Date
    $duration = $endTime - $startTime
    "Automatic update completed: $timestamp`nTotal runtime: $duration`n(see Raspberry Pi logs)" | Out-File $logPath -Append