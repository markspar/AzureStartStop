<#PSScriptInfo

.USAGE
    The runbook implements a solution for scheduled power management of Azure virtual machines in combination with tags
    on virtual machines or resource groups which define a shutdown schedule. Each time it runs, the runbook looks for all
    virtual machines or resource groups with a tag named "Autostartstop" having a value defining the schedule, 
	e.g. A0622 (all days of week, start at 6am, shutdown 10pm). 
	It then checks the current hour, stopping a VM at the stop hour and starting it at the start hour.  It does not
	attempt to enforce stopped/started state in between (e.g. 6am start and 10pm stop - if someone stops the VM at 8am, 
	autostartstop will not start it until the next start hour)

    This is a PowerShell runbook, as opposed to a PowerShell Workflow runbook.

    This runbook requires the "Az.Accounts", "Az.Compute" and "Az.Resources" modules (which are on by default) and
	authenticate with a managed identity granted specific VM rights on the subscriptions to be managed.

    Valid tags:
	<day tag><shutdown hour><startup hour>
	A - all days of week
	B - all weekdays
	C - all weekends
	MTWHFSU - days of week, Monday - Sunday
	Special hour codes - 0000 for shutdown all day, 2424 for leave on all day
	These can be combined as needed, with more specific days taking precedence over more generic schedules.
	A1806S0000M2424 would have the VM stay off all saturday, on all Monday, and otherwise turn off at 6pm and on at 6am.

    PARAMETER AzSubscriptionIDs
    The Azure subscription IDs to operate against. By default, it will use the Variable setting named "AutoStartStop Subscriptions"
	Enter as a command-delimited list of IDs (e.g. aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa,bbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb)

    PARAMETER tz
    The ID of the time zone you want to use. Run 'Get-TimeZone -ListAvailable' to get available timezone ID's.  Defaults to UTC.
	This is important as administrators and VMs can be running in many time zones.  To ensure the proper schedule is followed, using UTC values
	is suggested for global companies.

	PARAMETER deallocate
	Takes stopped machines and deallocates them (stopped machines happen when the machine is shutdown from within the OS but Azure does not deallocate it)
	Stopped machines are still charged in azure, so this is most often desired.  In some cases, machines are stopped temporarily but not deallocated purposely,
	mostly to save the temp disk or preseve IP allocation or the like.  Defaults to $true.

    PARAMETER Simulate
    If $true, the runbook will not perform any power actions and will only simulate evaluating the tagged schedules. Use this
    to test your runbook to see what it will do when run normally (Simulate = $false).

	PARAMETER EnvironmentExclude
	If non-null, will skip any VM with the Environment tag set to these values

	PARAMETER EnvironmentInclude
	If non-null, will skip any VM with the Environment tag set to these values
    
.PROJECTURI https://github.com/markspar/autostartstop

.TAGS
    Azure, Automation, Runbook, Start, Stop, Machine

.OUTPUTS
    Human-readable informational and error messages produced during the job. Not intended to be consumed by another runbook.

.CREDITS
    The script was originally created by Automys, https://automys.com/library/asset/scheduled-virtual-machine-shutdown-startup-microsoft-azure
#>

param(
    [parameter(Mandatory = $false)]
    [String] $AzSubscriptionIDs = "Use *AutoStartStop Subscriptions* Variable Value",
    [parameter(Mandatory = $false)]
    [String] $tz = "Use *AutoStartStop TimeZone* Variable Value",
    [parameter(Mandatory = $false)]
    [bool]$Simulate = $false,
    [parameter(Mandatory = $false)]
    [bool]$Deallocate = $false,
    [parameter(Mandatory = $false)]
    [String]$EnvironmentExclude = "Use *AutoStartStop Exclude* Variable Value",
    [parameter(Mandatory = $false)]
    [String]$EnvironmentInclude = "Use *AutoStartStop Include* Variable Value"
)

$VERSION = "1.1"
$script:DoNotStart = $false

# Main runbook content
try {
    # Ensures you do not inherit an AzContext in your runbook
    Disable-AzContextAutosave -Scope Process
    # Retrieve time zone name from variable asset if not specified
    if ($tz -eq "Use *AutoStartStop TimeZone* Variable Value") {
        $tz = Get-AutomationVariable -Name "AutoStartStop TimeZone"
    }
	# Get current time in timezone specified
	$startTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $tz)
	$day = ($startTime.DayOfWeek.ToString()).ToUpper()
	$hour = $startTime.Hour
    # Retrieve Subscription ID(s) from variable asset if not specified
    if ($AzSubscriptionIDs -eq "Use *AutoStartStop Subscriptions* Variable Value") {
        $AzSubscriptionIDs = Get-AutomationVariable -Name "AutoStartStop Subscriptions" -ErrorAction Ignore
    }
    # Retrieve environment tag includes from variable asset if not specified
    if ($EnvironmentExclude -eq "Use *AutoStartStop Exclude* Variable Value") {
        $EnvironmentExclude = Get-AutomationVariable -Name "AutoStartStop Exclude" -ErrorAction Ignore
    }
    # Retrieve environment tag excludes from variable asset if not specified
    if ($EnvironmentInclude -eq "Use *AutoStartStop Include* Variable Value") {
        $EnvironmentInclude = Get-AutomationVariable -Name "AutoStartStop Include" -ErrorAction Ignore
    }

    Write-Output "Runbook started. Version: $VERSION"
	Write-Output "Start time $($startTime) (Time Zone $($TZ))"
	Write-Output "Day: $($day), Hour: $($hour)"
    Write-Output "Subscription IDs: [$AzSubscriptionIDs]"
	Write-Output "Environment tags to exclude: $($EnvironmentExclude)"
	Write-Output "Environment tags to include: $($EnvironmentInclude)"
    if ($Simulate) {
        Write-Output "*** Running in SIMULATE mode. No power actions will be taken. ***"
    }
    else {
        Write-Output "*** Running in LIVE mode. Schedules will be enforced. ***"
    }

	$AzIDs = $AzSubscriptionIDs.Split(",")
	foreach ($AzID in $AzIDs) {
		Write-Output "Processing Subscription ID: [$AzId]"
		Connect-AzAccount -Identity -Subscription $AzId > $null
#		Write-Output "Authenticated"
		Set-AzContext -SubscriptionId $AzId > $null
#		Write-Output "Context set"
		$CurrentSub = (Get-AzContext).Subscription.Id
		If ($CurrentSub -ne $AzID) {
			Throw "Could not switch to SubscriptionID: $AzID"
		}

		# maybe add filter for include/exclude of machines in specific resource groups?
		# Get a list of all virtual machines in subscription, excluding some environment tags
		$vms = Get-AzVM -Status | Where-Object {(($_.tags.Autostartstop -ne $null) -and ($_.tags.Environment -notin $EnvironmentExclude))} | Sort-Object Name
		# Get a list of all virtual machines in subscription, including only some environment tags
		#$vms = Get-AzVM -Status | Where-Object {(($_.tags.Autostartstop -ne $null) -and ($_.tags.Environment -in $EnvironmentInclude))} | Sort-Object Name

		Write-Output "Processing [$($vms.Count)] virtual machines found in subscription"
		foreach ($vm in $vms) {
			Write-Output "Processing VM - $($vm.Name)"
#			Write-Output "PowerState - $($vm.PowerState)"
#			Write-Output "Environment - $($vm.tags.Environment)"
			$schedule = $vm.tags.Autostartstop
			$schedule = $schedule.ToUpper()
#			Write-Output "Autostartstop value - $($schedule)"

#			Write-Output $day

			$dayfound = $null
			switch($day){
				"MONDAY" {if ($schedule.contains("M")){$dayfound="M"}}
				"TUESDAY" {if ($schedule.contains("T")){$dayfound="T"}}
				"WEDNESDAY" {if ($schedule.contains("W")){$dayfound="W"}}
				"THURSDAY" {if ($schedule.contains("U")){$dayfound="U"}}
				"FRIDAY" {if ($schedule.contains("F")){$dayfound="F"}}
				"SATURDAY" {if ($schedule.contains("S")){$dayfound="S"}}
				"SUNDAY" {if ($schedule.contains("U")){$dayfound="U"}}
			}
			if ($dayfound -eq $null){
				if (($day -in @('MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY')) -and ($schedule.contains("B"))){
					$dayfound="B"
				}
				elseif (($day -in @('SATURDAY','SUNDAY')) -and ($schedule.contains("C"))){
					$dayfound="C"
				}
			}
			if (($dayfound -eq $null) -and ($schedule.contains("A"))){
				$dayfound="A"
			}

#			Write-Output "Schedule token found - $($dayfound)"

			$starthour = $schedule.substring($schedule.indexof($dayfound)+1,2)
			$stophour = $schedule.substring($schedule.indexof($dayfound)+3,2)
			$dostop = $false
			$dostart = $false

#			Write-Output "Start Hour - $($starthour)"
#			Write-Output "Stop Hour - $($stophour)"

			#check for special hours - 0000 = always off, 2424 = always on
			if (($starthour -eq "00") -and ($stophour -eq "00")){
				$stophour = $hour
				$dostop=$true
				$dostart=$false
			}
			elseif (($starthour -eq "24") -and ($stophour -eq "24")){
				$starthour = $hour
				$dostart=$true
				$dostop=$false
			}

			# check environment tag for excluded - if so, set flag for excluded
			# check environment tag for included - if not, set flag for excluded
			if (($hour -eq $stophour) -and ($vm.PowerState -eq "VM Running") -and ($simulate -eq $false) -and ($dostop)){
			    Write-Output "Stop VM - $($vm.Name)"
				Stop-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Confirm:$false -Force -NoWait > $null
			}
			elseif (($hour -eq $starthour) -and ($vm.PowerState -ne "VM Running") -and ($simulate -eq $false) -and ($dostart)){
			    Write-Output "Start VM - $($vm.Name)"
				Start-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -NoWait > $null
			}

		} #foreach vm
		Write-Output "Finished processing subscription"
	} # foreach azsubid
    Write-Output "Finished processing virtual machine schedules"
} # try
catch {
    $errorMessage = $_.Exception.Message
    $line = $_.InvocationInfo.ScriptLineNumber
    throw "Unexpected exception: $errorMessage at $line"
}
finally {
    $EndTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $tz)
    Write-Output "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ($EndTime - $startTime))))"
}
