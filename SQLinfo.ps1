import-module .\queries.ps1 -Force
import-module .\html-process.ps1 -force
$TableHeader = "My SQL Report"          ##The title of the HTML page
$OutputFile = "C:\MyReport.htm"         ##The file location
$debug = $true

$HTMLMiddle =""

function t-head {
    Param (
    [Parameter(Position=0,Mandatory,HelpMessage = "At least one value required")]
    [ValidateNotNullorEmpty()]
    [string[]]$A
    )

    
    $r += "<colgroup><col/><col/></colgroup><tr>"
    foreach ($x in $A) {
        $r += '<th>'+$x.ToString()+'</th>'
    }
    $r += "</tr>"
    return $r
}


function CheckLatency {

if ($debug) {Write-Host "--------- Latency ---------------"}
$in =""
$Drv_Read =[ordered]@{}
$Drv_Write = [ordered]@{}
$flag=@{}
$L_Warning = 10
$L_Major = 25

$Latency = Invoke-SQLcmd -Query $Check_Latency
$Latency_Max_Read = $Latency | sort-object -property Avg_read_latency_ms -Descending
$Latency_Max_Write = $Latency | sort-object -property Avg_write_latency_ms -Descending

foreach ($x in $Latency) {
$d = (split-path -Qualifier $x.datafile_name )

    If (!($Drv_Read.Contains($d))) {$Drv_Read.Add($d,$x.avg_read_latency_ms)}
    else {
        if ($drv_read.item($d) -lt $x.avg_read_latency_ms) {
            $drv_read.item($d) = $x.avg_read_latency_ms            
        }
    }
    If (!($Drv_Write.Contains($d))) {$Drv_Write.Add($d,$x.avg_write_latency_ms)}
    else {
        if ($drv_write.item($d) -lt $x.avg_write_latency_ms) {
            $drv_write.item($d) = $x.avg_write_latency_ms            
        }
    }
}

$In += "<H3>Latency</H3>"  
$In += "<div></div><table>"
$In += t-head("Drive","type","Max Latency","Notes")
foreach ($x in $drv_read.GetEnumerator()) {
    $In += "<tr>"
    $In += "<td>"+ $x.Name +"</td>" + "<td>Reads</td><td>" + $x.Value + "</td>"
    if ($x.value -ge $L_Major) {
           $In += "<td><span style='background-color: tomato'>Critical: Latency exceeds " + $L_Major+ "ms</span></td>"
    }
    elseif ($x.value -ge $L_Warning) {
        $In += "<td><span style='background-color: gold'>Warning: Latency exceeds " + $L_Warning+ "ms</span></td>"
    }
    else {
        $In += "<td>OK: Within thresholds</td>"
    }
    $In += "</tr>"
}
foreach ($x in $drv_write.GetEnumerator()) {
    $In += "<tr>"
    $In += "<td>"+ $x.Name +"</td>" + "<td>Writes</td><td>" + $x.Value + "</td>"
    if ($x.value -ge $L_Major) {
           $In += "<td><span style='background-color: tomato'>Critical: Latency exceeds " + $L_Major+ "ms</span></td>"
    }
    elseif ($x.value -ge $L_Warning) {
        $In += "<td><span style='background-color: gold'>Warning: Latency exceeds " + $L_Warning+ "ms</span></td>"
    }
    else {
        $In += "<td>OK: Within thresholds</td>"
    }
    $in += "</tr>"
}


$in += "</table>"
return $In

}

function CheckDrives {
    
    $threshold = 25
    if ($debug) {Write-Host "--------- Drives ---------------"}
    $disks = Get-PSDrive | where {$_.name.Length -eq 1}
    if ($debug) {Write-Host "--------- Drive Size ---------------"}
    $in = "<H3>Disk Space</H3>"   
    $in += "<table>"
    $in += t-head("Drive","Total (GB)","Free (GB)","Used (GB)","% Free","Warnings")
        foreach ($disk in $disks) {
         $in += "<tr>"
         $in += "<td>"+ $disk.Name +"</td>" 
         $in += "<td>" + [math]::round((($disk.Free + $disk.Used) /1gb))   + "</td>"
         $in += "<td>" + [math]::round((($disk.Free) /1gb))   + "</td>"
         $in += "<td>" + [math]::round((($disk.Used) /1gb))   + "</td>"
         $in += "<td>" + [math]::round(($disk.Free /($disk.Used + $disk.Free)) *100)    + "%</td>"
         
         if ( ($disk.Free /($disk.Used + $disk.Free) * 100) -lt 100-$threshold) {
            $in += "<td>Low disk</td>"
         }
         


         $in += "</tr>"
    }      
    $in +="</table>"
    return $in

}




# Load SQLPS
if (-not(Get-Module -name 'SQLPS')) {
     if (Get-Module -ListAvailable | Where-Object {$_.Name -eq 'SQLPS' }) {
        Push-Location # The SQLPS module load changes location to the Provider, so save the current location
        Import-Module -Name 'SQLPS' -DisableNameChecking
        Pop-Location # Now go back to the original location
     }
}

# Get Disk Drive Sizes

push-location
$HTMLMiddle += CheckDrives

# Get SQL Server basic settings
$temp =[ordered] @{}
$flag = @{}

$HTMLMiddle += "<H3>Settings</H3>"   
if ($debug) {Write-Host "--------- SQL Settings ---------------"}
cd SQLSERVER:\sql\localhost
$srv = get-item default
$temp.add("Computer Name:",$srv.ComputerNamePhysicalNetBIOS)
$temp.add("OS Platform::",$srv.platform)
$temp.add("OS Ver:",$srv.OSVersion)
$temp.add("OS Processor Count:",$srv.Processors)
$temp.add("OS Physical Memory:",$srv.PhysicalMemory)
$temp.add("SQLServer Edition:",$srv.Edition)
$temp.add("SQLServer Build:",$srv.BuildNumber)
$temp.add("SQLServer Prouct:",$srv.Product)
$temp.add("SQLServer Engine Edition:",$srv.EngineEdition)
$temp.add("SQLServer Product Level:",$srv.ProductLevel)
$temp.add("SQLServer Version:",($srv.Version.Major.ToString() +'.' + $srv.Version.Minor.ToString() +'.' +$srv.Version.Build.ToString()))
$temp.add("SQLServer Collation:",$srv.Collation)
#-------------- TEST -----------------------
if (!(($srv.Collation -eq "Latin1_General_BIN2") -or ($srv.Collation -eq "Latin1_General_BIN"))) {
    $flag.add("SQLServer Collation:",$true)
}

$temp.add("SQLServer Master DB:",$srv.MasterDBPath)
#-------------- TEST -----------------------
if ((split-path $srv.MasterDBPath -Qualifier) -eq "C:") {
    $flag.add("SQLServer Master DB:",$true)
}

$temp.add("SQLServer Login Mode:",$srv.LoginMode)
$x = if ($srv.InstanceName.Length -eq 0) { 'Default'} else {$srv.InstanceName}
$temp.add("SQLServer Instance:",$x)
$temp.add("SQLServer DOP Cost:",$srv.configuration.CostThresholdForParallelism.ConfigValue)
$temp.add("SQLServer DOP Max:",$srv.configuration.MaxDegreeOfParallelism.ConfigValue)
#-------------- TEST -----------------------
if (($srv.$srv.configuration.MaxDegreeOfParallelism.ConfigValue) -lt 2) {
    $flag.add("SQLServer DOP Max:",$true)
}
$temp.add("SQLServer Priority Boost:",$srv.configuration.PriorityBoost.ConfigValue)
$temp.add("SQLServer Memory Min:",$srv.configuration.MinServerMemory.ConfigValue)
$temp.add("SQLServer Memory Max:",$srv.configuration.MaxServerMemory.ConfigValue)
#-------------- TEST -----------------------
if ($srv.PhysicalMemory - $srv.configuration.MaxServerMemory.ConfigValue -lt 4) {
    $flag.add("SQLServer Memory Max:",$true)
}
if ($srv.configuration.MaxServerMemory.ConfigValue -gt 524800) {
    $flag.add("SQLServer Memory Max:",$true)#
}

$temp.add("SQLServer Full Text Installed:",$srv.IsFullTextInstalled)
#-------------- TEST -----------------------
if ($srv.IsFullTextInstalled -eq 1) {
    $flag.add("SQLServer Full Text Installed:",$true)
}
$temp.add("SQLServer Clustered:",$srv.IsClustered)
$temp.add("SQLServer Install Dir:",$srv.InstallSharedDirectory)


$HTMLMiddle += "<div></div><table>"
$HTMLMiddle += t-head("Name","Value","Notes")

foreach ($x in $temp.GetEnumerator()) {
    $HTMLMiddle += "<tr><td>" + $x.name + "</td>"
    if (!($flag.Item($x.name))) {
        $HTMLMiddle += "<td>" + $x.value +"</td>"
    }
    else {
        $HTMLMiddle += "<td><span style='background-color: gold'>" + $x.value +"</span></td>"
    }
    if ($KBLink.Item($x.name) -ne $null) {
        $HTMLMIddle += "<td>" + $KBlink.item($x.name) + "</td>"
    }
    else {
        $HTMLMIddle += "<td></td>"
    }
    $HTMLMiddle += "</td>"
}
$HTMLMiddle += "</table>"

if ($debug) {Write-Host "--------- TraceFlags ---------------"}
$traceflags = Invoke-SQLcmd -Query $Check_Traceflags




if ($debug) {Write-Host "--------- Databases ---------------"}
$HTMLMiddle +="<DIV></DIV>"
$HTMLMiddle += "<H3>Databases</H3>"  
$database_list = $srv.Databases | where ({$_.name -ne 'Master' -and $_.name -ne 'model' -and $_.name -ne 'msdb' -and $_.name -ne 'tempdb'} )
$HTMLMiddle += $database_list |Select-object -Property Name,Collation,@{n="Replication";e={($_.ReplicationOptions)}}, LastBackupDate,PrimaryFilePath,RecoveryModel, @{n="Size (GB)";e={"{0:N2}" -f (($_.DataSpaceUsage +$_.IndexSpaceUsage) / 1mb)}}, AutoUpdateStatisticsAsync | Convertto-HTML -fragment
$flag = @{}
$chkdate = (get-date)

foreach ($x in $database_list) {
   if ($x.LastBackupDate -lt $chkdate.AddDays(-1)) {    
        if (!($flag.ContainsKey("Outdated backups:"))) { $flag.add("Outdated backups:",$true)}          
     }
     if ((split-path $x.PrimaryFilePath -Qualifier) -eq "C:") {        
        if (!($flag.ContainsKey("Database on on OS Drive:"))) { $flag.add("Database on on OS Drive:",$true)}          
     }
}

$HTMLMiddle += "<div></div><table>"
$HTMLMiddle += t-head("Database Warnings","Value","Notes")


foreach ($x in $flag.GetEnumerator()) {    
    $HTMLMiddle += "<tr><td>" + $x.name + "</td>"    
    $HTMLMiddle += "<td><span style='background-color: tomato'>" + $x.value +"</span></td>"    
    if ($KBLink.Item($x.name) -ne $null) {
        $HTMLMIddle += "<td>" + $KBlink.item($x.name) + "</td>"
    }
    else {
        $HTMLMIddle += "<td></td>"
    }
    $HTMLMiddle += "</tr>"
}
$HTMLMiddle += "</table>"

if ($debug) {Write-Host "--------- TEMPDB ---------------"}
$HTMLMiddle += "<H3>TempDB</H3>"  
$tempdb = Invoke-SQLcmd -Query $Check_TEMPDB_Count
$chk = $tempdb[0].FileSizeinMB
$tempdb_size = $true
foreach ($x in $tempdb) {
    if ($x.filesizeinMB -ne $chk) { 
        $tempdb_size = $false 
        break
    }
}

#if false then we have a size mismatch
$HTMLMiddle += $tempdb | select-object -property FileName,@{n="Size (MB)";e={"{0:N0}" -f ($_.FileSizeinMB)}},AutogrowthStatus,GrowthValue,GrowthIncrement | Convertto-HTML -fragment
#-------------- TEST -----------------------
if (($tempdb_size)) {

    $HTMLMiddle += "<div></div><table>"
    $HTMLMiddle += t-head("TempDB Warnings")
    $HTMLMiddle += "<tr><td><span style='background-color: gold'>" + "Warning: Tempdb files not all equal" +"</span></td></tr>"
    $HTMLMiddle += "</table>"
}
 

if ($debug) {Write-Host "--------- Page Life ---------------"}
$HTMLMiddle += "<H3>Page Life Expectancy</H3>"  
$Pagelife = Invoke-SQLcmd -Query $Check_Pagelife

$HTMLMiddle += "<div></div><table>"
$HTMLMiddle += t-head("Page Life (sec)", "Warnings")


$HTMLMiddle += "<tr><td>"+$Pagelife.PLE_sec.ToString() +"</td>"
#-------------- TEST -----------------------
if ($pagelife.PLE_sec -lt 10000) {
    $HTMLMiddle +="<td><span style='background-color: gold'>" + "Warning: Low Page Life Expectancy" +"</span></td></tr>"
}
else {
    $HTMLMiddle +="<td>No Page Life Proglems found<td></tr>"
}
$HTMLMiddle += "</table>"

$HTMLMiddle += CheckLatency
Pop-Location

# Assemble the final report from all our HTML sections
$HTMLmessage = $HTMLHeader + $HTMLMiddle + $HTMLEnd
# Save the report out to a file in the current path
$HTMLmessage | Out-File ((Get-Location).Path + "\sqlinfo.html")
exit


if ($debug) {Write-Host "--------- Waits ---------------"}
$Wait_Stats = Invoke-SQLcmd -Query $Get_WaitStats
$wait_Stats |Select Wait_type, pct , avg_wait_ms


if ($debug) {Write-Host "--------- Find M3 DB ---------------"}
$M3DB = '' 
foreach ($x in $database_list) { 
    if ($x.Name -like "M3*") {
        if ($x.name -like "*DB*") {
            $M3DB = $x.Name
        }
    }
}

If ($M3DB.length -ne 0) {
    Write-host "Your M3 Database appears to be called " $M3DB
}
else {
    Write-Host "Unable to determine M3 Database.  Choose from the following list:" 
    $database_list | Select Name -ExpandProperty name

}
    
if ($debug) {Write-Host "--------- Statistics ---------------"}
$Check_stats = "USE " + $M3DB + " " + $Check_Stats 
$M3Stats = Invoke-SQLcmd -Query $Check_Stats -QueryTimeout 600
# over 7 days old
$M3Stats.count
If ($M3Stats.count -gt 0) {
    $M3Stats_Latest = $M3Stats | sort-object -property StatsUpdated -Descending
    $M3Stats_Latest[0].StatsUpdated.Year
    $M3Stats_Latest[0].StatsUpdated.Month
    $M3Stats_Latest[0].StatsUpdated.Day
}

if ($debug) {Write-Host "--------- Fragmentation ---------------"}
if ($debug) {Write-Host "--------- This can take a while to run ---------------"}
$Check_Frag = "USE " + $M3DB + " " + $Check_Frag
$M3Frag = Invoke-SQLcmd -Query $Check_Frag -QueryTimeout 600
# Over 30% and over 1000 pages
$M3Frag.count
foreach ($x in $M3Frag) {
    $x.ndxname, $x.avg_fragmentation_in_percent, $x.record_count
}
 
if ($debug) {Write-Host "--------- Slow Queries ---------------"}
$SlowQueries = Invoke-SQLcmd -Query $Check_SlowQueries
$SlowQueries | select statement_txt,exec_cnt,avg_et_ms 


if ($debug) {Write-Host "--------- Memory Dumps ---------------"}
$MemoryDumps = Invoke-SQLcmd -Query $Check_MemoryDumps
$MemoryDumps


if ($debug) {Write-Host "--------- M3DB VLF ---------------"}
$Check_VLF = "USE " + $M3DB + " " + $Check_VLF
$M3VLF = Invoke-SQLcmd -Query $Check_VLF
$M3VLF.count

if ($debug) {Write-Host "--------- M3DB DBCC ---------------"}

$Check_M3DBCC = "DBCC DBINFO('" + $M3DB + "') WITH TABLERESULTS"
$M3DBCC = invoke-SQLcmd -query $Check_M3DBCC
$M3DBCC | where {$_.field -eq "dbi_dbccLastKnownGood"} | select Value -ExpandProperty Value

     
if ($debug) {Write-Host "--------- M3DB Replicated --------------"}
$M3Replicated = Invoke-SQLcmd -Query $Check_Replicated
if ( ($M3Replicated | where {$_.name -eq $M3DB} | select is_published -ExpandProperty is_published) -eq "True") { $True} else {$false}

if ($debug) {Write-Host "--------- M3DB Triggers --------------"}
$Check_M3Triggers = "Select * from "+ $M3DB + ".sys.triggers where is_ms_shipped <> 1"
$M3Triggers = Invoke-SQLcmd -Query $Check_M3Triggers
$M3Triggers.count




