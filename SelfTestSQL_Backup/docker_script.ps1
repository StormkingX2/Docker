# Load environment variables from .env file
$envPath = ".\.env"
Get-Content $envPath | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Item -Path "Env:$name" -Value $value
    }
}

# Validate required tools
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "❌ Docker is not installed or not available in PATH."
    exit 1
}

if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "🔄 SqlServer module not found. Attempting to install..."
    try {
        Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber
    }
    catch {
        Write-Error "❌ Failed to install SqlServer module."
        exit 1
    }
}

# Function to generate a secure SQL Server password
function New-SqlPassword {
    param ([int]$Length = 16)

    if ($Length -lt 8 -or $Length -gt 32) {
        throw "Password length must be between 8 and 32 characters."
    }

    $upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $lower = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $digits = '0123456789'.ToCharArray()
    $special = '!@#$%^&*'.ToCharArray()
    $all = $upper + $lower + $digits + $special

    # Ensure each category is represented
    $required = @(
        Get-Random -InputObject $upper
        Get-Random -InputObject $lower
        Get-Random -InputObject $digits
        Get-Random -InputObject $special
    )

    # Fill the rest with random characters from all sets
    $remaining = $Length - $required.Count
    $rest = (1..$remaining | ForEach-Object { Get-Random -InputObject $all })

    $password = -join ($required + $rest | Sort-Object { Get-Random })

    # Show password for troubleshooting
    # Write-Host "`n🔐 Generated SA password: $password"
    # Write-Host "Length: $($password.Length)"
    # Write-Host "Contains uppercase: $($password -match '[A-Z]')"
    # Write-Host "Contains lowercase: $($password -match '[a-z]')"
    # Write-Host "Contains digit: $($password -match '\d')"
    # Write-Host "Contains special: $($password -match '[!@#$%^&*]')"

    return $password
}



# Load environment variables
$bakFolder = $env:BAK_FOLDER
$sqlImage = $env:SQL_IMAGE
$webhookUrl = $env:DISCORD_WEBHOOK
$basePort = 1433

# Generate a secure password
$sqlPassword = New-SqlPassword -Length 16


# Get all .bak files in the folder
$bakFiles = Get-ChildItem -Path $bakFolder -Filter *.bak
if ($bakFiles.Count -eq 0) {
    Write-Error "No .bak files found in $bakFolder"
    exit 1
}

# Prepare list to hold connection strings
$connectionStrings = @()
$index = 0

# Loop through each .bak file
foreach ($bakFile in $bakFiles) 
{
    $bakFileName = $bakFile.Name
    $dbName = [System.IO.Path]::GetFileNameWithoutExtension($bakFileName)
    $containerName = "sql_restore_$dbName"
    $port = $basePort + $index

    Write-Host "`n🚀 Starting container [$containerName] for $bakFileName on port $port..."

    # Start Docker container with SQL Server
    docker run `
        -e "ACCEPT_EULA=Y" `
        -e "SA_PASSWORD=$sqlPassword" `
        -p "$port`:1433" `
        --name "$containerName" `
        -v "${bakFolder}:/var/opt/mssql/backup" `
        -d $sqlImage | Out-Null

    # Wait for SQL Server to be ready
    $ready = $false
    $maxRetries = 20
    $retryCount = 0
    while (-not $ready -and $retryCount -lt $maxRetries) 
    {
        $logs = docker logs $containerName 2>$null
        if ($logs -match "SQL Server is now ready for client connections") 
        {
            Write-Host "✅ SQL Server in [$containerName] is ready."
            $ready = $true
            break
        }
        $retryCount++
        Start-Sleep -Seconds 5
    }

    if (-not $ready) 
    {
        Write-Error "❌ SQL Server in [$containerName] did not become ready in time."
        continue
    }

    # Extract logical file names from .bak
    try 
    {
        $logicalFiles = Invoke-Sqlcmd -ServerInstance "localhost,$port" -Username "sa" -Password $sqlPassword `
            -Query "RESTORE FILELISTONLY FROM DISK = N'/var/opt/mssql/backup/$bakFileName'" `
            -TrustServerCertificate

        $dataLogicalName = ($logicalFiles | Where-Object { $_.Type -eq 'D' }).LogicalName
        $logLogicalName = ($logicalFiles | Where-Object { $_.Type -eq 'L' }).LogicalName
    }
    catch 
    {
        Write-Error "❌ Failed to extract logical file names for $bakFileName"
        continue
    }

    # Restore the database
    $sqlCmd = @"
RESTORE DATABASE [$dbName]
FROM DISK = N'/var/opt/mssql/backup/$bakFileName'
WITH MOVE '$dataLogicalName' TO '/var/opt/mssql/data/${dbName}.mdf',
     MOVE '$logLogicalName' TO '/var/opt/mssql/log/${dbName}.ldf',
     REPLACE
"@

    Write-Host "🔧 Restoring [$dbName] in container [$containerName]..."
    Invoke-Sqlcmd -ServerInstance "localhost,$port" -Username "sa" -Password $sqlPassword `
        -Query $sqlCmd -TrustServerCertificate

    Write-Host "✅ Database [$dbName] restored successfully on port [$port]."

    # Add connection string to list
    $connectionStrings += "[$containerName] Server=localhost,$port;Database=$dbName;User Id=sa;Password=$sqlPassword;"
    $index++
}

# Log connection string to file for troubleshooting
$logPath = Join-Path $bakFolder "connection_strings.txt"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content $logPath "`n===== Run at $timestamp ====="
foreach ($line in $connectionStrings) 
{
    Add-Content $logPath $line
}


# Send connection strings to Discord
.\Send-DiscordMessage.ps1 -ConnectionStrings $connectionStrings -WebhookUrl $webhookUrl

# Generate restore status dashboard
.\Generate-RestoreDashboard.ps1