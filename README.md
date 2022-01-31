# AzureStartStop
Automates VM start and stop based on schedule tokens in VM tags

## Setup
* Ensure you have a managed identity (ideally system) that is granted VM contributor (or scaled down to just the rights to read and start/stop VMs)
in the subscriptions to be managed.
* Create the runbook, use powershell 7.1, import the script
* Create a schedule to run every hour, link it to this runbook
* Create variables to apply default values for the runbook: 
  *  Azurestartstop Exclude: Environment tags to EXCLUDE (e.g. PROD) to avoid impacting some machines even if accidentally tagged with shutdown schedules
  *  Azurestartstop Include: Environment tags to include (not used, exclude option can be swapped to include if desired)
  *  Azurestartstop Subscriptions: subscription IDs (comma-delimited) to use
  *  Azurestartstop TimeZone: timezone to use (e.g. Eastern Standard Time, UTC, etc.) - see get-date -listavailable, use the Id

## Tags
* Azurestartstop: <DAY><STARTHOUR><STOPHOUR>
   * <DAY> code: A (all days of week), B (weekdays), C (weekend), MTWHFSU for specific days of the week, most specific takes precedence
   * <STARTHOUR> and <STOPHOUR> code: military time (double digit 24 hour clock), with 0000 time code being off all day, 2424 time code being on all day
   * B0619C0000 = Weekdays on at 6am, off at 7pm, Weekends off all day
   * M0019B0619S1214U0000 = Weekdays on at 6am, off at 7pm, except Monday on at midnight and off at 7pm, Saturday on at noon and off at 2pm, Sunday off all day
   * A0619H2424U0000 = All days on at 6am, off at 7pm, except Tursday on all day and Sunday off all day
   * Apply to the VM
* Environment: <STRING>
   * Typically used for marking assets as PROD, DEV, TEST, QA, STAGING.
   * Apply to the VM

## Logging
 * Enable joblogs diagnostic logging for the azure automation account with the autostopstart runbook, log to an azure log analytics workspace
 * A sample log query will show all failed jobs in the last 24 hours.  An alert rule can be created to trigger e-mails based on this query.
```
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.AUTOMATION" and Category == "JobLogs" and RunbookName_s == "AutoShutdownSchedule" and ResultType == "Failed"
| project TimeGenerated, Resource, RunbookName_s, ResultType, JobId_g
```
 
 ## Version 1.1
Updated to cleanup timezone info

 Still needs:
1. Needs resource group tag reading (allows tagging an RG for Environment or azurestartstop schedule token
2. Needs more robust error handling, especially on binding to subscriptions and reading runbook variables
3. Needs a flag for include/exclude tag reading (or simply check if one is null and another is not, use that one)
4. Needs perf testing to see if parallel jobs should be designed for in the case of multiple large subscriptions
