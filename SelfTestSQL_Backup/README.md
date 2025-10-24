# 🛠 SQL Server Restore Automation Pipeline

**Version:** 1.0  
**Date:** October 2025  
**Purpose:** Automate the restoration of SQL Server `.bak` files into isolated Docker containers for testing and validation.


https://github.com/user-attachments/assets/5f5455c6-98dc-4d17-8965-6246a430af0c

---

## 📦 Overview

This system restores multiple SQL Server backups (`.bak` files) into individual Docker containers using PowerShell. Each container hosts a separate SQL Server instance, ensuring isolation and easy cleanup. The process includes:

- Secure password generation
- Container orchestration
- Database restoration
- Discord notifications
- Dashboard generation for audit and tracking

---

## 🧱 Components

### 1. `.env` File

Stores environment variables:

```.env
BAK_FOLDER=D:\Backups
SQL_IMAGE=mcr.microsoft.com/mssql/server:2019-latest
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
```

## 2. `Restore-SqlBackups.ps1`

Main script that performs the restore workflow:

- Loads environment variables from `.env`
- Generates a secure SA password
- Iterates over `.bak` files in the backup folder
- Starts a Docker container per file
- Restores the database using `Invoke-Sqlcmd`
- Sends connection strings to Discord
- Appends restore results to a dashboard

---

## 3. `Send-DiscordMessage.ps1`

Sends a formatted message to a Discord webhook with connection strings for each restored database.

Usage:

```powershell
.\Send-DiscordMessage.ps1 -ConnectionStrings $connectionStrings -WebhookUrl $webhookUrl
```

## 4. `Generate-RestoreDashboard.ps1`

Generates a CSV dashboard that summarizes the status of each SQL Server restore operation. This script is typically run **after** all containers are created and the Discord message has been sent.

### 🔍 What It Does

- Scans all `.bak` files in the backup folder
- Checks if a corresponding Docker container exists and is running
- Parses container logs to determine if the restore was successful
- Extracts error messages if the restore failed
- Appends results to a CSV file (`restore_dashboard.csv`) with the following columns:

| Backup File | Container Name     | Port | Database Name | Status     | Timestamp           | Observations                     |
|-------------|--------------------|------|----------------|------------|---------------------|----------------------------------|
| test1.bak   | sql_restore_test1  | 1433 | test1          | ✅ Restored | 2025-10-23 22:00:00 | Restore completed successfully   |
| test2.bak   | sql_restore_test2  | 1434 | test2          | ❌ Failed   | 2025-10-23 22:01:00 | Restore failed: Msg 3154, Level 16 |

### 🧠 Status Logic

- `✅ Restored`: SQL Server is ready and restore logs confirm success
- `❌ Failed`: SQL Server is ready but logs contain restore errors
- `⚠️ Running`: SQL Server is running but restore status is unclear
- `🛑 Stopped`: Container exists but is not running
- `❌ Missing`: No container found for the `.bak` file

### 📦 Usage

Run this script after the restore and Discord notification steps:

```powershell
.\Generate-RestoreDashboard.ps1
```

## 🔐 Password Generation

The `New-SqlPassword` function ensures that the SA password meets SQL Server's complexity requirements. It is automatically generated during the restore process and can optionally be logged for troubleshooting.

### Features

- Length: 16 characters
- Includes:
  - Uppercase letters
  - Lowercase letters
  - Digits
  - Special characters
- Can be written to a file for debugging (optional)

---

## 🐳 Docker Container Strategy

Each `.bak` file is restored into a separate Docker container to ensure isolation and simplify testing.

### Container Configuration

- **Name:** `sql_restore_<dbname>`
- **Port:** `1433 + index` (e.g., 1433, 1434, 1435…)
- **Volume Mount:** `-v $bakFolder:/var/opt/mssql/backup`
- **Image:** `mcr.microsoft.com/mssql/server:2019-latest`

### Benefits

- Full isolation between databases
- Easy cleanup by removing containers
- Parallel testing and validation
- Clear mapping between backup files and containers

---

## 📣 Discord Notification

After all restores are completed, a message is sent to a Discord channel containing the connection strings for each restored database.

### Usage

```powershell
.\Send-DiscordMessage.ps1 -ConnectionStrings $connectionStrings -WebhookUrl $webhookUrl
```

## 📊 Dashboard Generation

After the Discord message is sent, the dashboard script runs to generate a CSV report summarizing the restore status of each `.bak` file.

### Script

```powershell
.\Generate-RestoreDashboard.ps1
```

### 🔍 Dashboard Analysis Details

The `Generate-RestoreDashboard.ps1` script performs a post-restore audit by analyzing each `.bak` file and its corresponding Docker container. It appends results to a CSV file (`restore_dashboard.csv`) with detailed status and observations.

#### Key Functions

- ✅ Scans all `.bak` files in the backup folder
- 🐳 Checks if a corresponding Docker container exists and is running
- 📄 Parses container logs to determine if SQL Server is ready
- 🧠 Detects whether the database restore was successful or failed
- 🪵 Extracts error messages from logs if restore failed
- 📊 Appends results to a dashboard CSV with the following columns:
  - `Backup File`
  - `Container Name`
  - `Port`
  - `Database Name`
  - `Status`
  - `Timestamp`
  - `Observations`

#### Status Logic

- ✅ **Restored** — SQL Server is ready and restore logs confirm success
- ❌ **Failed** — SQL Server is ready but logs contain restore errors
- ⚠️ **Running** — SQL Server is running but restore status is unclear
- 🛑 **Stopped** — Container exists but is not running
- ❌ **Missing** — No container found for the `.bak` file

This script is typically run **after** the Discord notification step to ensure all containers are initialized and logs are available.

## 🧪 Testing & Validation

After the restore process completes, each SQL Server instance runs in its own Docker container and can be accessed using a standard connection string.

### Connection Format

```text
Server=localhost,<port>;Database=<dbname>;User Id=sa;Password=<password>;
```

Replace `port` and `dbname` with the values assigned during the restore. The SA password is generated automatically and can be logged or retrieved depending on your configuration.

### Validation Options

You can validate the restored databases using:

- SQL Server Management Studio (SSMS) — Connect using the container’s port and verify schema/data

- Azure Data Studio — Lightweight alternative for querying and inspecting databases

- PowerShell — Use Invoke-Sqlcmd to run automated checks or queries

- Custom scripts — Run schema comparison, data integrity checks, or test queries

## 🧹 Cleanup

After testing is complete, you can remove all Docker containers created during the restore process to free up system resources.

### Remove All Restore Containers

```powershell
docker rm -f $(docker ps -a -q --filter "name=sql_restore_")
```

This command forcefully stops and removes all containers whose names begin with sql_restore_.

> 💡 Tip: You can also add this as a cleanup step in your automation script if you want to automatically remove containers after validation.

---

## 📁 File Structure

```code
/SelfTestSQL_Backup/ 
│ 
├── .env 
├── Restore-SqlBackups.ps1 
├── Send-DiscordMessage.ps1 
├── Generate-RestoreDashboard.ps1 
├── connection_strings.txt 
└── restore_dashboard.csv
```
