<#
.SYNOPSIS
    Collects SQL Server Database file usage and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of SQL Servers (retrieved from a central monitoring database), 
    connects to each instance, and calculates data/log file metrics (size, used space, growth settings).
    The results are aggregated and stored in a central staging table.
    It is designed to handle Always On Availability Groups by checking replica states before querying.


.NOTES
    Author:  Ali Zulu
    Version: 1.0
    Warranty: Provided AS-IS
#>
cls


$startDTM = Get-Date

$CurrentMonth = (Get-Date).ToString('MMMM')
$CurrentYear = (Get-Date).Year

Clear-Host
Write-Host ""

Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host " CONTROLE SQL DATAFILES COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurrentMonth $CurrentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects SQL Datafile informationfrom all active servers" -ForegroundColor Cyan
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


Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "TRUNCATE TABLE dbo.SQL_DataFiles_Temp" -NonQuery
    	
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

function New-SQLConnection {
    <#
        Creates a SQL connection to the target SQL Server instance.
        Used ONLY for reading instance metadata from remote servers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )
    
    $Connection = New-Object System.Data.SqlClient.SqlConnection
    $ConnectionB = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $ConnectionB["Data Source"] = $ServerName
    $ConnectionB["Database"] = "master"
    $ConnectionB["Trusted_Connection"] = "SSPI"
    $ConnectionB["Connection Timeout"] = 15
    $Connection.ConnectionString = $ConnectionB.ConnectionString
    
    return $Connection
}



function Get-SQLDataFilesInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )
    # Create connection to the TARGET server (not monitor server)
    $SQLConnection = New-SQLConnection -ServerName $ServerName
   try {
  
         # Open the connection
        $SQLConnection.Open()


        # Your existing SQL query here
        $SQLQuery = @"
                                ------------Get SQL DataFiles Information -------------
                                
  SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#FileSpace') IS NOT NULL
    DROP TABLE #FileSpace;

CREATE TABLE #FileSpace
(
    DBName           SYSNAME,
    LogicalFileName  SYSNAME,
    FileName         NVARCHAR(500),

    FileId           INT,
    GroupId          INT,
    GroupName        SYSNAME,

    MaxSize          BIGINT,
    Growth           BIGINT,

    FileSizeMB       DECIMAL(6,2),
    SpaceUsedMB      DECIMAL(6,2),
    FreeSpaceMB      DECIMAL(6,2),
    FreeSpacePct     DECIMAL(6,2),
    UsedSpacePct          DECIMAL(6,2)
);

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += '
USE ' + QUOTENAME(d.name) + ';

INSERT INTO #FileSpace
(
    DBName,
    LogicalFileName,
    FileName,
    FileId,
    GroupId,
    GroupName,
    MaxSize,
    Growth,
    FileSizeMB,
    SpaceUsedMB,
    FreeSpaceMB,
    FreeSpacePct,
    UsedSpacePct
)
SELECT
    DB_NAME()                                 AS DBName,
    mf.name                                  AS LogicalFileName,
    mf.physical_name                         AS FileName,
    mf.file_id                               AS FileId,
    mf.data_space_id                         AS GroupId,
    ISNULL(fg.name, ''LOG'')                   AS GroupName,
    mf.max_size                              AS MaxSize,
    mf.growth                                AS Growth,
    CAST(mf.size / 128.0 AS DECIMAL(6,2))             AS FileSizeMB,
    CAST(FILEPROPERTY(mf.name, ''SpaceUsed'') / 128.0 AS DECIMAL(6,2)) AS SpaceUsedMB,
    CAST((mf.size - FILEPROPERTY(mf.name, ''SpaceUsed'')) / 128.0 AS DECIMAL(6,2)) AS FreeSpaceMB,
    CAST(((mf.size - FILEPROPERTY(mf.name, ''SpaceUsed'')) * 100.0) / mf.size AS DECIMAL(6,2)) AS FreeSpacePct,
    CAST((FILEPROPERTY(mf.name, ''SpaceUsed'') * 100.0) / mf.size AS DECIMAL(6,2)) AS UsedSpacePct
FROM sys.database_files mf
LEFT JOIN sys.filegroups fg
    ON mf.data_space_id = fg.data_space_id
WHERE mf.type IN (0,1);   -- DATA + LOG

'
FROM sys.databases d
LEFT JOIN sys.dm_hadr_database_replica_states drs
    ON d.database_id = drs.database_id
   AND drs.is_local = 1
LEFT JOIN sys.dm_hadr_availability_replica_states ars
    ON drs.replica_id = ars.replica_id
LEFT JOIN sys.availability_replicas ar
    ON drs.replica_id = ar.replica_id
WHERE d.state_desc = 'ONLINE'

  AND
  (
        drs.database_id IS NULL
     OR drs.is_primary_replica = 1
     OR (ars.role_desc = 'SECONDARY'
         AND ar.secondary_role_allow_connections_desc <> 'NO')
  );

EXEC sys.sp_executesql @sql;

-- Example filter
SELECT *
FROM #FileSpace ;

DROP TABLE #FileSpace;


"@
        
        $SQLDataSet = New-Object System.Data.DataSet
        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SQLQuery, $SQLConnection)
        [void]$SQLAdapter.Fill($SQLDataSet)
        
        $data = $SQLDataSet.Tables[0]
        
        foreach ($dataItem in $data.Rows) {

        




            $sql = @"
           INSERT INTO SQL_DataFiles_Temp (ServerName, DatabaseName,LogicalFileName,FileID,GroupID,GroupName,MaxSize,Growth,FileName,DataFileSize,DataFileUsedSpace,DataFileFreeSpace,PctFreeSpace,PctUsed)
SELECT 
    '$ServerName', '$($dataItem.DBName)', '$($dataItem.LogicalFileName)',
    '$($dataItem.FileID)', '$($dataItem.GroupID)', '$($dataItem.GroupName)',
    '$($dataItem.MaxSize)',  '$($dataItem.Growth)',  '$($dataItem.FileName)',  $($dataItem.FileSizeMB),  $($dataItem.SpaceUsedMB),  $($dataItem.FreeSpaceMB),  $($dataItem.FreeSpacePct),  $($dataItem.UsedSpacePct)
"@
            
            Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $sql -NonQuery
        }
    }
    catch {

        Write-Error "[$ServerName] Connection failed: $($_.Exception.Message)"
    }
    finally {
        $SQLConnection.Close()
    }

}  

$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"

Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan


foreach ($row in $result) {


    $ServerName = $row.ServerName
    try {
        Get-SQLDataFilesInformation -ServerName $ServerName -ErrorAction Stop
        Write-Host "Collected from [$ServerName]" -ForegroundColor Green
    }
    catch {
        Write-Host "FAILED [$ServerName] -> $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
 
 }
    #Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "EXEC Sync_SQL_DataFiles_Metadata" -NonQuery
	Write-Host " " -ForegroundColor Green


$endDTM = (Get-Date)
Write-Host ""
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "SQL DataFiles collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow



