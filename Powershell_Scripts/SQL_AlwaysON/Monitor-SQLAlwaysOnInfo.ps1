<#
.SYNOPSIS
    Collects SQL Server AlwaysON usage and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of SQL Servers (retrieved from a central monitoring database), 
    connects to each instance, and collections SQL AlwaysOn information.
    The results are aggregated and stored in a central staging table.

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
Write-Host " Description   : Collects Cluster informationfrom all active servers" -ForegroundColor Cyan
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



Invoke-SqlQuery -ConnectionString $MonitorConnectionString -Query "TRUNCATE TABLE dbo.SQL_AlwaysON_Temp" -NonQuery
    	
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



function Get-SQLAlwaysONInformation {
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


        # Your existing massive SQL query here
        $SQLQuery = @"
                                ------------Get AAG Information -------------
                                
    SET FMTONLY OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET NOCOUNT ON;

DECLARE @cluster_name varchar(64);

SELECT @cluster_name = cluster_name
FROM sys.dm_hadr_cluster;

SELECT
    /* =========================================================
       Identity / Topology
       ========================================================= */
    ag.name                                           AS availabilitygroupName,
    @cluster_name                                     AS cluster_name,
    ar.replica_server_name                            AS servername,
    DB_NAME(dr_state.database_id)                     AS databasename,
    al.dns_name                                       AS listener_name,
    lip.ip_address                                    AS listener_ip,
    ar.endpoint_url,

    /* =========================================================
       Replica Role & Connectivity
       ========================================================= */
    CASE 
        WHEN ar_state.is_local = 1 THEN N'LOCAL'
        ELSE N'REMOTE'
    END                                               AS isLocal,
    COALESCE(ar_state.role_desc, N'DISCONNECTED')     AS role_desc,
    ar_state.connected_state_desc,
    ar_state.operational_state_desc,
    ar_state.last_connect_error_description,
    ar_state.last_connect_error_timestamp,

    /* =========================================================
       Availability & Failover Configuration
       ========================================================= */
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ar.primary_role_allow_connections_desc,
    ar.secondary_role_allow_connections_desc,

    /* =========================================================
       Database Synchronization State
       ========================================================= */
    dr_state.synchronization_state_desc               AS synchronization_state_desc,

    /* =========================================================
       Health Signals (Replica vs Database)
       ========================================================= */
    ar_state.synchronization_health_desc              AS replica_sync_health,
    dr_state.synchronization_health_desc              AS db_sync_health,
    dr_state.is_suspended,
    dr_state.suspend_reason_desc,

    /* =========================================================
       Data Movement Telemetry
       ========================================================= */
    dr_state.last_sent_time,
    dr_state.last_received_time,
    dr_state.last_hardened_time,
    dr_state.last_redone_time,
    dr_state.last_commit_time,
    dr_state.log_send_queue_size,
    dr_state.log_send_rate,
    dr_state.redo_queue_size,
    dr_state.redo_rate,
    dr_state.filestream_send_rate,

    /* =========================================================
       Derived / Human-Readable Health
       ========================================================= */
    CASE
        WHEN dr_state.is_suspended = 1
            THEN 'NOT_HEALTHY (SUSPENDED)'
        WHEN dr_state.synchronization_health_desc <> 'HEALTHY'
            THEN 'NOT_HEALTHY (DB)'
        WHEN ar_state.synchronization_health_desc <> 'HEALTHY'
            THEN 'NOT_HEALTHY (REPLICA)'
        ELSE 'HEALTHY'
    END                                               AS effective_health_reason

FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ar_state
    ON ar.replica_id = ar_state.replica_id
JOIN sys.dm_hadr_database_replica_states dr_state
    ON ag.group_id = dr_state.group_id
   AND dr_state.replica_id = ar_state.replica_id
LEFT JOIN sys.availability_group_listeners al
    ON ag.group_id = al.group_id
LEFT JOIN sys.availability_group_listener_ip_addresses lip
    ON lip.listener_id = al.listener_id
WHERE ar_state.is_local = 1;

"@
        
        $SQLDataSet = New-Object System.Data.DataSet
        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SQLQuery, $SQLConnection)
        [void]$SQLAdapter.Fill($SQLDataSet)
        
        $data = $SQLDataSet.Tables[0]
        
        foreach ($dataItem in $data.Rows) {
            # Build INSERT statement with parameterized values to prevent SQL injection
            $insertSQL = @"
INSERT INTO SQL_AlwaysON_Temp (
            ServerName
           ,availabiltygroupName
           ,cluster_name
           ,replica_server_name
           ,endpoint_url
           ,Listener
           ,Listener_IP
           ,databasename
           ,operational_state_desc
           ,isLocal
           ,role_desc
           ,connected_state_desc
           ,availability_mode_desc
           ,synchronization_state_desc
           ,replica_sync_health
           ,db_sync_health
           ,failover_mode_desc
           ,suspend_reason_desc
           ,effective_health_reason
           ,primary_role_allow_connections_desc
           ,secondary_role_allow_connections_desc
           ,last_connect_error_description
           ,last_connect_error_timestamp
           ,last_sent_time
           ,last_received_time
           ,last_hardened_time
           ,last_redone_time
           ,log_send_queue_size
           ,log_send_rate
           ,redo_queue_size
           ,redo_rate
           ,filestream_send_rate
           ,last_commit_time
)
SELECT 
    '$ServerName', '$($dataItem.availabiltygroupName)', '$($dataItem.cluster_name)',
    '$($dataItem.replica_server_name)', '$($dataItem.endpoint_url)', '$($dataItem.Listener)',
    '$($dataItem.Listener_IP)',  '$($dataItem.databasename)',
    '$($dataItem.operational_state_desc)', '$($dataItem.isLocal)',
    '$($dataItem.role_desc)', '$($dataItem.connected_state_desc)',
    '$($dataItem.availability_mode_desc)', '$($dataItem.synchronization_state_desc)',
    '$($dataItem.replica_sync_health)','$($dataItem.db_sync_health)', '$($dataItem.failover_mode_desc)',
    '$($dataItem.suspend_reason_desc)','$($dataItem.effective_health_reason)', '$($dataItem.primary_role_allow_connections_desc)', '$($dataItem.secondary_role_allow_connections_desc)',
    '$($dataItem.last_connect_error_description)', '$($dataItem.last_connect_error_timestamp)',
    '$($dataItem.last_sent_time)', '$($dataItem.last_received_time)',
    '$($dataItem.last_hardened_time)', '$($dataItem.last_redone_time)',
    '$($dataItem.log_send_queue_size)', '$($dataItem.log_send_rate)',
    '$($dataItem.redo_queue_size)', '$($dataItem.redo_rate)',
    '$($dataItem.filestream_send_rate)', '$($dataItem.last_commit_time)'
"@
           # write-host $insertSQL
            Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $insertSQL
        }
    }
    catch {
           Write-Error "Error collecting AlwaysON information from ${ServerName}: $_"
           Write-SqlLog -Message "Error collecting AlwaysON information: $_" -Level ERROR -ServerName $ServerName -ScriptName $MyInvocation.MyCommand.Name
        throw
    }

}  

 
$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"

Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan


foreach ($row in $result) {

    $ServerName = $row.ServerName
    Get-SQLAlwaysONInformation $ServerName 
	Write-Host "Collecting AlwaysON Info: [$ServerName]" -ForegroundColor Green
 
    }
    
    



$endDTM = (Get-Date)
Write-Host ""
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "SQL AlwaysON collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow
  


