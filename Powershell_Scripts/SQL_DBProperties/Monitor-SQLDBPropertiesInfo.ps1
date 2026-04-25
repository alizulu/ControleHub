<#
.SYNOPSIS
    Collects SQL Server Database Properties usage and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of SQL Servers (retrieved from a central monitoring database), 
    connects to each instance, and pulls Database properties.
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
Write-Host " CONTROLE SQL DB PROPERTIES COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurrentMonth $CurrentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects Database Properties informationfrom all active servers" -ForegroundColor Cyan
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


Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "TRUNCATE TABLE dbo.SQL_DBProperties_Temp" -NonQuery
    	
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



Function Get-DBPropertiesInformation
{
	PARAM
	(
        [string]$ServerName
 
	)

       
    # Create connection to the TARGET server (not monitor server)
    $SQLConnection = New-SQLConnection -ServerName $ServerName

        try{        
			    #Open database
				$SQLConnection.Open()
	             
	               #SQL query statement to get all stale statistics
                    $SQLQuery = "
                                SELECT name as DatabaseName,  
                                                suser_sname(sid) as owner,
                                                convert(nvarchar(19), crdate) as created,
                                                dbid,
                                                DatabasePropertyEx(name, 'Status') as Status,
                                                DatabasePropertyEx(name, 'Updateability') as Updateability,
                                                DatabasePropertyEx(name, 'UserAccess') as UserAccess,
                                                DatabasePropertyEx(name, 'Recovery') as Recovery,
                                                DatabasePropertyEx(name, 'Version') as Version,
                                                DatabasePropertyEx(name, 'Collation') as Collation,
                                                DatabasePropertyEx(name, 'SQLSortOrder') as SQLSortOrder,
                                                cast(DatabasePropertyEx(name, 'IsAutoClose') as bit) as IsAutoClose,
                                                cast(DatabasePropertyEx(name, 'IsAutoShrink') as bit) as IsAutoShrink,
                                                cast(DatabasePropertyEx(name, 'IsInStandby') as bit) as IsInStandby,
                                                cast(DatabasePropertyEx(name, 'IsTornPageDetectionEnabled') as bit) as IsTornPageDetectionEnabled,
                                                cast(DatabasePropertyEx(name, 'IsAnsiNullDefault') as bit) as IsAnsiNullDefault,
                                                cast(DatabasePropertyEx(name, 'IsAnsiNullsEnabled') as bit) as IsAnsiNullsEnabled,
                                                cast(DatabasePropertyEx(name, 'IsAnsiPaddingEnabled') as bit) as IsAnsiPaddingEnabled,
                                                cast(DatabasePropertyEx(name, 'IsAnsiWarningsEnabled') as bit) as IsAnsiWarningsEnabled,
                                                cast(DatabasePropertyEx(name, 'IsArithmeticAbortEnabled') as bit) as IsArithmeticAbortEnabled,
                                                cast(DatabasePropertyEx(name, 'IsAutoCreateStatistics') as bit) as IsAutoCreateStatistics,
                                                cast(DatabasePropertyEx(name, 'IsAutoUpdateStatistics') as bit) as IsAutoUpdateStatistics,
                                                cast(DatabasePropertyEx(name, 'IsCloseCursorsOnCommitEnabled') as bit) as IsCloseCursorsOnCommitEnabled,
                                                cast(DatabasePropertyEx(name, 'IsFullTextEnabled') as bit) as IsFullTextEnabled,
                                                cast(DatabasePropertyEx(name, 'IsLocalCursorsDefault') as bit) as IsLocalCursorsDefault,
                                                cast(DatabasePropertyEx(name, 'IsNullConcat') as bit) as IsNullConcat,
                                                cast(DatabasePropertyEx(name, 'IsNumericRoundAbortEnabled') as bit) as IsNumericRoundAbortEnabled,
                                                cast(DatabasePropertyEx(name, 'IsQuotedIdentifiersEnabled') as bit) as IsQuotedIdentifiersEnabled,
                                                cast(DatabasePropertyEx(name, 'IsRecursiveTriggersEnabled') as bit) as IsRecursiveTriggersEnabled,
                                                cast(DatabasePropertyEx(name, 'IsMergePublished') as bit) as IsMergePublished,
                                                cast(DatabasePropertyEx(name, 'IsPublished') as bit) as IsPublished,
                                                cast(DatabasePropertyEx(name, 'IsSubscribed') as bit) as IsSubscribed,
                                                cast(DatabasePropertyEx(name, 'IsSyncWithBackup') as bit) as IsSyncWithBackup,
												cmptlevel
FROM   master.dbo.sysdatabases 
ORDER BY 1


                                "
                            
                    #Create SQLDataAdapter object with command text and connection
			        $SQLDataSet = New-Object System.Data.DataSet
			        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SQLQuery,$SQLConnection)
                                       
			        $SQLAdapter.Fill($SQLDataSet) | Out-Null
                    $SQLConnection.Close()
                  

                    $data = $SQLDataSet.Tables[0]

           
                    $data = $SQLDataSet.Tables[0]

                    foreach ($data_item in $data.Rows)
                        {	
                            
                            $DatabaseName 			= $data_item.DatabaseName;
                            $owner 	= $data_item.owner;
                            $created 	= $data_item.created;
                            $dbid 			= $data_item.dbid;
                            $Status 			= $data_item.Status;
                            $Updateability 			= $data_item.Updateability;
                            $UserAccess 			= $data_item.UserAccess;
                            $Recovery 			= $data_item.Recovery;
                            $Version 			= $data_item.Version;
                            $Collation 			= $data_item.Collation;
                            $SQLSortOrder 			= $data_item.SQLSortOrder;
                            $IsAutoClose 			= $data_item.IsAutoClose;
                            $IsAutoShrink 			= $data_item.IsAutoShrink;
                            $IsInStandby 			= $data_item.IsInStandby;
                            $IsTornPageDetectionEnabled 			= $data_item.IsTornPageDetectionEnabled;
                            $IsAnsiNullDefault 			= $data_item.IsAnsiNullDefault;
                            $IsAnsiNullsEnabled 			= $data_item.IsAnsiNullsEnabled;
                            $IsAnsiPaddingEnabled 			= $data_item.IsAnsiPaddingEnabled;
                            $IsAnsiWarningsEnabled 			= $data_item.IsAnsiWarningsEnabled;
                            $IsArithmeticAbortEnabled 			= $data_item.IsArithmeticAbortEnabled;
                            $IsAutoCreateStatistics 			= $data_item.IsAutoCreateStatistics;
                            $IsAutoUpdateStatistics 			= $data_item.IsAutoUpdateStatistics;
                            $IsCloseCursorsOnCommitEnabled 			= $data_item.IsCloseCursorsOnCommitEnabled;
                            $IsFullTextEnabled 			= $data_item.IsFullTextEnabled;
                            $IsLocalCursorsDefault 			= $data_item.IsLocalCursorsDefault;
                            $IsNullConcat 			= $data_item.IsNullConcat;
                            $IsNumericRoundAbortEnabled 			= $data_item.IsNumericRoundAbortEnabled;
                            $IsQuotedIdentifiersEnabled 			= $data_item.IsQuotedIdentifiersEnabled;
                            $IsMergePublished 			= $data_item.IsMergePublished;
                            $IsPublished 			= $data_item.IsPublished;
                            $IsSubscribed 			= $data_item.IsSubscribed;
                            $IsSyncWithBackup 			= $data_item.IsSyncWithBackup;
                            $cmptlevel 			= $data_item.cmptlevel;
                            
                            

			            $sql = "INSERT INTO SQL_DBProperties_Temp (ServerName, DatabaseName,owner,created,dbid, Status,Updateability,UserAccess,Recovery,Version,Collation,SQLSortOrder,IsAutoClose,IsAutoShrink,IsInStandby,IsTornPageDetectionEnabled,
IsAnsiNullDefault,IsAnsiNullsEnabled,IsAnsiPaddingEnabled,IsAnsiWarningsEnabled,IsArithmeticAbortEnabled,IsAutoCreateStatistics,IsAutoUpdateStatistics,IsCloseCursorsOnCommitEnabled,IsFullTextEnabled,IsLocalCursorsDefault,IsNullConcat,IsNumericRoundAbortEnabled,
IsQuotedIdentifiersEnabled,IsRecursiveTriggersEnabled,IsMergePublished,IsPublished,IsSubscribed,IsSyncWithBackup,cmptlevel) " 
	                        $sql += " SELECT '$ServerName', '$DatabaseName','$owner','$created', $dbid,'$Status', '$Updateability', '$UserAccess', '$Recovery', '$Version', '$Collation', '$SQLSortOrder', '$IsAutoClose', '$IsAutoShrink', '$IsInStandby','$IsTornPageDetectionEnabled','$IsAnsiNullDefault','$IsAnsiNullsEnabled','$IsAnsiPaddingEnabled','$IsAnsiWarningsEnabled','$IsArithmeticAbortEnabled','$IsAutoCreateStatistics','$IsAutoUpdateStatistics','$IsCloseCursorsOnCommitEnabled', '$IsFullTextEnabled','$IsLocalCursorsDefault','$IsNullConcat','$IsNumericRoundAbortEnabled','$IsQuotedIdentifiersEnabled','$IsRecursiveTriggersEnabled','$IsMergePublished','$IsPublished','$IsSubscribed','$IsSyncWithBackup','$cmptlevel'"
			                #Write-Host $sql
            Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $sql -NonQuery
                        }
            }
        catch 
		{

			$ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
			Write-Host "SQL Query: $SQLQuery" -foregroundcolor "red"
			Write-Host "ErrorMessage: $ErrorMessage" -foregroundcolor "yellow" " ServerName -->"$ServerName 


		}
    
}
$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"

Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan


foreach ($row in $result) {

    $ServerName = $row.ServerName


    
    try {
        Get-DBPropertiesInformation -ServerName $ServerName -ErrorAction Stop
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
Write-Host "SQL Database Properties collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow



