$KBLink = @{
"SQLServer Collation:"= "<a href='https://www.inforxtreme.com/espublic//DLSearch/51422/M3BE_15_1_4_SQLServer2016_Best%20Practice.pdf'>M3 Best Practice Guide</a>";
"SQLServer Memory Max"= "<a href='https://www.inforxtreme.com/espublic//DLSearch/51422/M3BE_15_1_4_SQLServer2016_Best%20Practice.pdf'>M3 Best Practice Guide</a>";
"SQLServer DOP Max:"= "<a href='https://www.inforxtreme.com/espublic//DLSearch/51422/M3BE_15_1_4_SQLServer2016_Best%20Practice.pdf'>M3 Best Practice Guide</a>";
"SQLServer Full Text Installed:"= "<a href='https://www.inforxtreme.com/espublic//DLSearch/51422/M3BE_15_1_4_SQLServer2016_Best%20Practice.pdf'>M3 Best Practice Guide</a>";
"SQLServer Master DB:"= "Master DB on OS Drive is not recommended";
"Outdated backups:"= "Critical: Check backup tasks";
"Database on on OS Drive:"= "Critical: Do not place database on drive C:"
}


$Check_traceflags = @"
DBCC TRACESTATUS(-1)
"@

$Check_TEMPDB_Count = @"
SELECT
name AS FileName,
size*1.0/128 AS FileSizeinMB,
CASE max_size
WHEN 0 THEN 'Autogrowth is off.'
WHEN -1 THEN 'Autogrowth is on.'
ELSE 'Log file will grow to a maximum size of 2 TB.'
END AutogrowthStatus,
growth AS 'GrowthValue',
'GrowthIncrement' =
CASE
WHEN growth = 0 THEN 'Size is fixed and will not grow.'
WHEN growth > 0
AND is_percent_growth = 0
THEN 'Growth value is in 8-KB pages.'
ELSE 'Growth value is a percentage.'
END
FROM tempdb.sys.database_files;
GO

"@


$Check_TEMPDB1 = @"
WITH 
TempdbDataFile AS 
( 
SELECT  size, 
        max_size, 
        growth, 
        is_percent_growth, 
        AVG(CAST(size AS decimal(18,4))) OVER() AS AvgSize, 
        AVG(CAST(max_size AS decimal(18,4))) OVER() AS AvgMaxSize, 
        AVG(CAST(growth AS decimal(18,4))) OVER() AS AvgGrowth 
FROM tempdb.sys.database_files  
WHERE   type_desc = 'ROWS' 
        AND 
        state_desc = 'ONLINE' 
) 
SELECT  CASE WHEN (SELECT scheduler_count FROM sys.dm_os_sys_info)  
                  BETWEEN COUNT(1)  
                      AND COUNT(1) * 2 
             THEN 'YES' 
             ELSE 'NO' 
        END 
        AS MultipleDataFiles, 
        CASE SUM(CASE size WHEN AvgSize THEN 1 ELSE 0 END)  
             WHEN COUNT(1) THEN 'YES' 
             ELSE 'NO' 
        END AS EqualSize, 
        CASE SUM(CASE max_size WHEN AvgMaxSize THEN 1 ELSE 0 END)  
             WHEN COUNT(1) THEN 'YES'  
             ELSE 'NO'  
        END AS EqualMaxSize, 
        CASE SUM(CASE growth WHEN AvgGrowth THEN 1 ELSE 0 END)  
             WHEN COUNT(1) THEN 'YES' 
             ELSE 'NO' 
        END AS EqualGrowth, 
        CASE SUM(CAST(is_percent_growth AS smallint))  
             WHEN 0 THEN 'YES' 
             ELSE 'NO' 
        END AS NoFilesWithPercentGrowth  
FROM TempdbDataFile; 

"@

$Check_PageLife = @"
select counter_name , cntr_value as PLE_sec
from sys.dm_os_performance_counters
where counter_name = 'Page life expectancy'
and object_name like '%Manager%'
order by counter_name asc; 
"@

$Check_Latency = @"
select cast(db_name(mf.database_id) as nvarchar(20)) as database_name
, cast(mf.physical_name as nvarchar(100)) as datafile_name
, cast(vfs.size_on_disk_bytes/1024/1024. as numeric(10,1)) as size_on_disk_MB
, vfs.num_of_reads
, vfs.io_stall_read_ms
, vfs.num_of_writes
, vfs.io_stall_write_ms
, vfs.io_stall
, cast(vfs.io_stall_read_ms/(1.0+vfs.num_of_reads) as numeric(10,1)) as avg_read_latency_ms
, cast(vfs.io_stall_write_ms/(1.+vfs.num_of_writes) as numeric(10,1)) as avg_write_latency_ms
, cast((vfs.io_stall)/(1.+vfs.num_of_reads+num_of_writes) as numeric(10,1)) as avg_disk_latency_ms
, cast(vfs.num_of_bytes_read/(1.+vfs.num_of_reads) as numeric(10,1)) as bytes_per_read
, cast(vfs.num_of_bytes_written/(1.+vfs.num_of_writes) as numeric(10,1)) as bytes_per_write
from sys.dm_io_virtual_file_stats(null,null) as vfs
join sys.master_files as mf on mf.database_id = vfs.database_id and mf.file_id = vfs.file_id
order by datafile_name asc;
"@

$Get_InstanceStart = "select sqlserver_start_time as last_instance_start from sys.dm_os_sys_info;"
$Get_Waitstats = @"
with os_waits as (
select wait_type
, waiting_tasks_count
, wait_time_ms
, max_wait_time_ms
, signal_wait_time_ms
, wait_time_ms-signal_wait_time_ms as resource_wait_time_ms
, wait_time_ms*100./sum(wait_time_ms) over() as percentage
from sys.dm_os_wait_stats
where wait_time_ms>0
and wait_type not in ( 
N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR'
, N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH'
, N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE'
, N'CHKPT', N'CLR_AUTO_EVENT'
, N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE'
, N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE'
, N'DBMIRROR_WORKER_QUEUE', N'DBMIRRORING_CMD'
, N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE'
, N'EXECSYNC', N'FSAGENT'
, N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX'
, N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
, N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE'
, N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE'
, N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP'
, N'LOGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE'
, N'PWAIT_ALL_COMPONENTS_INITIALIZED'
, N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'
, N'QDS_SHUTDOWN_QUEUE'
, N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'
, N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE'
, N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH'
, N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP'
, N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY'
, N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP'
, N'SLEEP_SYSTEMTASK', N'SLEEP_TASK'
, N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT'
, N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH'
, N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP'
, N'SQLTRACE_WAIT_ENTRIES', N'WAIT_FOR_RESULTS'
, N'WAITFOR', N'WAITFOR_TASKSHUTDOWN'
, N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG'
, N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN'
, N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
, N'TRACEWRITE'
) )
select top 5
wait_type
, cast(percentage as numeric(5,1)) as pct
, cast(wait_time_ms*1./waiting_tasks_count as numeric(10,1)) as avg_wait_ms
, cast(resource_wait_time_ms*1./waiting_tasks_count as numeric(10,1)) as avg_res_ms
, cast(signal_wait_time_ms*1./waiting_tasks_count as numeric(10,1)) as avg_sig_ms
, waiting_tasks_count
, wait_time_ms
, resource_wait_time_ms
, signal_wait_time_ms
, max_wait_time_ms
from os_waits
where percentage > 1 
order by percentage desc
option (maxdop 1);
"@

$Check_Stats = @"
SELECT OBJECT_NAME(id) as TableName,name as IndexName,STATS_DATE(id, indid) as StatsUpdated ,rowmodctr as ModCounter
FROM sys.sysindexes
WHERE STATS_DATE(id, indid)<=DATEADD(DAY,-7,GETDATE()) 
and rowmodctr > 0
and left(name,1) <> '_'
AND id IN (SELECT object_id FROM sys.tables)
"@

$Check_Frag = @"
select db_name() as database_name
, object_schema_name(ps.object_id,db_id())+'.'+ object_name(ps.object_id, db_id()) as tblName
, si.name ndxName
, ps.index_type_desc
, stats_date(si.object_id,si.index_id) as last_stats_date
, ps.index_depth
, ps.index_level
, cast(ps.avg_fragmentation_in_percent as numeric(5,1)) as avg_fragmentation_in_percent
, cast(ps.avg_fragment_size_in_pages as numeric(5,1)) as avg_fragment_size_in_pages
, ps.fragment_count
, ps.page_count
, ps.record_count
from sys.dm_db_index_physical_stats(db_id(),null,null,null,'sampled') ps 
join sys.indexes si on ps.object_id=si.object_id and ps.index_id=si.index_id
where ps.page_count>1000
and ps.avg_fragmentation_in_percent>=30
order by ps.avg_fragmentation_in_percent desc,tblName asc,si.name asc;
"@


$Check_SlowQueries = @"
select distinct top 10
substring (st.text,(qs.statement_start_offset/2)+1,
((case qs.statement_end_offset
when -1 then datalength (st.text)
else qs.statement_end_offset
end - qs.statement_start_offset)/ 2)+ 1) as statement_txt
, isnull(qs.execution_count/datediff(ss, qs.creation_time, getdate()), 0) as 'calls_per_sec'
, datediff(ss,qs.creation_time,getdate()) as 'age_in_cache_sec'
, (qs.total_logical_reads+qs.total_logical_writes) as tot_logic_io
, qs.total_physical_reads as tot_phys_re
, (qs.total_physical_reads/qs.execution_count) as avg_phys_re
, qs.total_logical_reads as total_logic_re
, (qs.total_logical_reads/qs.execution_count) as avg_logic_re
, qs.total_logical_writes as tot_logic_wr
, (qs.total_logical_writes/qs.execution_count) as avg_logic_wr
, qs.execution_count as exec_cnt
, qs.total_elapsed_time / 1000000 as tot_et_sec
, (qs.total_elapsed_time / qs.execution_count / 1000) as avg_et_ms
, qs.total_worker_time / 1000000 as tot_wt_sec
, (qs.total_worker_time / qs.execution_count / 1000) as avg_wt_ms
from sys.dm_exec_query_stats qs
cross apply sys.dm_exec_sql_text (qs.sql_handle) st
-- order by tot_logic_io desc;
order by avg_et_ms desc;
-- order by avg_wt_ms desc;
-- order by tot_et_sec desc;
-- order by tot_wt_sec desc;
-- the end of the script
"@


$Check_MemoryDumps = @"
select count(*) as DumpCount
FROM
[sys].[dm_server_memory_dumps]
WHERE [creation_time] >= DATEADD(Month, -1, GETDATE());
"@

$Check_VLF = @"
DBCC LOGINFO
"@

$Check_Replicated = @"
select name, is_published, is_subscribed, is_merge_published, is_distributor
  from sys.databases
  where is_published = 1 or is_subscribed = 1 or
  is_merge_published = 1 or is_distributor = 1
"@

$traceflags = @{
101 = 'Verbose Merge Replication logging output for troubleshooting Merger repl performance'
102 = 'Verbose Merge Replication logging to msmerge_history table for troubleshooting Merger repl performance'
105 = 'Join more than 16 tables in SQL server 6.5'
106 = 'This enables you to see the messages that are sent to and from the Publisher, if you are using Web Synchronization'
107 = 'Alter input rules for decimal numbers'
168 = 'Bugfix in ORDER BY'
205 = 'Log usage of AutoStat/Auto Update Statistics'
253 = 'Prevent adhoc query plans from staying in cache (SQL 2005)'
260 = 'Prints Extended stord proc DLL versioning info'
272 = 'Grenerates a log record per identity increment. Can be users to convert SQL 2012 back to old style Indetity behaviour'
302 = 'Output Index Selection info'
310 = 'Outputs info about actual join order'
323 = 'Outputs detailed info about updates'
345 = 'Changes join order selection logic in SQL Server 6.5'
445 = 'Prints â€compile issuedâ€ message in the errorlog for each compiled statement, when used together with 3605'
610 = 'Minimally logged inserts to indexed tables'
652 = 'Disable page pre-fetching scans'
661 = ' Disable the ghost record removal process'
662 = 'Prints detailed information about the work done by the ghost cleanup task when it runs next. Use TF 3605 to see the output in the errorlog'
806 = ' Turn on Page Audit functionality, to verify page validity'
818 = ' Turn on ringbuffer to store info about IO write operations. Used to troubleshoot IO problems'
830 = 'Disable diagnostics for stalled and stuck I/O operations'
834 = 'Large Page Allocations'
836  = 'Use the max server memory option for the buffer pool'
845 = 'Enable Lock pages in Memory on Standard Edition'
902 = 'Bypass Upgrade Scripts'
1117 = 'Simultaneous Autogrowth in Multiple-file database'
1118 = 'Force Uniform Extent Allocation'
1119 = 'Turns of mixed extent allocation (Similar to 1118?)'
1140 = 'Fix for growing tempdb in special cases'
1200 = 'Prints detailed lock information'
1124 = 'Unknown. Has been reportedly found turned on in some SQL Server instances running Dynamics AX. Also rumored to be invalid in public builds of SQL Server'
1204 = 'Returns info about deadlocks'
1211 = 'Disables Lock escalation caused by mem pressure'
1222 = 'Returns Deadlock info in XML format'
1224 = 'Disables lock escalation based on number of locks'
1236 = 'Fixes performance problem in scenarios with high lock activity in SQL 2012 and SQL 2014'
1264 = 'Collect process names in non-yielding scenario memory dumps'
1448 = 'Alters replication logreader functionality'
1462 = 'Disable Mirroring Log compression'
1717 = 'MSShipped bit will be set automatically at Create time when creating stored procedures'
1806 = 'Disable Instant File Initialization'
1807 = 'Enable option to have database files on SMB share for SQL Server 2008 and 2008R2'
2301 = 'Enable advanced decision support optimizations'
2312 = 'Forces the query optimizer to use the SQL Server 2014 version of the cardinality estimator when creating the query plan when running SQL Server 2014 with database compatibility level 110'
2335 = 'Generates Query Plans optimized for less memory'
2340 = 'Disable specific SORT optimization in Query Plan'
2371 = 'Change threshold for auto update stats'
2372 = 'Displays memory utilization during the optimization process'
2373 = 'Displays memory utilization during the optimization process'
2388 = 'Change DBCC SHOW_STATISTICS output to show stats history and lead key type such as known ascending keys'
2389 = 'Enable auto-quick-statistics update for known ascending keys'
2390 = 'Enable auto-quick-statistics update for all columns'
2430 = 'Fixes performance problem when using large numbers of locks'
2453 = 'Allow a table variable to trigger recompile when enough number of rows are changed with may allow the query optimizer to choose a more efficient plan.'
2470 = 'Fixes performance problem when using AFTER triggers on partitioned tables'
2514 = 'Verbose Merge Replication logging to msmerge_history table for troubleshooting Merger repl performance'
2528 = 'Disables parallellism in CHECKDB etc.'
2529 = 'Displays memory usage for DBCC commands when used with TF 3604.'
2537 = 'Allows you to see inactive records in transactionlog using fn_dblog'
2540 = 'Unknown, but related to controlling the contents of a memorydump'
2541 = 'Unknown, but related to controlling the contents of a memorydump'
2542 = 'Unknown, but related to controlling the contents of a memorydump'
2543 = 'Unknown, but related to controlling the contents of a memorydump'
2544 = 'Produces a full memory dump'
2545 = 'Unknown, but related to controlling the contents of a memorydump'
2546 = 'Dumps all threads for SQL Server in the dump file'
2547 = 'Unknown, but related to controlling the contents of a memorydump'
2548 = 'Shrink will run faster with this trace flag if there are LOB pages that need conversion and/or compaction, because that actions will be skipped.'
2549 = 'Faster CHECKDB'
2550 = 'Unknown, but related to controlling the contents of a memorydump'
2551 = 'Produces a filtered memory dump'
2552 = 'Unknown, but related to controlling the contents of a memorydump'
2553 = 'Unknown, but related to controlling the contents of a memorydump'
2554 = 'Unknown, but related to controlling the contents of a memorydump'
2555 = 'Unknown, but related to controlling the contents of a memorydump'
2556 = 'Unknown, but related to controlling the contents of a memorydump'
2557 = 'Unknown, but related to controlling the contents of a memorydump'
2558 = 'Unknown, but related to controlling the contents of a memorydump'
2559 = 'Unknown, but related to controlling the contents of a memorydump'
2562 = 'Faster CHECKDB'
2588 = 'Get more information about undocumented DBCC commands'
2861 = 'Keep zero cost plans in cache'
3004 = 'Returns more info about Instant File Initialization'
3014 = 'Returns more info about backups to the errorlog'
3023 = 'Enable the CHECKSUM option if backup utilities do not expose the option'
3042 = 'Alters backup compression functionality'
3101 = 'Fix performance problems when restoring database with CDC'
3205 = 'Disable HW compression for backup to tape drives'
3213 = 'Output buffer info for backups to ERRORLOG'
3226 = 'Turns off Backup Successful messages in errorlog'
3422 = 'Log record auditing'
3502 = 'Writes info about checkpoints to teh errorlog'
3505 = 'Disables automatic checkpointing'
3604 = 'Redirect DBCC command output to query window'
3605 = 'Directs the output of some Trace Flags to the Errorlog'
3607 = 'Skip recovery on startup'
3608 = 'Recover only Master db at startup'
3609 = 'Do not create tempdb at startup'
3625 = 'Masks some errormessages'
3656 = 'Enables resolve of all callstacks in extended events'
3659 = ' Enables logging all errors to errorlog during server startup'
3688 = 'Removes messages to errorlog about traces started and stopped'
3801 = 'Prohibits use of USE DB statement'
3923 = 'Let SQL Server throw an exception to the application when the 3303 warning message is raised.'
4013 = 'Log each new connection the errorlog'
4022 = 'Bypass Startup procedures'
4130 = 'XML performance fix'
4134 = 'Bugfix for error: parallell query returning different results every time'
4135 = 'Bugfix for error inserting to temp table'
4136 = 'Parameter Sniffing behaviour alteration'
4137 = 'Fix for bad performance in queries with several AND criteria'
4138 = 'Fixes performance probles with certain queries that use TOP statement'
4139 = 'Fix for poor cardinality estimation when the ascending key column is branded as stationary'
4199 = 'Turn on all optimizations'
4606 = 'Ignore domain policy about weak password'
4616 = 'Alters server-level metadata visibility'
6498 = 'Increased query compilation scalability in SQL Server 2014'
6527 = 'Alters mem dump functionality'
6534 = 'This fix updates the sorting algorithm to include angular vectorization techniques that significantly improve the LineString performance'
7300 = 'Outputs extra info about linked server errors'
7470 = 'Fix for sort operator spills to tempdb in SQL Server 2012 or SQL Server 2014 when estimated number of rows and row size are correct'
7502 = 'Disable cursor plan caching for extended stored procedures'
7806 = 'Enables DAC on SQL Server Express'
7826 = 'Disable Connectivity ringbuffer'
7827 = 'Record connection closure info in ring buffer'
8002 = 'Changes CPU Affinity behaviour'
8010 = 'Fixes problem that SQL Server services can not be stopped'
8011 = 'Disable the ring buffer for Resource Monitor'
8012 = 'Disable the ring buffer for schedulers'
8015 = 'Ignore NUMA functionality'
8018 = 'Disable the exception ring buffer'
8019 = 'Disable stack collection for the exception ring buffer'
8020 = 'Disable working set monitoring'
8026 = 'SQL Server will clear a dumptrigger after generating the dump once'
8030 = 'Fix for performance bug'
8032 = 'Alters cache limit settings'
8038 = 'will drastically reduce the number of context switches when running SQL 2005 or 2008'
8040 = 'Disables Resource Govenor'
8048 = 'NUMA CPU based partitioning'
8207 = 'Alters Transactional Replication behaviour of UPDATE statement'
8209 = 'Output extra infomation to errorlog regarding replication of schema changes in SQL Server Replication'
8295 = 'Creates a secondary index on the identifying columns on the change tracking side table at enable time'
8602 = 'Disable Query Hints'
8605 = 'Displays logical and physical trees used during the optimization process'
8607 = 'Displays the optimization output tree during the optimization process'
8649 = 'Set Cost Threshold for parallelism to 0'
8675 = 'Displays the query optimization phases for a specific optimization'
8722 = 'Disable all hints exept locking hints'
8744 = 'Disable pre-fetching for ranges'
8755 = 'Disable all locking hints'
8757 = 'Skip trivial plan optimization and force a full optimization'
8780 = 'Give the optimizer more time to find a better plan'
9185 = 'Cardinality estimates for literals that are outside the histogram range are very low'
9024 = 'Performance fix for AlwaysON log replication'
9204 = 'Output Statistics used by Query Optimizer'
9205 = 'Cardinality estimates for literals that are outside the histogram range are very low for tables that have parent-child relationships'
9207 = 'Fixes that SQL Server underestimates the cardinality of a query expression and query performance may be slow'
9292 = 'Output Statistics considered to be used by Query Optimizer'
9481 = 'Forces the query optimizer to use the SQL Server 2012 version of the cardinality estimator when creating the query plan when running SQL Server 2014 with the default database compatibility level 120'
9485 = 'Disables SELECT permission for DBCC SHOW_STATISTICS.'
9806 = 'Unknown. Is turned on on SQL Server 2014 CTP1 standard installation in Windows Azure VM'
9807 = 'Unknown. Is turned on on SQL Server 2014 CTP1 standard installation in Windows Azure VM'
9808 = 'Unknown. Is turned on on SQL Server 2014 CTP1 standard installation in Windows Azure VM'
}

