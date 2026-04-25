<#
.SYNOPSIS
    Collects Windows Cluster information and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of SQL Servers (retrieved from a central monitoring database), 
    connects to each instance, and gathers cluster and cluster resource information.
    The results are aggregated and stored in a central staging table.

.NOTES
    Author:  Ali Zulu
    Version: 1.0
    Warranty: Provided AS-IS
#>
cls

#region Initialization
$startDTM = Get-Date

$CurentMonth = (Get-Date).ToString('MMMM')
$CurentYear = (Get-Date).Year

Clear-Host
Write-Host ""

Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host " CONTROLE WINDOWS CLUSTER COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurentMonth $CurentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects Cluster informationfrom all active servers" -ForegroundColor Cyan
Write-Host " Warranty      : Provided AS-IS" -ForegroundColor DarkGray
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "Start Time     : $startDTM"
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



Invoke-SqlQuery -ConnectionString $MonitorConnectionString -Query "TRUNCATE TABLE dbo.Cluster_Temp" -NonQuery
Invoke-SqlQuery -ConnectionString $MonitorConnectionString -Query "TRUNCATE TABLE dbo.ClusterResource_Temp" -NonQuery

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
   	

function Get-ClusterInformation {
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
                                ------------Get Cluster Information -------------
                                
    SET NOCOUNT ON;

    SELECT CONVERT(varchar(100), SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) as ComputerName


"@
        
        $SQLDataSet = New-Object System.Data.DataSet
        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SQLQuery, $SQLConnection)
        [void]$SQLAdapter.Fill($SQLDataSet)
        
        $data = $SQLDataSet.Tables[0]
        
        foreach ($dataItem in $data.Rows) {

            $insertSQL = @"
            INSERT INTO Cluster_Temp (ServerName, PhysicalComputerName)
            SELECT  '$ServerName', '$($dataItem.ComputerName)'
"@
           # Invoke-SqlQuery -ServerInstance $MonitorServer -Database $MonitorDatabase -Query $insertSQL
Invoke-SqlQuery -ConnectionString $MonitorConnectionString -Query $insertSQL -NonQuery
    
        }
        Write-Host "[$ServerName] Cluster information collected" -ForegroundColor Gray
    }

    catch {
           Write-Error "Error collecting Cluster information from ${ServerName}: $_"
           Write-SqlLog -Message "Error collecting Cluster information from ${ServerName}: $_" -Level ERROR -ServerName $ServerName -ScriptName $MyInvocation.MyCommand.Name
        throw
    }
    finally {
        $SQLConnection.Close()
    }

}  
function Get-ClusterResourceInformation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ServerName
    )

    try {
       

        # Inline cluster membership test
        try {
            Get-CimInstance -ClassName MSCluster_Node -Namespace root\mscluster -ComputerName $ServerName -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "[$ServerName] Not a cluster node – skipping" -ForegroundColor DarkGray
            return
        }

        Import-Module FailoverClusters -ErrorAction Stop

        $cluster   = Get-Cluster  -Name $ServerName
        $nodes     = Get-ClusterNode -Cluster $cluster.Name
        $resources = Get-ClusterResource -Cluster $cluster.Name

        foreach ($node in $nodes) {
            foreach ($res in $resources) {

                $sql = @"
INSERT INTO dbo.ClusterResource_Temp
(
    ServerName,
    ClusterName,
    ClusterState,
    QuorumType,
    Witness,
    NodeName,
    NodeState,
    ResourceName,
    ResourceType,
    ResourceState,
    OwnerNode
)
VALUES
(
    '$ServerName',
    '$($cluster.Name)',
    '$($cluster.State)',
    '$($cluster.QuorumType)',
    '$($cluster.QuorumResource)',
    '$($node.Name)',
    '$($node.State)',
    '$($res.Name)',
    '$($res.ResourceType)',
    '$($res.State)',
    '$($res.OwnerNode.Name)'
)
"@

                Invoke-SqlQuery -ConnectionString $MonitorConnectionString -Query $sql -NonQuery
                #Invoke-SqlQuery -ServerInstance $MonitorServer -Database $MonitorDatabase -Query $sql -NonQuery
            }
        }

        Write-Host "[$ServerName] Cluster Resource information collected" -ForegroundColor Green
    }
    catch {
        Write-Warning "[$ServerName] Cluster Resource collection failed: $($_.Exception.Message)"
        Write-SqlLog -Message "Cluster Resource collection failed: $($_.Exception.Message)" -Level ERROR -ServerName $ServerName -ScriptName $ScriptName
    }
}



$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"

Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan


foreach ($row in $result) {


    $ServerName = $row.ServerName
    
       Get-ClusterInformation  -ServerName $ServerName
       Get-ClusterResourceInformation  -ServerName $ServerName
	    
  
}


$endDTM = (Get-Date)
Write-Host ""
Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host "Cluster collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow


