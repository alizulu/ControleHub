<#
.SYNOPSIS
    Collects all Windows Disk information and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of SQL Servers (retrieved from a central monitoring database), 
    connects to each instance, and gathers information.
    The results are aggregated and stored in a central staging table.

.NOTES
    Author:  Ali Zulu
    Version: 1.0
    Warranty: Provided AS-IS
#>
cls

$startDTM = Get-Date

$CurentMonth = (Get-Date).ToString('MMMM')
$CurentYear = (Get-Date).Year

Clear-Host
Write-Host ""

Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host " CONTROLE WINDOWS DISK COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurentMonth $CurentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects disk capacity from all active servers" -ForegroundColor Cyan
Write-Host " Warranty      : Provided AS-IS" -ForegroundColor DarkGray
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "Start Time     : $startDTM"
Write-Host ""

Write-Host ""



#SQL Server Configuration values
$MonitorServer = "SQL1"
$MonitorDatabase = "ControleHub"
$MonitorconnectionString = "Server=$MonitorServer;Database=$MonitorDatabase;Integrated Security=True"



### SQL Account Credentials
#$Username = "YourUsername"
#$Password = "YourSecurePassword"

### Updated Connection String for SQL Authentication
#$MonitorconnectionString = "Server=$MonitorServer;Database=$MonitorDatabase;User ID=$Username;Password=$Password;"


function Invoke-SqlQuery {
    <#
        .SYNOPSIS
            Executes a SQL query and returns results as a DataTable.

        .PARAMETER ServerInstance
            SQL Server instance name (legacy mode).

        .PARAMETER Database
            Target database name (legacy mode).

        .PARAMETER ConnectionString
            Full SQL connection string (/ advanced mode).

        .PARAMETER Query
            SQL query to execute.

        .PARAMETER QueryTimeout
            Optional query timeout in seconds. Default is 30.
    #>

    [CmdletBinding(DefaultParameterSetName = "ServerMode")]
    param(

        # --- Legacy Mode ---
        [Parameter(Mandatory, ParameterSetName = "ServerMode")]
        [string]$ServerInstance,

        [Parameter(Mandatory, ParameterSetName = "ServerMode")]
        [string]$Database,

        # --- Connection String Mode ---
        [Parameter(Mandatory, ParameterSetName = "ConnectionStringMode")]
        [string]$ConnectionString,

        # --- Common ---
        [Parameter(Mandatory)]
        [string]$Query,
        
        [hashtable]$SqlParameters,

        [switch]$NonQuery,

        [int]$QueryTimeout = 30
    )

    # ---------------------------------------------------
    # Build Connection String
    # ---------------------------------------------------

    if ($PSCmdlet.ParameterSetName -eq "ServerMode") {
        $connectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=True"
    }
    else {
        $connectionString = $ConnectionString
    }

    # ---------------------------------------------------
    # Create SQL Objects
    # ---------------------------------------------------

    $conn = New-Object System.Data.SqlClient.SqlConnection $connectionString
    $cmd  = New-Object System.Data.SqlClient.SqlCommand $Query, $conn
    $cmd.CommandTimeout = $QueryTimeout

    # Add parameters if supplied
    if ($SqlParameters) {
        foreach ($key in $SqlParameters.Keys) {
            $null = $cmd.Parameters.AddWithValue("@$key", $SqlParameters[$key])
        }
    }

    # ---------------------------------------------------
    # Execute
    # ---------------------------------------------------

    try {
        $conn.Open()

        if ($NonQuery) {
            [void]$cmd.ExecuteNonQuery()
            return
        }

        $dataTable = New-Object System.Data.DataTable
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        [void]$adapter.Fill($dataTable)

        return $dataTable
    }
    catch {
        if ($PSCmdlet.ParameterSetName -eq "ServerMode") {
            throw "Invoke-SqlQuery failed on [$ServerInstance].[$Database] : $($_.Exception.Message)"
        }
        else {
            throw "Invoke-SqlQuery failed using ConnectionString : $($_.Exception.Message)"
        }
    }
    finally {
        if ($conn.State -ne 'Closed') {
            $conn.Close()
        }
        $conn.Dispose()
    }
}



Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "TRUNCATE TABLE dbo.Disks_Temp" -NonQuery

function Get-DiskInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )


    try {
        
        $cimOptions = New-CimSessionOption -Protocol Dcom
        $session = New-CimSession -ComputerName $ServerName -SessionOption $cimOptions -ErrorAction Stop

        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -CimSession $session -Filter "DriveType = 3"

        $diskSummary = @()

foreach ($disk in $disks) {

    $drive        = "$($disk.DeviceID)\"
    $label        = $disk.VolumeName
    $totalSizeMB  = [math]::Round($disk.Size / 1MB, 2)
    $freeSpaceMB  = [math]::Round($disk.FreeSpace / 1MB, 2)
    $freePct      = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)

    $diskSummary += [PSCustomObject]@{
        Drive       = $drive
        Label       = $label
        FreePct     = $freePct
    }

    
    $sql = @"
INSERT INTO dbo.Disks_Temp
(
    ServerName,
    Drive,
    VolumeName,
    TotalSize,
    FreeSpace
)
VALUES
(
    '$ServerName',
    '$drive',
    '$label',
    $totalSizeMB,
    $freeSpaceMB
)
"@
Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $sql

}

    }
    catch {
        Write-Error "[$ServerName] Connection failed: $($_.Exception.Message)"
    }
}


$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"


Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan

foreach ($row in $result) {

    $ServerName = $row.ServerName

    Get-DiskInformation -ServerName $ServerName 
	Write-Host "Collecting Disk Info: [$ServerName]" -ForegroundColor Green

        
  
}

	Write-Host " " -ForegroundColor Green


$endDTM = (Get-Date)
Write-Host ""
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "Disk collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow


