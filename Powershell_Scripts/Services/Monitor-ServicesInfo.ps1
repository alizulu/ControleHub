<#
.SYNOPSIS
    Collects all Windows Services information and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of Servers (retrieved from a central monitoring database), 
    connects to each instance, and gathers services information.
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
Write-Host " CONTROLE WINDOWS SERVICES COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurentMonth $CurentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects Services from all active servers" -ForegroundColor Cyan
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

$checkQuery = "IF OBJECT_ID('dbo.Services_Temp', 'U') IS NOT NULL SELECT 1 AS TableExists ELSE SELECT 0 AS TableExists"

$tableExists = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $checkQuery

if ($tableExists.TableExists -eq 0) {
    Write-host "Table dbo.Services_Temp does not exist. Exiting." -ForegroundColor Red
    return
}

Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "TRUNCATE TABLE dbo.Services_Temp" -NonQuery

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
   	
function Escape-SqlValue {
    param ([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return $Value.Replace("'", "''")
}

function Get-ServicesInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )

    try {
      

       
        $services = Get-CimInstance -ClassName Win32_Service -ComputerName $ServerName -ErrorAction Stop

        if (-not $services) {
            Write-Warning "[$ServerName] No services returned"
            return
        }

$values = foreach ($svc in $services) {

    $name        = Escape-SqlValue $svc.Name
    $displayName = Escape-SqlValue $svc.DisplayName
    $state       = Escape-SqlValue $svc.State
    $startName   = Escape-SqlValue $svc.StartName
    $startMode   = Escape-SqlValue $svc.StartMode

    "('$ServerName','$name','$displayName','$state','$startName','$startMode')"
}

        $sql = @"
INSERT INTO dbo.Services_Temp
(ServerName, Service_Name, Display_Name, RunningState, Service_Account, StartMode)
VALUES
$(($values -join ",`n"))
"@

        Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $sql -NonQuery

        
    }
    catch {
        Write-Warning "[$ServerName] Services collection failed: $($_.Exception.Message)"
    }
}


 
 
$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"



Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan
foreach ($row in $result) {

    $ServerName = $row.ServerName

        Get-ServicesInformation -ServerName $ServerName 
	    Write-Host "Collecting Services Info: [$ServerName]" -ForegroundColor Green
	   
  
}

    
   
$endDTM = (Get-Date)
Write-Host ""
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "Services collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow


