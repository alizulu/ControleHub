<#
.SYNOPSIS
    Collects SQL Server Database Backup and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of SQL Servers (retrieved from a central monitoring database), 
    connects to each instance, and gathers backup information.
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


Write-Host ""

Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host " CONTROLE SQL BACKUPS COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurrentMonth $CurrentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects Cluster informationfrom all active servers" -ForegroundColor Cyan
Write-Host " Warranty      : Provided AS-IS" -ForegroundColor DarkGray
Write-Host "=================================================================================================" -ForegroundColor Yellow

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


Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "TRUNCATE TABLE dbo.SQL_Backups_Temp" -NonQuery
    	


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



function Get-SQLBackupsInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )
    # Create connection to the TARGET server (not monitor server)
    $SQLConnection = New-SQLConnection -ServerName $ServerName

  
         # Open the connection
        $SQLConnection.Open()


        # Your existing massive SQL query here
        $SQLQuery = @"
                                ------------Get SQL Backups Information -------------
                                
   select MAX_FIN.databasename, 
                                MAX_FIN.type, 
                                MAX_FIN.Media,bs2.backup_size/1024/1024 as backup_size, 
				                bs2.backup_start_date, 
                                MAX_FIN.Backup_Finish_Date, 
                                bm2.physical_device_name                                   
			 from (select bs.database_name COLLATE SQL_Latin1_General_CP1_CS_AS as databasename, bs.type,
								 upper(left(bm.physical_device_name,3)) as Media,
								 max(bs.backup_finish_date) as Backup_Finish_Date
				   from msdb.dbo.backupset bs inner join msdb.dbo.backupmediafamily bm
										  on bs.media_set_id = bm.media_set_id
						group by bs.database_name COLLATE SQL_Latin1_General_CP1_CS_AS,
									bs.type, upper(left(bm.physical_device_name,3))) MAX_FIN
						inner join msdb.dbo.backupset bs2
							  on MAX_FIN.Backup_Finish_Date = bs2.backup_finish_date
									and MAX_FIN.type = bs2.type
									and MAX_FIN.databasename = bs2.database_name
						inner join msdb.dbo.backupmediafamily bm2
							  on bs2.media_set_id = bm2.media_set_id
							  and upper(left(bm2.physical_device_name,3)) = MAX_FIN.Media;

"@
        
        $SQLDataSet = New-Object System.Data.DataSet
        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SQLQuery, $SQLConnection)
        [void]$SQLAdapter.Fill($SQLDataSet)
        
        $data = $SQLDataSet.Tables[0]
        
        foreach ($dataItem in $data.Rows) {
            # Build INSERT statement with parameterized values to prevent SQL injection
            $sql = @"
            INSERT INTO SQL_Backups_Temp (ServerName, DatabaseName, Type, Media, Backup_Size, Backup_Start_Date, Backup_Finish_Date, Physical_Device_Name)
SELECT 
    '$ServerName', '$($dataItem.DatabaseName)', '$($dataItem.type)',
    '$($dataItem.Media)', '$($dataItem.backup_size)', '$($dataItem.backup_start_date)',
    '$($dataItem.Backup_Finish_Date)',  '$($dataItem.physical_device_name)'
"@
           #write-host $sql 
            Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $sql 
        }


}  


 
$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"



Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan


foreach ($row in $result) {

    $ServerName = $row.ServerName

   
    try {
        Get-SQLBackupsInformation -ServerName $ServerName -ErrorAction Stop
        Write-Host "Collected from [$ServerName]" -ForegroundColor Green
    }
    catch {
        Write-Host "FAILED [$ServerName] -> $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
}

    

$endDTM = (Get-Date)
Write-Host ""
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "SQL Backups collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow

  


