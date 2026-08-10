<#
Script for Application installation/uninstallation
v1.3
Date: 10/Aug/2026
By: Array IT Support

Install cmd:
.\NodeJS.ps1 -Action "Install" -AppName "NodeJS" -BinaryPath ".\node-v26.4.0-x64.msi" -UninstallRegistryPath "C:\Program Files\nodejs\node.exe"

Uninstall cmd:
.\NodeJS.ps1 -Action "Uninstall" -AppName "NodeJS" -BinaryPath "{16ACB226-F825-4982-A438-4E2A4D52BC44}" -UninstallRegistryPath "C:\Program Files\nodejs\node.exe"
#>

param (
    [string]$Action,
    [string]$AppName,
    [string]$BinaryPath,
    [string]$UninstallRegistryPath,
    [string]$LogFilePath = "C:\ProgramData\ArrayIntuneApps\NodeJSV2640Log.txt"
)

# =========================================================
# Logging
# =========================================================

function Log-Message {
    param (
        [string]$Message
    )

    $LogFolder = Split-Path $LogFilePath -Parent

    if (-not (Test-Path $LogFolder)) {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $LogFilePath)) {
        New-Item -Path $LogFilePath -ItemType File -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp - $Message"

    Write-Output $LogEntry
    Add-Content -Path $LogFilePath -Value $LogEntry
}

# =========================================================
# Detect Installed Corporate NodeJS
# =========================================================

function Is-AppInstalled {
    param (
        [string]$RegistryPath
    )

    try {

        $Installed =
            (Test-Path $RegistryPath) -and
            ((Get-Item $RegistryPath).VersionInfo.ProductVersion -like "26.4.0*")

        return $Installed
    }
    catch {
        return $false
    }
}

# =========================================================
# Remove NodeJS from all user profiles
# =========================================================

function Remove-UserScopeNode {

    Log-Message "Starting user-scope NodeJS cleanup"

    #
    # Kill running processes
    #

    foreach ($ProcessName in @("node", "npm", "npx")) {

        try {

            Get-Process $ProcessName -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue

            Log-Message "Stopped process $ProcessName"
        }
        catch {}
    }

    #
    # Enumerate local profiles
    #

    $Profiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notin @(
                "Public",
                "Default",
                "Default User",
                "All Users"
            )
        }

    foreach ($Profile in $Profiles) {

        Log-Message "Processing profile: $($Profile.Name)"

        #
        # Remove WinGet Node packages
        #

        $WinGetPackagesPath = Join-Path `
            $Profile.FullName `
            "AppData\Local\Microsoft\WinGet\Packages"

        if (Test-Path $WinGetPackagesPath) {

            $NodeFolders =
                Get-ChildItem `
                    -Path $WinGetPackagesPath `
                    -Directory `
                    -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match "NodeJS"
                }

            foreach ($Folder in $NodeFolders) {

                try {

                    Log-Message "Removing $($Folder.FullName)"

                    Remove-Item `
                        -Path $Folder.FullName `
                        -Recurse `
                        -Force `
                        -ErrorAction Stop

                    Log-Message "Removed $($Folder.Name)"
                }
                catch {

                    Log-Message "Failed removing $($Folder.FullName)"
                    Log-Message $_.Exception.Message
                }
            }
        }

        #
        # Remove npm folders
        #

        $FoldersToRemove = @(
            "$($Profile.FullName)\AppData\Roaming\npm",
            "$($Profile.FullName)\AppData\Roaming\npm-cache",
            "$($Profile.FullName)\AppData\Local\npm-cache"
        )

        foreach ($Folder in $FoldersToRemove) {

            try {

                if (Test-Path $Folder) {

                    Log-Message "Removing $Folder"

                    Remove-Item `
                        -Path $Folder `
                        -Recurse `
                        -Force `
                        -ErrorAction Stop
                }
            }
            catch {

                Log-Message "Failed removing $Folder"
            }
        }
    }

    #
    # Cleanup PATH values for loaded profiles
    #

    Log-Message "Cleaning PATH variables"

    $UserHives =
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSChildName -match "^S-\d-\d+-.+"
        }

    foreach ($Hive in $UserHives) {

        try {

            $EnvKey = "$($Hive.Name)\Environment"

            $CurrentPath =
                (Get-ItemProperty `
                    -Path $EnvKey `
                    -Name Path `
                    -ErrorAction SilentlyContinue).Path

            if (:IsNullOrWhiteSpace($CurrentPath)) {
                continue
            }

            $NewPath =
                ($CurrentPath -split ';' |
                    Where-Object {

                        $_ -notmatch 'OpenJS\.NodeJS' -and
                        $_ -notmatch 'WinGet\\Packages' -and
                        $_ -notmatch '\\npm'

                    }) -join ';'

            if ($NewPath -ne $CurrentPath) {

                Set-ItemProperty `
                    -Path $EnvKey `
                    -Name Path `
                    -Value $NewPath `
                    -ErrorAction SilentlyContinue

                Log-Message "Updated PATH for $($Hive.PSChildName)"
            }
        }
        catch {

            Log-Message "Unable to update PATH for $($Hive.PSChildName)"
        }
    }

    #
    # Verification
    #

    try {

        $RemainingNode =
            Get-ChildItem `
                -Path "C:\Users" `
                -Filter "node.exe" `
                -Recurse `
                -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -match "WinGet\\Packages"
            }

        if ($RemainingNode) {

            foreach ($File in $RemainingNode) {
                Log-Message "WARNING - Remaining node.exe: $($File.FullName)"
            }
        }
        else {

            Log-Message "No remaining user-scope NodeJS installations found"
        }
    }
    catch {}
}

# =========================================================
# Validation
# =========================================================

if (-not $Action) {
    Log-Message "ERROR: No action specified."
    exit 1
}

if (-not $BinaryPath) {
    Log-Message "ERROR: No binary path specified."
    exit 1
}

# =========================================================
# Main
# =========================================================

try {

    if ($Action -eq "Install") {

        if (Is-AppInstalled -RegistryPath $UninstallRegistryPath) {

            Log-Message "$AppName already installed. Skipping."

        }
        else {

            Log-Message "Starting installation of $AppName"

            Remove-UserScopeNode

            $MsiPath = (Resolve-Path $BinaryPath).Path

            $Process = Start-Process `
                -FilePath "msiexec.exe" `
                -ArgumentList "/i `"$MsiPath`" /qn /norestart" `
                -Wait `
                -PassThru `
                -NoNewWindow

            Log-Message "MSI Exit Code: $($Process.ExitCode)"

            if (Is-AppInstalled -RegistryPath $UninstallRegistryPath) {

                Log-Message "$AppName installation completed successfully."
            }
            else {

                Log-Message "ERROR: Installation failed."
                exit 1
            }
        }
    }
    elseif ($Action -eq "Uninstall") {

        Log-Message "Starting uninstallation of $AppName"

        Remove-UserScopeNode

        try {

            $Process = Start-Process `
                -FilePath "msiexec.exe" `
                -ArgumentList "/x $BinaryPath /qn /norestart" `
                -Wait `
                -PassThru `
                -NoNewWindow

            Log-Message "MSI Exit Code: $($Process.ExitCode)"
        }
        catch {

            Log-Message "MSI uninstall failed: $($_.Exception.Message)"
        }

        if (-not (Test-Path $UninstallRegistryPath)) {

            Log-Message "$AppName uninstallation completed successfully."
        }
        else {

            Log-Message "$AppName may still be installed."
        }
    }
    else {

        Log-Message "ERROR: Invalid action specified."
        exit 1
    }
}
catch {

    Log-Message "ERROR: $($_.Exception.Message)"
    exit 1
}

Log-Message "Script execution completed."