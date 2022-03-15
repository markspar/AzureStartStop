# AzureStartStop
Automates VM start and stop based on schedule tokens in VM tags.

The runbook triggers a shutdown on the day/hour a machine is scheduled, and the same for the startup schedule.
It DOES NOT enforce the powered off or powered on period between the shutdown time and startup time; 5 minutes after a shutdown, a person
or process can turn it back on and it will stay on. The only exception to that are the all-day tags for schedules, those will be enforced every
time the runbook is fired.

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
* Azurestartstop: DayStarthourStophour
   * DAY code: D (days of the month range to be turned off), A (all days of week), B (weekdays), C (weekend), MTWHFSU for specific days of the week, day of month range and then most specific takes precedence
   * STARTHOUR and STOPHOUR code: military time (double digit 24 hour clock), with 0000 time code being off all day, 2424 time code being on all day
   * D0910 = turn off on the 9th of the month, stay off until 10th of the month (inclusive)
   * D0910A2424 = turn on 24 hours a day, except days 9 through 10 when it will turn off (inclusive)
   * B0619C0000 = Weekdays on at 6am, off at 7pm, Weekends off all day
   * M0019B0619S1214U0000 = Weekdays on at 6am, off at 7pm, except Monday on at midnight and off at 7pm, Saturday on at noon and off at 2pm, Sunday off all day
   * A0619H2424U0000 = All days on at 6am, off at 7pm, except Tursday on all day and Sunday off all day
   * Apply to the VM
* Environment: STRING
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
 * The JobId_g can be used to find the specific job in the runbook job list (enter quid in the search query), the specific errors can be found in the error entries.
 ![image](https://user-images.githubusercontent.com/31252279/151740702-b9f6410b-ffe4-47b7-9bbb-a57047c257f7.png)
 
 ## Version 1.3
Fixed thursday tag issue, added support in code for easier addition of new schedule tokens
Added support for days of month range (D code)

 Future Improvements:
1. Needs more robust error handling, especially on binding to subscriptions and reading runbook variables
2. Needs perf testing to see if parallel jobs should be designed for in the case of multiple large subscriptions
3. Needs a flag for include/exclude tag reading (or simply check if one is null and another is not, use that one)
4. Needs resource group tag reading (allows tagging an RG for Environment or azurestartstop schedule token
 
