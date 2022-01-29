# AzureStartStop
Automates VM start and stop based on schedule tokens in VM tags

Azure Runbook
Ensure you have a managed identity (ideally system) that is granted VM contributor (or scaled down to just the rights to read and start/stop VMs)
in the subscriptions to be managed.
Create the runbook, use powershell 7.1, import the script
Create a schedule to run every hour, link it to this runbook
Create variables to apply default values for the runbook: 
  Azurestartstop Exclude: Environment tags to EXCLUDE (e.g. PROD) to avoid impacting some machines even if accidentally tagged with shutdown schedules
  Azurestartstop Include: Environment tags to include (not used, exclude option can be swapped to include if desired)
  Azurestartstop Subscriptions: subscription IDs (comma-delimited) to use
  Azurestartstop TimeZone: timezone other than UTC to use (e.g. Eastern Time Zone)
Put tags on each VM with the schedule desired:
  Azurestartstop: <DAY><STARTHOUR><STOPHOUR>
    A (all days of week), B (weekdays), C (weekend), MTWHFSU for specific days of the week, always using double digit hours, military time
    0000 time code is off all day, 2424 time code is on all day
      B0619C0000 = Weekdays on at 6am, off at 7pm, Weekends off all day
      M0019B0619S1214U0000 = Weekdays on at 6am, off at 7pm, except Monday on at midnight and off at 7pm, Saturday on at noon and off at 2pm, Sunday off all day
      A0619H2424U0000 = All days on at 6am, off at 7pm, except Tursday on all day and Sunday off all day
  Environment
