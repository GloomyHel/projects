
    
    # -------------------------
    # FUNCTION TO RUN SSH COMMANDS AND LOG OUTPUT
    # -------------------------
    function Invoke-SshCommand {
        <# 
        .SYNOPSIS
            Runs an SSH command on the Raspberry Pi and logs the Output.
        .PARAMETER TaskName
            A descriptive name for the task being performed (e.g., "Check disk space").
        .PARAMETER SshCommand
            The actual command to run on the Raspberry Pi (e.g., "df -h /").
        .PARAMETER OutputLabel
            An optional Label to use when logging the Output. If not provided, TaskName will be used.
        .PARAMETER SuccessOnly
            If specified, only logs the Success/failure of the command, not the full Output.
        #>
        [CmdletBinding()]
            param(
                [Parameter(Mandatory=$true)]
                [string]$TaskName,

                [Parameter(Mandatory=$true)]
                [string]$SshCommand,

                [Parameter(Mandatory=$true)]
                [string]$PiHost,

                [Parameter(Mandatory=$true)]
                [string]$LogPath,

                [string]$OutputLabel,
                [switch]$SuccessOnly
            )


        Write-Host "DEBUG: SshCommand raw = [$SshCommand]"
        Write-Host "DEBUG: PiHost raw = [$PiHost]"

        # Run the SSH command
        $Output = ssh "$PiHost" "$SshCommand" 2>&1

        Write-Host "RAW SSH OUTPUT:"
        Write-Host ($Output | Format-List | Out-String)


        # Normalize to array
        if ($Output -isnot [System.Array]) {
            $Output = @($Output)
        }

        # Convert everything to string and trim
        $Output = $Output | ForEach-Object { $_.ToString().Trim() }

        $Success = $LASTEXITCODE -eq 0

        # Log Success or failure
        if ($Success) {
            "{$TaskName}: successful" | Out-File $LogPath -Append
        }
        else {
            "{$TaskName}: failed" | Out-File $LogPath -Append
            "ERROR: $($Output[0])`n" | Out-File $LogPath -Append
        }

        # Log normal Output (single or multi-line)
        if ($Success -and -not $SuccessOnly) {

            $Label = $OutputLabel
            if (-not $Label) { $Label = $TaskName }

            if ($Output.Count -gt 1) {
                "{$Label}:" | Out-File $LogPath -Append
                $Indented = $Output | ForEach-Object { "    $_" }
                ($Indented -join "`n") | Out-File $LogPath -Append
                "" | Out-File $LogPath -Append
            }
            else {
                "{$Label}: $($Output[0])`n" | Out-File $LogPath -Append
            }
        }
        # Return structured object
        return [PSCustomObject]@{
            Success = $Success
            Output  = $Output
            Error   = if ($Success) { $null } else { $Output[0] }
        }
    }


    # -------------------------
    # FUNCTION TO PARSE APT UPGRADE SUMMARY
    # -------------------------
   function ConvertFrom-AptSummary {
    <#
    .SYNOPSIS
        Generates a stable summary of upgradeable packages using
        `apt list --upgradeable` output.
    .PARAMETER Output
        Raw output from `apt list --upgradeable`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Output
    )

    $packages = $Output |
        Where-Object { $_ -match "/" -and $_ -notmatch "Listing..." } |
        ForEach-Object { ($_ -split " ")[0] }  # package name only

    $count = $packages.Count

    return [PSCustomObject]@{
        "Not Upgrading" = $packages
        "Summary"       = @(
            "Upgrading: 0",
            "Installing: 0",
            "Removing: 0",
            "Not Upgrading: $count"
        )
        "Errors"        = @()
    }
}

    # -------------------------
    # 5. FUNCTION TO WRITE SUMMARY OBJECT TO LOG
    # -------------------------

    function Write-LogSummary {
        <#
        .SYNOPSIS
            Writes a structured summary object to the log file in a readable format.
        .PARAMETER SummaryObject
            The summary object to be written to the log file.
        #>
        param(
            [Parameter(Mandatory=$true)]
            [pscustomobject]$SummaryObject,

            [Parameter(Mandatory=$true)]
            [string]$LogPath
        )

        foreach ($property in $SummaryObject.PSObject.Properties) {

            if ($property.Name -eq "Errors") { continue }

            $Label = $property.Name
            $Value = $property.Value

            # Multi-line Value (array)
            if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                "{$Label}:" | Out-File $LogPath -Append
                $Value | ForEach-Object { "    $_" | Out-File $LogPath -Append }
                continue
            }

            # Single-line Value
            if ($null -ne $Value) {
                "{$Label}: $Value" | Out-File $LogPath -Append
            }
            else {
                "{$Label}: <no Value>" | Out-File $LogPath -Append
            }
        }

        # Print errors if any
        if ($SummaryObject.Errors -and $SummaryObject.Errors.Count -gt 0) {
            "Summary extraction errors:" | Out-File $LogPath -Append
            foreach ($err in $SummaryObject.Errors) {
                "    $err" | Out-File $LogPath -Append
            }
        }
}

Export-ModuleMember -Function Invoke-SshCommand, ConvertFrom-AptSummary, Write-LogSummary