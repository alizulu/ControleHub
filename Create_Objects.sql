-- =============================================
-- Database Script: Create Database Objects
-- Server: SQL1
-- Generated: 2026-04-24 14:12:40
-- =============================================
SET NOCOUNT ON
GO


BEGIN
    PRINT 'Dropping existing tables...';

    DROP TABLE IF EXISTS dbo.ClusterResource_Temp;
    DROP TABLE IF EXISTS dbo.Cluster_Temp;
    DROP TABLE IF EXISTS dbo.Disks_Temp;
    DROP TABLE IF EXISTS dbo.Services_Temp;
    DROP TABLE IF EXISTS dbo.SQL_Backups_Temp;
    DROP TABLE IF EXISTS dbo.SQL_DataFiles_Temp;
    DROP TABLE IF EXISTS dbo.SQL_DBProperties_Temp;
    DROP TABLE IF EXISTS dbo.SQL_Instance_Temp;
    DROP TABLE IF EXISTS dbo.SQL_Jobs_Temp;
    DROP TABLE IF EXISTS dbo.ServerList;
    DROP TABLE IF EXISTS dbo.Environment;
END
-- =============================================
-- TABLES
-- =============================================

-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[Cluster_Temp]'
-- =============================================

CREATE TABLE [dbo].[Cluster_Temp](
	[ServerName] [nvarchar](128) NULL,
	[PhysicalComputerName] [sysname],
	[DTM] [datetime] NULL
) ON [PRIMARY]

ALTER TABLE [dbo].[Cluster_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO

-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[ClusterResource_Temp]'
-- =============================================

CREATE TABLE [dbo].[ClusterResource_Temp](
	[ServerName] [nvarchar](128) NULL,
	[ClusterName] [sysname],
	[ClusterState] [varchar](20),
	[QuorumType] [varchar](50),
	[Witness] [varchar](255),
	[NodeName] [sysname],
	[NodeState] [varchar](20),
	[ResourceName] [sysname],
	[ResourceType] [varchar](100),
	[ResourceState] [varchar](20),
	[OwnerNode] [sysname],
	[DTM] [datetime] NULL
) ON [PRIMARY]

ALTER TABLE [dbo].[ClusterResource_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO


-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[Disks_Temp]'
-- =============================================

CREATE TABLE [dbo].[Disks_Temp](
	[ServerName] [nvarchar](128) NULL,
	[Drive] [varchar](200) NULL,
	[VolumeName] [varchar](100) NULL,
	[TotalSize] [numeric](18, 0) NULL,
	[FreeSpace] [numeric](18, 0) NULL,
	[DTM] [datetime] NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[Disks_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO


-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[Environment]'
-- =============================================

CREATE TABLE dbo.Environment (
    EnvironmentID INT NOT NULL PRIMARY KEY,
    EnvironmentName VARCHAR(50) NOT NULL
);

GO

-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[ServerList]'
-- =============================================

CREATE TABLE [dbo].[ServerList](
	[ServerID] [int] IDENTITY(1,1) NOT NULL,
    [ServerName] nvarchar(128) NOT NULL,
	[EnvironmentID] [int] NOT NULL,
	[CreateDateTime] [datetime] NOT NULL DEFAULT SYSDATETIME(),
	[LastActiveDateTime] [datetime] NULL,
	[ActiveInd] [bit] NOT NULL,
 CONSTRAINT [PK_ServerList] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

ALTER TABLE [dbo].[ServerList] ADD  DEFAULT ((1)) FOR [ActiveInd]
ALTER TABLE [dbo].[ServerList]  WITH CHECK ADD  CONSTRAINT [FK_ServerList_Environment] FOREIGN KEY([EnvironmentID])
REFERENCES [dbo].[Environment] ([EnvironmentID])
ALTER TABLE [dbo].[ServerList] CHECK CONSTRAINT [FK_ServerList_Environment]
GO


-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[Services_Temp]'
-- =============================================

CREATE TABLE [dbo].[Services_Temp](
	[ServerName] [nvarchar](128) NULL,
	[Service_Name] [nvarchar](400) NULL,
	[Display_Name] [nvarchar](400) NULL,
	[RunningState] [varchar](50) NULL,
	[StartUpName] [nvarchar](400) NULL,
	[ErrorControl] [nvarchar](50) NULL,
	[last_startup_time] [datetime] NULL,
	[Service_Account] [nvarchar](100) NULL,
	[StartMode] [nvarchar](50) NULL,
	[Status] [nvarchar](50) NULL,
	[DTM] [datetime] NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[Services_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO

-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[SQL_Backups_Temp]'
-- =============================================

CREATE TABLE [dbo].[SQL_Backups_Temp](
	[ServerName] [nvarchar](128) NULL,
	[DatabaseName] [varchar](100) NULL,
	[Type] [char](1) NULL,
	[Media] [char](3) NULL,
	[Backup_size] [decimal](10, 2) NULL,
	[Backup_Start_Date] [datetime] NULL,
	[Backup_Finish_Date] [datetime] NULL,
	[Physical_Device_Name] [varchar](260) NULL,
	[DTM] [datetime] NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[SQL_Backups_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO

-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[SQL_DataFiles_Temp]'
-- =============================================


CREATE TABLE [dbo].[SQL_DataFiles_Temp](
	[ServerName] [nvarchar](128) NULL,
	[DataBaseName] [varchar](100) NULL,
	[LogicalFileName] [varchar](500) NULL,
	[Filename] [varchar](500) NULL,
	[FileId] [int] NULL,
	[GroupId] [int] NULL,
	[GroupName] [varchar](100) NULL,
	[MaxSize] [varchar](55) NULL,
	[Growth] [varchar](55) NULL,
	[DataFileSize] [decimal](10, 2) NULL,
	[DataFileUsedSpace] [decimal](10, 2) NULL,
	[DataFileFreeSpace] [decimal](10, 2) NULL,
	[PctFreeSpace] [decimal](10, 2) NULL,
	[PctUsed] [decimal](10, 2) NULL,
	[DTM] [datetime] NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[SQL_DataFiles_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO


-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[SQL_DBProperties_Temp]'
-- =============================================

CREATE TABLE [dbo].[SQL_DBProperties_Temp](
	[Servername] [nvarchar](128) NOT NULL,
	[DatabaseName] [nvarchar](128) NULL,
	[owner] [nvarchar](128) NULL,
	[created] [nvarchar](19) NULL,
	[dbid] [smallint] NULL,
	[Status] [nvarchar](50) NULL,
	[Updateability] [nvarchar](50) NULL,
	[UserAccess] [nvarchar](50) NULL,
	[Recovery] [nvarchar](50) NULL,
	[Version] [nvarchar](50) NULL,
	[Collation] [nvarchar](50) NULL,
	[SQLSortOrder] [nvarchar](50) NULL,
	[IsAutoClose] [nvarchar](10) NULL,
	[IsAutoShrink] [nvarchar](10) NULL,
	[IsInStandby] [nvarchar](10) NULL,
	[IsTornPageDetectionEnabled] [nvarchar](10) NULL,
	[IsAnsiNullDefault] [nvarchar](10) NULL,
	[IsAnsiNullsEnabled] [nvarchar](10) NULL,
	[IsAnsiPaddingEnabled] [nvarchar](10) NULL,
	[IsAnsiWarningsEnabled] [nvarchar](10) NULL,
	[IsArithmeticAbortEnabled] [nvarchar](10) NULL,
	[IsAutoCreateStatistics] [nvarchar](10) NULL,
	[IsAutoUpdateStatistics] [nvarchar](10) NULL,
	[IsCloseCursorsOnCommitEnabled] [nvarchar](10) NULL,
	[IsFullTextEnabled] [nvarchar](10) NULL,
	[IsLocalCursorsDefault] [nvarchar](10) NULL,
	[IsNullConcat] [nvarchar](10) NULL,
	[IsNumericRoundAbortEnabled] [nvarchar](10) NULL,
	[IsQuotedIdentifiersEnabled] [nvarchar](10) NULL,
	[IsRecursiveTriggersEnabled] [nvarchar](10) NULL,
	[IsMergePublished] [nvarchar](10) NULL,
	[IsPublished] [nvarchar](10) NULL,
	[IsSubscribed] [nvarchar](10) NULL,
	[IsSyncWithBackup] [nvarchar](10) NULL,
	[dbsize] [decimal](15, 2) NULL,
	[cmptlevel] [smallint] NULL,
	[DTM] [datetime] NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[SQL_DBProperties_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO


-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[SQL_Instance_Temp]'
-- =============================================

CREATE TABLE [dbo].[SQL_Instance_Temp](
	[ServerName] [nvarchar](128) NOT NULL,
	[instancename] [varchar](50) NULL,
	[ComputerNamePhysicalNetBIOS] [varchar](50) NULL,
	[Domain] [varchar](20) NULL,
	[isclustered] [varchar](20) NULL,
	[ClusterNodes] [varchar](250) NULL,
	[ActiveNode] [varchar](50) NULL,
	[HostIPAddress] [varchar](40) NULL,
	[PortNumber] [int] NULL,
	[IsIntegratedSecurityOnly] [varchar](50) NULL,
	[AuditLevel] [varchar](50) NULL,
	[ProductVersion] [varchar](20) NULL,
	[ProductLevel] [varchar](10) NULL,
	[ResourceVersion] [varchar](20) NULL,
	[ResourceLastUpdateDateTime] [varchar](50) NULL,
	[engineedition] [varchar](50) NULL,
	[BuildClrVersion] [varchar](50) NULL,
	[Collation] [varchar](50) NULL,
	[CollationID] [int] NULL,
	[ComparisonStyle] [int] NULL,
	[IsHadrEnabled] [int] NULL,
	[IsFullTextInstalled] [varchar](50) NULL,
	[SQLCharset] [int] NULL,
	[SQLCharsetName] [varchar](50) NULL,
	[SQLSortOrderID] [int] NULL,
	[SQLSortOrderName] [varchar](50) NULL,
	[Platform] [varchar](50) NULL,
	[FileDescription] [varchar](50) NULL,
	[WindowsVersion] [varchar](50) NULL,
	[ProcessorCount] [int] NULL,
	[ProcessorType] [varchar](50) NULL,
	[PhysicalMemory] [int] NULL,
	[ServerPageFile] [varchar](50) NULL,
	[SQLInstallationLocation] [varchar](400) NULL,
	[BinariesPath] [varchar](400) NULL,
	[ErrorLogsLocation] [varchar](400) NULL,
	[MSSQLServerServiceStartupUser] [varchar](50) NULL,
	[MSSQLAgentServiceStartupUser] [varchar](50) NULL,
	[MSSQLServerServiceStartupType] [varchar](50) NULL,
	[MSSQLAgentServiceStartupType] [varchar](50) NULL,
	[InstanceLastStartDate] [datetime] NULL,
	[DTM] [datetime] NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[SQL_Instance_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO


-- =============================================
 PRINT 'CREATING TABLE: Table: [dbo].[SQL_Jobs_Temp]'
-- =============================================

CREATE TABLE [dbo].[SQL_Jobs_Temp](
	[ServerName] nvarchar(128) NULL,
	[DatabaseName] [nvarchar](250) NULL,
	[JobName] [nvarchar](400) NULL,
	[LastStep] [nvarchar](400) NULL,
	[LastRunOutCome] [nvarchar](50) NULL,
	[Enabled] [int] NULL,
	[ScheduleCount] [int] NULL,
	[StepCount] [int] NULL,
	[date_created] [datetime] NULL,
	[date_modified] [datetime] NULL,
	[StartDate] [datetime] NULL,
	[FinishDate] [datetime] NULL,
	[DurationSec] [bigint] NULL,
	[DurationSecFormatted] [nvarchar](50) NULL,
	[AvgDurationSec] [bigint] NULL,
	[AvgDurationSecFormatted] [nvarchar](50) NULL,
	[NextRunDate] [datetime] NULL,
	[StepCommand] [nvarchar](500) NULL,
	[HistoryMessage] [nvarchar](500) NULL,
	[DTM] [datetime] NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[SQL_Jobs_Temp] ADD  DEFAULT (getdate()) FOR [DTM]
GO


-- =============================================
-- DEFAULT DATA INSERTION
-- =============================================

-- Default data for Environment table
PRINT '';
PRINT 'Seeding Environment table...';

IF NOT EXISTS (SELECT 1 FROM dbo.Environment)
BEGIN
    INSERT INTO dbo.Environment (EnvironmentID, EnvironmentName)
    VALUES 
        (1, 'PRODUCTION'),
        (2, 'PRE-PRODUCTION'),
        (3, 'TEST'),
        (4, 'DEVELOPMENT');
END
GO

PRINT 'Seeding ServerList...';

IF NOT EXISTS (SELECT 1 FROM dbo.ServerList)
BEGIN
    INSERT INTO dbo.ServerList (ServerName, EnvironmentID)
    VALUES 
        ('SQL1', 4),
        ('SQL2', 4),
        ('SQL3', 4);
END
GO

-- =============================================
-- END OF SCRIPT
-- =============================================
-- Summary:

--   Default Data Added: Environment, ServerList

-- =============================================
