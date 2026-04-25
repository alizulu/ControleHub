<#
.SYNOPSIS
    Collects SQL Server Instance Properties usage and metadata across multiple instances.

.DESCRIPTION
    This script iterates through a list of SQL Servers (retrieved from a central monitoring database), 
    connects to each instance, and pulls Instance properties.
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
Write-Host " CONTROLE SQL INSTANCE COLLECTION" -ForegroundColor Cyan
Write-Host " Author        : Ali Zulu" -ForegroundColor Cyan
Write-Host " Execution Date: $CurrentMonth $CurrentYear" -ForegroundColor Cyan
Write-Host " Description   : Collects Instance informationfrom all active servers" -ForegroundColor Cyan
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

Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "TRUNCATE TABLE dbo.SQL_Instance_Temp" -NonQuery
           
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



function Get-SQLInstanceInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )
    # Create connection to the TARGET server
    $SQLConnection = New-SQLConnection -ServerName $ServerName
   try {
  
         # Open the connection
        $SQLConnection.Open()


   
        $SQLQuery = @"
 DECLARE  @SQLServerStartupMode [int]
                                        ,@SQLAgentStartupMode [int]
                                        ,@LoadID [int]
                                        ,@Position [int]
                                        ,@LoginMode [int]
                                        ,@SQLServerAuditLevel [int]
                                        ,@SQLServerStartupType [char](12)
                                        ,@SQLAgentStartupType [char](12)
                                        ,@SQLServerServiceAccount [varchar](64)
                                        ,@SQLAgentServiceAccount [varchar](64)
                                        ,@SQLServerRegistryKeyPath [varchar](256)
                                        ,@SQLAgentRegistryKeyPath [varchar](256)
                                        ,@InstanceName [nvarchar](128) 
                                        ,@FullInstanceName [nvarchar](128) 
                                        ,@SystemInstanceName [nvarchar](128) 
                                        ,@ErrorLogDirectory [nvarchar](128)
                                        ,@Domain [nvarchar](64)
                                        ,@IPLine [nvarchar](256)
                                        ,@IpAddress [nvarchar](16)
                                        ,@ActiveNode [nvarchar](128)
                                        ,@AuthenticationMode [varchar](64)
                                        ,@IsHadrEnabled [varchar](1) 
                                        ,@PortNumber [varchar](8) 
                                        ,@PageFile [varchar](124)
                                        ,@ClusterNodes [nvarchar](128) 
                                        ,@BinariesPath [nvarchar](128) 
                                        ,@RegistryKeyPath [nvarchar](256) 
                                        ,@RegistryPath1 [nvarchar](256) 
                                        ,@RegistryPath2 [nvarchar](256) 
                                        ,@RegistryPath3 [nvarchar](256) 
                                        ,@SQLServerInstallationLocation [nvarchar](512)

                                IF OBJECT_ID('[Tempdb].[dbo].[#_IPCONFIG_OUTPUT]') IS NOT NULL 
                                DROP TABLE [dbo].[#_IPCONFIG_OUTPUT]

                                IF OBJECT_ID('[Tempdb].[dbo].[#_PAGE_FILE_DETAILS]') IS NOT NULL 
                                DROP TABLE [dbo].[#_PAGE_FILE_DETAILS]

                                IF OBJECT_ID('[Tempdb].[dbo].[#_XPMSVER]') IS NOT NULL 
                                DROP TABLE [dbo].[#_XPMSVER]

                                IF EXISTS (SELECT * FROM [tempdb].[sys].[objects] 
                                            WHERE [name] = '##_SERVER_CONFIG_INFO' 
                                            AND [type] IN (N'U'))
                                DROP TABLE [dbo].[##_SERVER_CONFIG_INFO]

                                CREATE TABLE [dbo].[#_PAGE_FILE_DETAILS] ([data] [varchar](500))

                                CREATE TABLE [dbo].[#_IPCONFIG_OUTPUT] ([IPConfigCommandOutput] [nvarchar](256))

                                CREATE TABLE [dbo].[#_XPMSVER]([IDX] [int] NULL
                                ,[C_NAME] [varchar](100) NULL
                                ,[INT_VALUE] [float] NULL
                                ,[C_VALUE] [varchar](128) NULL ) ON [PRIMARY]

                                CREATE TABLE [dbo].[##_SERVER_CONFIG_INFO](
                                    [Domain] [nvarchar](64) NULL,
                                    [ServerName] [varchar](64) NULL,
                                    [InstanceName] [nvarchar](128) NULL,
                                    [ComputerNamePhysicalNetBIOS] [nvarchar](128) NULL,
                                    [IsClustered] [varchar](13) NULL,
                                    [IsHadrEnabled] [varchar] (1) NULL,
                                    [ClusterNodes] [nvarchar](128) NULL,
                                    [ActiveNode] [nvarchar](128) NULL,
                                    [HostIPAddress] [nvarchar](16) NULL,
                                    [PortNumber] [varchar](8) NULL,
                                    [IsIntegratedSecurityOnly] [varchar](64) NULL,
                                    [AuditLevel] [varchar](38) NOT NULL,
                                    [ProductVersion] [varchar](100) NULL,
                                    [ProductLevel] [varchar](100) NULL,
                                    [ResourceVersion] [varchar](100) NULL,
                                    [ResourceLastUpdateDateTime] [varchar](100) NOT NULL,
                                    [EngineEdition] [varchar](64) NULL,
                                    [BuildClrVersion] [varchar](100) NOT NULL,
                                    [Collation] [varchar](100) NULL,
                                    [CollationID] [varchar](100) NULL,
                                    [ComparisonStyle] [varchar](100) NULL,
                                    [IsFullTextInstalled] [varchar](26) NULL,
                                    [SQLCharset] [varchar](100) NOT NULL,
                                    [SQLCharsetName] [varchar](100) NOT NULL,
                                    [SQLSortOrderID] [varchar](100) NOT NULL,
                                    [SQLSortOrderName] [varchar](100) NOT NULL,
                                    [Platform] [varchar](128) NULL,
                                    [FileDescription] [varchar](128) NULL,
                                    [WindowsVersion] [varchar](128) NULL,
                                    [ProcessorCount] [float] NULL,
                                    [ProcessorType] [varchar](128) NULL,
                                    [PhysicalMemory] [float] NULL,
                                    [ServerPageFile] [varchar](124) NULL,
                                    [SQLInstallationLocation] [nvarchar](512) NULL,
                                    [BinariesPath] [nvarchar](128) NULL,
                                    [ErrorLogsLocation] [nvarchar](128) NULL,
                                    [MSSQLServerServiceStartupUser] [varchar](64) NULL,
                                    [MSSQLAgentServiceStartupUser] [varchar](64) NULL,
                                    [MSSQLServerServiceStartupType] [char](12) NULL,
                                    [MSSQLAgentServiceStartupType] [char](12) NULL,
                                    [InstanceLastStartDate] [datetime] NULL,
                                    [LoadID] [int]) ON [PRIMARY]

                                ------ Finding SQL Server and Agent Service Account Information ------
                                IF SERVERPROPERTY('InstanceName') IS NULL -- Default Instance
                                 BEGIN --default instance
                                    SET @SQLServerRegistryKeyPath='SYSTEM\CurrentControlSET\SERVICES\MSSQLSERVER'
                                    SET @SQLAgentRegistryKeyPath='SYSTEM\CurrentControlSET\SERVICES\SQLSERVERAGENT'
                                 END
                                ELSE 
                                 BEGIN --Named Instance
                                    SET @SQLServerRegistryKeyPath = 'SYSTEM\CurrentControlSET\SERVICES\MSSQL$'
                                    + CAST (SERVERPROPERTY('InstanceName') AS [sysname])

                                    SET @SQLAgentRegistryKeyPath = 'SYSTEM\CurrentControlSET\SERVICES\SQLAgent$'
                                    + CAST (SERVERPROPERTY('InstanceName') AS [sysname]) 
                                 END

                                EXEC [master]..[xp_regread] 'HKEY_LOCAL_MACHINE'
                                                            ,@SQLServerRegistryKeyPath
                                                            ,@value_name = 'Start'
                                                            ,@value = @SQLServerStartupMode OUTPUT 

                                EXEC [master]..[xp_regread] 'HKEY_LOCAL_MACHINE'
                                                            ,@SQLAgentRegistryKeyPath
                                                            ,@value_name = 'Start'
                                                            ,@value = @SQLAgentStartupMode OUTPUT 

                                SET @SQLServerStartupType = (SELECT 'Start Up Mode' = 
                                                                CASE 
                                                                WHEN @SQLServerStartupMode = 2 THEN 'Automatic' 
                                                                WHEN @SQLServerStartupMode = 3 THEN 'Manual' 
                                                                WHEN @SQLServerStartupMode = 4 THEN 'Disabled' 
                                                                END)

                                SET @SQLAgentStartupType = (SELECT 'Start Up Mode' = 
                                                                CASE 
                                                                WHEN @SQLAgentStartupMode = 2 THEN 'Automatic' 
                                                                WHEN @SQLAgentStartupMode = 3 THEN 'Manual' 
                                                                WHEN @SQLAgentStartupMode = 4 THEN 'Disabled' 
                                                                END) 

                                EXEC [master]..[xp_regread] 'HKEY_LOCAL_MACHINE'
                                                            ,@SQLServerRegistryKeyPath
                                                            ,@value_name = 'ObjectName'
                                                            ,@value = @SQLServerServiceAccount OUTPUT 

                                EXEC [master]..[xp_regread] 'HKEY_LOCAL_MACHINE'
                                                            ,@SQLAgentRegistryKeyPath
                                                            ,@value_name = 'ObjectName'
                                                            ,@value = @SQLAgentServiceAccount OUTPUT 

                                ------ Reading registry keys for Binaries, Errorlogs location and Domain ------
                                SET @InstanceName = COALESCE (CONVERT([nvarchar](100)
                                                        , SERVERPROPERTY('InstanceName')), 'MSSQLSERVER'); 
                                IF @InstanceName != 'MSSQLSERVER' 
                                 BEGIN
                                    SET @InstanceName = @InstanceName 
                                 END

                                SET @FullInstanceName = COALESCE (CONVERT([nvarchar](100)
                                                            , SERVERPROPERTY('InstanceName')), 'MSSQLSERVER'); 
                                IF @FullInstanceName != 'MSSQLSERVER' 
                                 BEGIN 
                                    SET @FullInstanceName = 'MSSQL$'+ @FullInstanceName 
                                 END

                                EXEC [master]..[xp_regread]  N'HKEY_LOCAL_MACHINE'
                                                            ,N'Software\Microsoft\Microsoft SQL Server\Instance Names\SQL'
                                                            ,@InstanceName
                                                            ,@SystemInstanceName OUTPUT; 

                                SET @RegistryKeyPath = N'SYSTEM\CurrentControlSET\Services\' 
                                    + @FullInstanceName;

                                SET @RegistryPath1 = N'Software\Microsoft\Microsoft SQL Server\' 
                                    + @SystemInstanceName + '\MSSQLServer\Parameters'; 

                                SET @RegistryPath2 = N'Software\Microsoft\Microsoft SQL Server\' 
                                    + @SystemInstanceName + '\MSSQLServer\supersocketnetlib\TCP\IP1';

                                SET @RegistryPath3 = N'SYSTEM\ControlSET001\Services\Tcpip\Parameters\'; 

                                IF @RegistryPath1 IS NULL 
                                 BEGIN 
                                    SET @InstanceName = COALESCE(CONVERT([nvarchar](100)
                                                    ,SERVERPROPERTY('InstanceName')), 'MSSQLSERVER');
                                 END 

                                EXEC [master]..[xp_regread]  N'HKEY_LOCAL_MACHINE'
                                                            ,N'Software\Microsoft\Microsoft SQL Server\Instance Names\SQL'
                                                            ,@InstanceName
                                                            ,@SystemInstanceName OUTPUT; 

                                EXEC [master]..[xp_regread]  N'HKEY_LOCAL_MACHINE'
                                                            ,@RegistryKeyPath
                                                            ,@value_name = 'ImagePath'
                                                            ,@value = @BinariesPath OUTPUT 

                                EXEC [master]..[xp_regread]  N'HKEY_LOCAL_MACHINE'
                                                            ,@RegistryPath1
                                                            ,@value_name = 'SQLArg1'
                                                            ,@value = @ErrorLogDirectory OUTPUT 

                                EXEC [master]..[xp_regread]  N'HKEY_LOCAL_MACHINE'
                                                            ,@RegistryPath3
                                                            ,@value_name = 'Domain'
                                                            ,@value = @Domain OUTPUT 

                                SELECT @ClusterNodes = COALESCE(@ClusterNodes+', ' ,'') + [Nodename] 
                                FROM [sys].[dm_os_cluster_nodes]

                                IF @ClusterNodes IS NULL
                                 BEGIN
                                    SET @ClusterNodes = 'Not Clustered' 
                                 END


                                SET @IsHadrEnabled = CONVERT([varchar](1), SERVERPROPERTY('IsHadrEnabled'))

                                SET @InstanceName = CONVERT([varchar](25), SERVERPROPERTY('InstanceName'))

                                EXEC [master]..[xp_instance_regread] N'HKEY_LOCAL_MACHINE'
                                                                    ,N'Software\Microsoft\MSSQLServer\MSSQLServer'
                                                                    ,N'AuditLevel'
                                                                    ,@SQLServerAuditLevel OUTPUT

                                EXEC [master]..[xp_instance_regread] N'HKEY_LOCAL_MACHINE'
                                                                    ,N'SOFTWARE\Microsoft\MSSQLServer\Setup'
                                                                    ,N'SQLPath'
                                                                    ,@SQLServerInstallationLocation OUTPUT

                                ------ Finding IP Address ------
                                --INSERT #_IPCONFIG_OUTPUT EXEC [master]..[xp_cmdshell] 'ipconfig'

                                

                                ------ Finding Port Information ------ 
                                IF @InstanceName IS NULL
                                BEGIN
                                    SET @RegistryKeyPath = 'Software\Microsoft\MSSQLServer\MSSQLServer\SuperSocketNetLib\Tcp\' 
                                END
                                ELSE
                                BEGIN
                                    SET @RegistryKeyPath = 'Software\Microsoft\Microsoft SQL Server\' 
                                                + @InstanceName + '\MSSQLServer\SuperSocketNetLib\Tcp\'
                                END

                                EXEC [master]..[xp_regread] 'HKEY_LOCAL_MACHINE'
                                                            ,@RegistryKeyPath
                                                            ,@value_name = 'tcpPort'
                                                            ,@value = @PortNumber OUTPUT -- Port Number

                                ------ Finding Authentication Mode ------
                                EXEC [master]..[xp_instance_regread] N'HKEY_LOCAL_MACHINE'
                                                                    ,N'Software\Microsoft\MSSQLServer\MSSQLServer'
                                                                    ,@value_name = N'LoginMode' 
                                                                    ,@value = @LoginMode OUTPUT

                                SET @AuthenticationMode = (SELECT 'AuTHENtication Mode' = 
                                                            CASE 
                                                            WHEN @LoginMode = 1 THEN 'Windows Authentication' 
                                                            WHEN @LoginMode = 2 THEN 'Mixed Mode Authentication' 
                                                            END ) 

                                ------ Finding Active Node ------
                                EXEC [master]..[xp_regread]  @rootkey = 'HKEY_LOCAL_MACHINE'
                                                            ,@RegistryKeyPath = 'SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'
                                                            ,@value_name = 'ComputerName'
                                                            ,@value = @ActiveNode OUTPUT

                                --INSERT INTO [#_PAGE_FILE_DETAILS] 
                                --EXEC [master]..[xp_cmdshell] 'wmic pagefile list /format:list'

                                SELECT @PageFile = RTRIM(LTRIM([data])) 
                                FROM #_PAGE_FILE_DETAILS 
                                WHERE [data] LIKE 'AllocatedBaseSize%'

                                INSERT INTO [#_XPMSVER]
                                EXEC( 'master.dbo.xp_msver')

                                SELECT 
                                    CONVERT([varchar](64),SERVERPROPERTY('ServerName')) AS [ServerName]
                                    ,@FullInstanceName AS [InstanceName]
                                    ,@ActiveNode AS [ComputerNamePhysicalNetBIOS]
                                    ,UPPER(@Domain) AS [Domain]
                                    ,(CASE
                                        WHEN CONVERT([varchar](100),SERVERPROPERTY('IsClustered')) = 1 THEN 'Clustered'
                                        WHEN SERVERPROPERTY('IsClustered') = 0 THEN 'Not Clustered'
                                        WHEN SERVERPROPERTY('IsClustered') = NULL THEN 'Error'
                                        END) AS [IsClustered]
                                    ,@ClusterNodes AS [ClusterNodes]
                                    ,@IsHadrEnabled as [IsHadrEnabled]
                                    ,@ActiveNode AS [ActiveNode]
                                    ,@PortNumber AS [PortNumber]
                                    ,@AuthenticationMode AS [IsIntegratedSecurityOnly]
                                    ,(CASE 
                                        WHEN @SQLServerAuditLevel = 0 THEN 'None.'
                                        WHEN @SQLServerAuditLevel = 1 THEN 'Successful Logins Only'
                                        WHEN @SQLServerAuditLevel = 2 THEN 'Failed Logins Only'
                                        WHEN @SQLServerAuditLevel = 3 THEN 'Both Failed and Successful Logins Only'
                                        ELSE 'N/A' END) AS [AuditLevel]
                                    ,CONVERT([varchar](100),SERVERPROPERTY('ProductVersion')) AS [ProductVersion]
                                    ,CONVERT([varchar](100),SERVERPROPERTY('ProductLevel')) AS [ProductLevel]
                                    ,ISNULL(CONVERT([varchar](100),SERVERPROPERTY('ResourceVersion'))
                                    ,CONVERT([varchar](100),SERVERPROPERTY('ProductVersion'))) AS [ResourceVersion]
                                    ,ISNULL(CONVERT([varchar](100),SERVERPROPERTY('ResourceLastUpdateDateTime')) 
                                        ,'Information Not Available') AS [ResourceLastUpdateDateTime]
                                    ,CAST (SERVERPROPERTY('Edition') as [varchar](64)) AS [EngineEdition]
                                    ,ISNULL(CONVERT([varchar](100),SERVERPROPERTY('BuildClrVersion')), 'NOT Applicable') AS [BuildClrVersion]
                                    ,CONVERT([varchar](100),SERVERPROPERTY('Collation')) AS [Collation]
                                    ,CONVERT([varchar](100),SERVERPROPERTY('CollationID')) AS [CollationID]
                                    ,CONVERT([varchar](100),SERVERPROPERTY('ComparisonStyle')) AS [ComparisonStyle]
                                    ,(CASE
                                        WHEN CONVERT([varchar](100),SERVERPROPERTY('IsFullTextInstalled')) = 1 THEN 'Full-text is installed'
                                        WHEN SERVERPROPERTY('IsFullTextInstalled') = 0 THEN 'Full-text is not installed'
                                        WHEN SERVERPROPERTY('IsFullTextInstalled') = NULL THEN 'Error'
                                        END) AS [IsFullTextInstalled]
                                    ,ISNULL (CONVERT([varchar](100), SERVERPROPERTY('SqlCharSet')), 'No Information') AS [SQLCharset]
                                    ,ISNULL (CONVERT([varchar](100), SERVERPROPERTY('SqlCharSetName')), 'No Information') AS [SQLCharsetName]
                                    ,ISNULL (CONVERT([varchar](100), SERVERPROPERTY('SqlSortOrder')), 'No Information') AS [SQLSortOrderID]
                                    ,ISNULL (CONVERT([varchar](100), SERVERPROPERTY('SqlSortOrderName')), 'No Information') AS [SQLSortOrderName]
                                    ,(SELECT C_VALUE from [#_XPMSVER] where [C_NAME] = 'Platform') as [Platform]
                                    ,(SELECT C_VALUE from [#_XPMSVER] where [C_NAME] = 'FileDescription' ) as [FileDescription]
                                    ,(SELECT C_VALUE from [#_XPMSVER] where [C_NAME] = 'WindowsVersion') as [WindowsVersion] 
                                    ,(SELECT INT_VALUE from [#_XPMSVER] where [C_NAME] = 'ProcessorCount') as [ProcessorCount] 
                                    ,(SELECT ISNULL(C_VALUE,CAST (INT_VALUE AS VARCHAR(9))) from #_XPMSVER where [C_NAME] = 'ProcessorType') as [ProcessorType] 
                                    ,(SELECT INT_VALUE from [#_XPMSVER] where [C_NAME] = 'PhysicalMemory') as [PhysicalMemory]
                                    ,@PageFile AS [ServerPageFile] 
                                    ,@SQLServerInstallationLocation AS [SQLInstallationLocation]
                                    ,@BinariesPath AS [BinariesPath] 
                                    ,@ErrorLogDirectory AS [ErrorLogsLocation] 
                                    ,@SQLServerServiceAccount AS [MSSQLServerServiceStartupUser]
                                    ,@SQLAgentServiceAccount AS [MSSQLAgentServiceStartupUser]
                                    ,@SQLServerStartupType AS [MSSQLServerServiceStartupType]
                                    ,@SQLAgentStartupType AS [MSSQLAgentServiceStartupType]
                                    ,(SELECT [login_time] FROM [master]..[sysprocesses] WHERE [spid] = 1) AS [InstanceLastStartDate]

                                -- Dropping temporary table
                                IF OBJECT_ID('[Tempdb].[dbo].[#_IPCONFIG_OUTPUT]') IS NOT NULL 
                                DROP TABLE [dbo].[#_IPCONFIG_OUTPUT]

                                IF OBJECT_ID('[Tempdb].[dbo].[#_PAGE_FILE_DETAILS]') IS NOT NULL 
                                DROP TABLE [dbo].[#_PAGE_FILE_DETAILS]
"@
        
        $SQLDataSet = New-Object System.Data.DataSet
        $SQLAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SQLQuery, $SQLConnection)
        [void]$SQLAdapter.Fill($SQLDataSet)
        
        $data = $SQLDataSet.Tables[0]
        
        foreach ($dataItem in $data.Rows) {
            # Build INSERT statement with parameterized values to prevent SQL injection
            $sql = @"
INSERT INTO SQL_Instance_Temp (
    ServerName, InstanceName, ComputerNamePhysicalNetBIOS, Domain,
    IsClustered, ClusterNodes, ActiveNode, HostIPAddress, PortNumber,
    IsIntegratedSecurityOnly, AuditLevel, ProductVersion, ProductLevel,
    ResourceVersion, ResourceLastUpdateDateTime, EngineEdition, BuildClrVersion,
    Collation, CollationID, ComparisonStyle, IsHadrEnabled, IsFullTextInstalled,
    SQLCharset, SQLCharsetName, SQLSortOrderID, SQLSortOrderName, Platform,
    FileDescription, WindowsVersion, ProcessorCount, ProcessorType, PhysicalMemory,
    ServerPageFile, SQLInstallationLocation, BinariesPath, ErrorLogsLocation,
    MSSQLServerServiceStartupUser, MSSQLAgentServiceStartupUser,
    MSSQLServerServiceStartupType, MSSQLAgentServiceStartupType, InstanceLastStartDate
)
SELECT 
    '$ServerName', '$($dataItem.InstanceName)', '$($dataItem.ComputerNamePhysicalNetBIOS)',
    '$($dataItem.Domain)', '$($dataItem.IsClustered)', '$($dataItem.ClusterNodes)',
    '$($dataItem.ActiveNode)', '', $($dataItem.PortNumber),
    '$($dataItem.IsIntegratedSecurityOnly)', '$($dataItem.AuditLevel)',
    '$($dataItem.ProductVersion)', '$($dataItem.ProductLevel)',
    '$($dataItem.ResourceVersion)', '$($dataItem.ResourceLastUpdateDateTime)',
    '$($dataItem.EngineEdition)', '$($dataItem.BuildClrVersion)',
    '$($dataItem.Collation)', $($dataItem.CollationID), '$($dataItem.ComparisonStyle)',
    '$($dataItem.IsHadrEnabled)', '$($dataItem.IsFullTextInstalled)',
    $($dataItem.SQLCharset), '$($dataItem.SQLCharsetName)',
    $($dataItem.SQLSortOrderID), '$($dataItem.SQLSortOrderName)',
    '$($dataItem.Platform)', '$($dataItem.FileDescription)',
    '$($dataItem.WindowsVersion)', $($dataItem.ProcessorCount),
    '$($dataItem.ProcessorType)', $($dataItem.PhysicalMemory),
    '$($dataItem.ServerPageFile)', '$($dataItem.SQLInstallationLocation)',
    '$($dataItem.BinariesPath)', '$($dataItem.ErrorLogsLocation)',
    '$($dataItem.MSSQLServerServiceStartupUser)',
    '$($dataItem.MSSQLAgentServiceStartupUser)',
    '$($dataItem.MSSQLServerServiceStartupType)',
    '$($dataItem.MSSQLAgentServiceStartupType)',
    '$($dataItem.InstanceLastStartDate)'
"@
            
            Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query $sql -NonQuery
        }
    }
    catch {
           Write-Error "Error collecting instance information from ${ServerName}: $_"
           Write-SqlLog -Message "Error collecting instance information from ${ServerName}: $_" -Level ERROR -ServerName $ServerName -ScriptName $ScriptName
        throw
    }

}  


$result = Invoke-SqlQuery -ConnectionString $MonitorconnectionString -Query "SELECT ServerName from ServerList WHERE ActiveInd = 1 ORDER BY ServerName"

Write-Host "Starting collection for $($result.Count) servers..." -ForegroundColor Cyan


foreach ($row in $result) {


    $ServerName = $row.ServerName
    
    try {
        Get-SQLInstanceInformation -ServerName $ServerName -ErrorAction Stop
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
Write-Host "SQL Instance collection run completed." -ForegroundColor Cyan
Write-Host "End Time       : $endDTM"
Write-Host "Elapsed Time   : $(($endDTM-$startDTM).TotalSeconds) seconds"
Write-Host "=================================================================================================" -ForegroundColor Yellow


    


