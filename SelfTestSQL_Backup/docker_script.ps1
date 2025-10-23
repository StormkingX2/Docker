# Load .env file
$envPath = ".\.env"
Get-Content $envPath | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Item -Path "Env:$name" -Value $value
    }
}

# Read variables from environment
$bakFolder = $env:BAK_FOLDER
$bakFileName = $env:BAK_FILENAME
$sqlContainerName = $env:SQL_CONTAINER_NAME
$sqlPassword = $env:SQL_PASSWORD
$sqlImage = $env:SQL_IMAGE
$dbName = [System.IO.Path]::GetFileNameWithoutExtension($bakFileName)

# Wait for .bak file
Write-Host "Waiting for $bakFileName in $bakFolder..."
while (-not (Test-Path "$bakFolder\$bakFileName")) {
    Start-Sleep -Seconds 5
}
Write-Host "$bakFileName found. Starting SQL Server container..."

# Start SQL Server container with Linux-compatible mount path
docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$sqlPassword" `
    -p 1433:1433 --name $sqlContainerName `
    -v "${bakFolder}:/var/opt/mssql/backup" -d $sqlImage


# Wait for SQL Server to be ready by checking container logs
Write-Host "Waiting for SQL Server to be ready..."
$ready = $false
$maxRetries = 20
$retryCount = 0

while (-not $ready -and $retryCount -lt $maxRetries) {
    $logs = docker logs $sqlContainerName 2>$null
    if ($logs -match "SQL Server is now ready for client connections") {
        Write-Host "SQL Server is ready."
        $ready = $true
        break
    }

    $retryCount++
    Start-Sleep -Seconds 5
}

if (-not $ready) {
    Write-Error "SQL Server did not become ready in time."
    exit 1
}


# Try structured output first
try {
    $logicalFiles = Invoke-Sqlcmd -ServerInstance "localhost" -Username "sa" -Password $sqlPassword `
        -Query "RESTORE FILELISTONLY FROM DISK = N'/var/opt/mssql/backup/$bakFileName'" `
        -TrustServerCertificate

    $dataLogicalName = ($logicalFiles | Where-Object { $_.Type -eq 'D' }).LogicalName
    $logLogicalName = ($logicalFiles | Where-Object { $_.Type -eq 'L' }).LogicalName
}
catch {
    Write-Warning "Invoke-Sqlcmd failed, falling back to text parsing..."

    $sqlOutput = sqlcmd -S localhost -U sa -P $sqlPassword `
        -Q "RESTORE FILELISTONLY FROM DISK = N'/var/opt/mssql/backup/$bakFileName'" `
        | Out-String

    $sqlOutput | Out-File "$bakFolder\filelist_output.txt"

    $logicalNames = $sqlOutput -split "`r`n" | Select-String -Pattern '^\s*(\S+)\s+.*\s+(PRIMARY|LOG)\s*$'

    if ($logicalNames.Count -lt 2) {
        Write-Error "Could not find both PRIMARY and LOG logical names in the backup file."
        return
    }

    $dataLogicalName = $logicalNames[0].Matches[0].Groups[1].Value
    $logLogicalName = $logicalNames[1].Matches[0].Groups[1].Value
}


# Restore the database using Linux paths
$sqlCmd = @"
RESTORE DATABASE [$dbName]
FROM DISK = N'/var/opt/mssql/backup/$bakFileName'
WITH MOVE '$dataLogicalName' TO '/var/opt/mssql/data/$dbName.mdf',
     MOVE '$logLogicalName' TO '/var/opt/mssql/log/$dbName.ldf',
     REPLACE
"@

Write-Host "Restoring database as $dbName..."
sqlcmd -S localhost -U sa -P $sqlPassword -Q $sqlCmd

Write-Host "Database [$dbName] restored successfully."
