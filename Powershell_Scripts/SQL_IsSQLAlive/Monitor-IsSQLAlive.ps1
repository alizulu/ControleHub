<#
.SYNOPSIS
    Checks SQL Server availability and updates a central inventory.
.NOTES
    Author: Ali Zulu
    Version: 1.0
    Warranty: Provided AS-IS
#>


cls
$startDTM = Get-Date
$CurrentMonth = $startDTM.ToString('MMMM')
$CurrentYear = $startDTM.Year


Write-Host "=================================================================================================" -ForegroundColor Yellow
Write-Host " CONTROLE SQL DATAFILES COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurrentMonth $CurrentYear" -ForegroundColor Cyan
Write-Host " Description   : Checks if Servers are available" -ForegroundColor Cyan
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


function Test-SqlInstanceAvailability {
    param ([string]$SqlInstance)

    # Use a very short timeout for availability checks to keep the loop moving
    $connString = "Server=$SqlInstance;Database=master;Integrated Security=SSPI;Connection Timeout=5;Application Name=AvailabilityCheck"
    $connection = New-Object System.Data.SqlClient.SqlConnection($connString)
    
    try {
        # CRITICAL: .Open() MUST be inside the try block
        $connection.Open()
        $cmd = $connection.CreateCommand()
        $cmd.CommandText = "SELECT CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20))"
        $result = $cmd.ExecuteScalar()

        if ($null -ne $result) { return $true }
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $connection) {
            $connection.Dispose() # Proper cleanup
        }
    }
    return $false
}


$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"

Write-Host "Checking $($result.Count) servers..." -ForegroundColor Gray

if ($null -eq $result) { Write-Error "Could not retrieve server list."; return }


foreach ($row in $result) {

    $sqlInstance = $row.ServerName
    
    if (Test-SqlInstanceAvailability -SqlInstance $sqlInstance) {
        Write-Host "[ONLINE] : $sqlInstance" -ForegroundColor Green
        
        # Update the LastActiveDateTime
        $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $updateQuery = "UPDATE ServerList SET LastActiveDateTime = '$now' WHERE ServerName = '$sqlInstance'"
        
        
        Invoke-SqlQuery -ConnectionString $MonitorConnectionString -Query $updateQuery -NonQuery
    }
    else {
        Write-Host "[OFFLINE]: $sqlInstance" -ForegroundColor Red
        
        Write-SqlLog -Message "Unable to connect to: ${sqlInstance}: $_" -Level WARN -ServerName $sqlInstance -ScriptName $MyInvocation.MyCommand.Name# Log failure to an audit table here
    }
}


$endDTM = Get-Date
Write-Host "Elapsed Time: $(($endDTM-$startDTM).TotalSeconds) seconds" -ForegroundColor White