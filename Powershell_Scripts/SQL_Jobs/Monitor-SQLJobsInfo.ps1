<#
.SYNOPSIS
    Collects SQL Server Jobs  usage and metadata across multiple instances.

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
Write-Host " CONTROLE SQL JOBS COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurrentMonth $CurrentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects SQJ Jobs informationfrom all active servers" -ForegroundColor Cyan
Write-Host " Warranty      : Provided AS-IS" -ForegroundColor DarkGray
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "Start Time     : $startDTM"
Write-Host ""

Write-Host ""



#SQL Server Configuration values
$MonitorServer = "SQL1"
$MonitorDatabase = "ControleHub"
$MonitorconnectionString = "Server=$MonitorServer;Database=$MonitorDatabase;Integrated Security=True"

# SQL Account Credentials
#$Username = "YourUsername"
#$Password = "YourSecurePassword"

# Updated Connection String for SQL Authentication
#$MonitorconnectionString = "Server=$MonitorServer;Database=$MonitorDatabase;User ID=$Username;Password=$Password;"

Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "TRUNCATE TABLE dbo.SQL_Jobs_Temp" -NonQuery
    	
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


Function GetJobsInformation
{
	PARAM
	(
        [string]$ServerName
 
	)

	if($ServerName)
	{  
          $SQLConnection = New-SQLConnection -ServerName $ServerName

        try{        
			    #Open database
				$SQLConnection.Open()
	             
	               #SQL query statement to get all stale statistics
                    $SQLQuery = "
                                                                SELECT *
FROM 
( 
 SELECT JobName, ISNULL(LastStep,'') LastStep,
 CASE WHEN StartDate IS NOT NULL AND FinishDate IS NULL THEN 'Running' 
 WHEN Enabled = 0 THEN 'Disabled' 
 WHEN StepCount = 0 THEN 'No steps' 
 WHEN RunStatus IS NOT NULL THEN RunStatus 
 WHEN ScheduleCount = 0 THEN 'Not scheduled' 
 ELSE 'UNKNOWN' END LastRunOutCome,
 DatabaseName, Enabled, ScheduleCount, StepCount, 
 date_created,
 date_modified,
 StartDate, 
 FinishDate, DurationSec, 
 RIGHT('0'+convert(varchar(5),DurationSec/3600),2)+':'+RIGHT('0'+convert(varchar(5),DurationSec%3600/60),2)+':'+ RIGHT('0'+convert(varchar(5),(DurationSec%60)),2) DurationSecFormatted, 
 avgDurationSec,
 RIGHT('0'+convert(varchar(5),avgDurationSec/3600),2)+':'+RIGHT('0'+convert(varchar(5),avgDurationSec%3600/60),2)+':'+ RIGHT('0'+convert(varchar(5),(avgDurationSec%60)),2) avgDurationSecFormatted, 
 CASE WHEN (DurationSec IS NULL OR ISNULL(avgDurationSec, 0) = 0) THEN 0 ELSE CONVERT(DECIMAL(18,2), (100*CAST(DurationSec AS DECIMAL)) / CAST (avgDurationSec as DECIMAL)) END AS DurationRatio, 
 NextRunDate, 
 StepCommand, 
 HistoryMessage 
 FROM 
 ( 
 SELECT j.name JobName,j.enabled Enabled, 
 (select COUNT(1) from msdb..sysjobschedules jss where jss.job_id = j.job_id) ScheduleCount, 
 (select COUNT(1) from msdb..sysjobsteps jps where jps.job_id = j.job_id) StepCount, 
 ls1.job_history_id HistoryID, 
 ls1.start_execution_date StartDate, 
 ls1.stop_execution_date FinishDate, 
 ls1.last_executed_step_id LastStepID, 
 DATEDIFF(SECOND, ls1.start_execution_date, CASE WHEN ls1.stop_execution_date IS NULL THEN GETDATE() ELSE ls1.stop_execution_date END) DurationSec, 
 ISNULL(avgSec, 0) avgDurationSec, 
 ls1.next_scheduled_run_date NextRunDate, 
 st.step_name LastStep, st.command StepCommand, st.database_name DatabaseName, 
 h.message HistoryMessage, 
 CASE WHEN h.job_id IS NULL THEN 'Never Run' ELSE 
 CASE h.run_status 
 WHEN 0 THEN 'Failed' 
 WHEN 1 THEN 'Succeeded' 
 WHEN 2 THEN 'Retry' 
 WHEN 3 THEN 'Canceled' END END RunStatus, 
 h.run_date rawRunDate, 
 h.run_time rawRunTime, 
 h.run_duration rawRunDuration,
 j.date_created,
 j.date_modified
 FROM msdb..sysjobactivity ls1 (NOLOCK) 
 INNER JOIN msdb..sysjobs j (NOLOCK) ON ls1.job_id = j.job_id 
 INNER JOIN 
 ( 
 SELECT job_id JobID, MAX(session_id) LastSessionID 
 FROM msdb..sysjobactivity (NOLOCK) 
 GROUP BY job_id 
 ) ls2 ON ls1.job_id = ls2.JobID and ls1.session_id = ls2.LastSessionID 
 LEFT OUTER JOIN msdb..sysjobsteps st (NOLOCK) ON st.job_id = j.job_id and ls1.last_executed_step_id = st.step_id 
 LEFT OUTER JOIN msdb..sysjobhistory h (NOLOCK) ON h.instance_id = ls1.job_history_id 
 LEFT OUTER JOIN 
 ( 
 SELECT j.job_id JobID, SUM(h.avgSecs) avgSec 
 FROM msdb..sysjobs j (NOLOCK) 
 INNER JOIN 
 ( 
 SELECT job_id, step_id, AVG(run_duration/10000*3600 + run_duration%10000/100*60 + run_duration%100) avgSecs 
 FROM msdb..sysjobhistory 
 WHERE step_id > 0 AND run_status = 1 
 GROUP BY job_id,step_id 
 ) h on j.job_id = h.job_id 
 GROUP BY j.job_id 
 ) jobavg ON jobavg.JobID = j.job_id 
 )jj 

)x 
ORDER BY CASE LastRunOutCome 
WHEN 'Running' THEN 0 
WHEN 'Failed' THEN 1 
WHEN 'Retry' THEN 2
WHEN 'Succeeded' THEN 3
WHEN 'Canceled' THEN 4
WHEN 'No steps' THEN 5 
WHEN 'Not scheduled' THEN 6
WHEN 'Disabled' THEN 7
WHEN 'Never Run' THEN 8
WHEN 'UNKNOWN' THEN -1
ELSE -2 END, NextRunDate, JobName
                                
                                "
                            
                    #Create SQLDataAdapter object with command text and connection
			        $SQLDataSet = New-Object System.Data.DataSet
			        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SQLQuery,$SQLConnection)
                                       
			        $SQLAdapter.Fill($SQLDataSet) | Out-Null
                    $SQLConnection.Close()


                    $data = $SQLDataSet.Tables[0]

                    foreach ($data_item in $data.Rows)
                        {	
                            
                            $JobName 			= $data_item.JobName -replace "'",""
                            
                            $LastStep 	        = $data_item.LastStep -replace "'","";
                            $LastRunOutCome 			= $data_item.LastRunOutCome;;
                            $DatabaseName 			= $data_item.DatabaseName;
                            $Enabled 			= $data_item.Enabled;
                            $ScheduleCount 			= $data_item.ScheduleCount;
                            $StepCount 			= $data_item.StepCount;
                            $StartDate 			= $data_item.StartDate;
                            $date_created 			= $data_item.date_created;
                            $date_modified 			= $data_item.date_modified;
                            $FinishDate 			= $data_item.FinishDate;
                            $DurationSec 			= $data_item.DurationSec;
                            $DurationSecFormatted= $data_item.DurationSecFormatted;
                            $AvgDurationSec 			= $data_item.AvgDurationSec;
                            $AvgDurationSecFormatted 			= $data_item.AvgDurationSecFormatted;
                            $NextRunDate 		= $data_item.NextRunDate;
                            $Command 			= $data_item.StepCommand;
                            $StepCommand        = $Command -replace "'","";
                            $HistoryMessage 			= $data_item.HistoryMessage;
                            



			                $sql = "INSERT INTO dbo.SQL_Jobs_Temp(ServerName ,DatabaseName,JobName,LastStep,LastRunOutCome,Enabled, ScheduleCount, StepCount,date_created,date_modified, StartDate,FinishDate,DurationSec, DurationSecFormatted,AvgDurationSec,AvgDurationSecFormatted,NextRunDate) " 
	                        $sql += " VALUES  ('$ServerName', '$DatabaseName','$JobName','$LastStep','$LastRunOutCome', '$Enabled','$ScheduleCount', '$StepCount','$date_created','$date_modified','$StartDate','$FinishDate','$DurationSec','$DurationSecFormatted', '$AvgDurationSec','$AvgDurationSecFormatted','$NextRunDate') "
                            Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $sql -NonQuery

                        }
                    
               
                
            }
        catch 
		{

             Write-host "Error collecting SQL Jobs information from ${ServerName}: $_" -ForegroundColor Red
             Write-SqlLog -Message "Error collecting SQL Jobs information from ${ServerName}: $_" -Level ERROR -ServerName $ServerName -ScriptName $MyInvocation.MyCommand.Name
		}
    }
}



$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"

Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan


foreach ($row in $result) {


    $ServerName = $row.ServerName

    
    try {
        GetJobsInformation -ServerName $ServerName -ErrorAction Stop
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
Write-Host "SQL Jobs collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow

    


