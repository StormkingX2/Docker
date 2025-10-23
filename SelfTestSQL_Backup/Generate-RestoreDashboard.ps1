# Path to the folder containing your .bak files
$bakFolder = $env:BAK_FOLDER
if (-not $bakFolder) {
    Write-Error "❌ BAK_FOLDER environment variable is not set."
    exit 1
}

# Output CSV path
$csvPath = Join-Path $bakFolder "restore_dashboard.csv"

# Get all .bak files in the folder
$bakFiles = Get-ChildItem -Path $bakFolder -Filter *.bak
if ($bakFiles.Count -eq 0) {
    Write-Error "❌ No .bak files found in $bakFolder"
    exit 1
}

# Base port for container mapping
$basePort = 1433
$index = 0

foreach ($bakFile in $bakFiles) {
    $fileName = $bakFile.Name
    $dbName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $containerName = "sql_restore_$dbName"
    $port = $basePort + $index
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $status = "Unknown"
    $observation = ""

    # Check if container exists
    $containerExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $containerName }

    if ($containerExists) {
        # Check if container is running
        $isRunning = docker inspect -f "{{.State.Running}}" $containerName 2>$null
        if ($isRunning -eq "true") {
            # Get logs
            $logs = docker logs $containerName 2>$null

            if ($logs -match "SQL Server is now ready for client connections") {
                # Check for restore success
                if ($logs -match "RESTORE DATABASE successfully processed") {
                    $status = "✅ Restored"
                    $observation = "Restore completed successfully"
                }
                elseif ($logs -match "Msg \d+, Level \d+, State \d+") {
                    $status = "❌ Failed"
                    $errorLine = ($logs -split "`n" | Where-Object { $_ -match "Msg \d+, Level \d+, State \d+" })[0]
                    $observation = "Restore failed: $errorLine"
                }
                else {
                    $status = "⚠️ Running"
                    $observation = "SQL Server ready, but restore status unclear"
                }
            }
            else {
                $status = "⚠️ Running"
                $observation = "SQL Server not ready"
            }
        }
        else {
            $status = "🛑 Stopped"
            $observation = "Container exists but is not running"
        }
    }
    else {
        $status = "❌ Missing"
        $observation = "No container found for this backup"
    }

    # Create dashboard entry
    $entry = [PSCustomObject]@{
        "Backup File"     = $fileName
        "Container Name"  = $containerName
        "Port"            = $port
        "Database Name"   = $dbName
        "Status"          = $status
        "Timestamp"       = $timestamp
        "Observations"    = $observation
    }

    # Append to CSV
    $entry | Export-Csv -Path $csvPath -Append -NoTypeInformation -Encoding UTF8

    $index++
}

Write-Host "📊 Restore dashboard updated at: $csvPath"
