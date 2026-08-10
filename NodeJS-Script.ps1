<#
Script for Application installation/uninstallation
v1.0
Date: 15/April/2026
By: Array IT support

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

# Function to log messages
function Log-Message {
    param (
        [string]$Message
    )

    if(-not (test-path -Path $LogFilePath)){
        new-item $LogFilePath -ItemType File -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logMessage = "$timestamp - $Message"

    Write-Output $logMessage
    Add-Content -Path $LogFilePath -Value $logMessage -Force
}

# Function to check if the application is installed by looking at node.exe version
function Is-AppInstalled {
    param (
        [string]$RegistryPath
    )

    $installed = ((test-path $RegistryPath) -and ((Get-Item $RegistryPath).VersionInfo.ProductVersion -like "26.4.0*"))

    return $installed
}

# Validate parameters
if (-not $Action) {
    Log-Message "ERROR: No action specified (Install/Uninstall)."
    exit 1
}

if (-not $BinaryPath) {
    Log-Message "ERROR: No binary path specified."
    exit 1
}

# Process based on action
try {
    if ($Action -eq "Install") {

        $installed = Is-AppInstalled -RegistryPath $UninstallRegistryPath

        if ($installed) {
            Log-Message "$AppName is already installed. Skipping installation."
        }
        else {
            Log-Message "Starting installation of $AppName."

            Start-Process -FilePath "msiexec.exe" `
                -ArgumentList "/i `"$BinaryPath`" /qn /norestart" `
                -Wait -NoNewWindow

            if (Is-AppInstalled -RegistryPath $UninstallRegistryPath) {
                Log-Message "$AppName Installation completed successfully."
            }
            else {
                Log-Message "ERROR: $AppName installation failed."
                exit 1
            }
        }
    }
    elseif ($Action -eq "Uninstall") {

        $installed = Is-AppInstalled -RegistryPath $UninstallRegistryPath

        if (-not $installed) {
            Log-Message "ERROR: $AppName is not installed. Skipping uninstallation."
            exit 1
        }
        else {
            Log-Message "Starting uninstallation of $AppName."

            Start-Process -FilePath "msiexec.exe" `
                -ArgumentList "/x $BinaryPath /qn /norestart" `
                -Wait -NoNewWindow

            if (-not (test-path $UninstallRegistryPath)) {
                Log-Message "$AppName uninstallation completed successfully."
            }
            else {
                Log-Message "ERROR: $AppName uninstallation failed."
                exit 1
            }
        }
    }
    else {
        Log-Message "ERROR: Invalid action specified. Use 'Install' or 'Uninstall'."
        exit 1
    }
}
catch {
    Log-Message "ERROR: An error occurred: $_"
    exit 1
}

Log-Message "Script execution completed."