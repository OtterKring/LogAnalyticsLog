# LogAnalyticsLog
A powershell module for simple logging to LogAnalytics

This module is roughly based on the the example code from Microsoft published [here](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api?tabs=powershell#sample-requests). I rewrote it to make logging as simple as possible while coding the actual script using it.

## Available Commands

### New-LogAnalyticsLog -WorkspaceId guid -SharedKey string -Table string -Columns psobject -Events string[]

Creates an object holding all the metadata used for logging to LogAnalytics.
|Parameter|Description|
|---|---|
|`WorkspaceId`|receives the guid representing your LogAnalytics Workspace' Id.|
|`SharedKey`|receives the string representing the shared key of your LogAnalytics Workspace.|
|`Table`|the name of the table your want to post to.|
|`Columns`|if you want to predefine columns aka data-fields, you can do it here. More details below.|
|`Events`|an array of strings representing the Events happening in your code, which you want to log.|

The function returns an instance of the `LogAnalyticsLog` class, which you _must_ save to a variable for later use with the other logging functions.

#### Example: "Columns" can be predefined using 3 levels of complexity:

1. BASIC

None at all. The objects you post to LogAnalytics will be taken "as is".

    $splat_LogAnalytics = @{
        WorkspaceId = 'yourworkspaceguid'
        SharedKey = 'yoursharedkey'
        Table = 'nameofyourlogtable'
        Events = 'Start','Info','Warning','Error','Create','Stop'
    }

    $Log = New-LogAnalyticsLog @splat_LogAnalytics 

2. SIMPLE

Using an array of strings representing the fields in your upcoming data object, only these fields will be posted to LogAnalytics, without any further modification.
 
    $splat_LogAnalytics = @{
        WorkspaceId = 'yourworkspaceguid'
        SharedKey = 'yoursharedkey'
        Table = 'nameofyourlogtable'
        Columns = 'DisplayName', 'UserPrincipalName', 'PrimarySMTPAddress', 'RecipientTypeDetails', 'EmailAddressPolicyEnabled'
        Events = 'Start','Info','Warning','Error','Create','Stop'
    }

    $Log = New-LogAnalyticsLog @splat_LogAnalytics 

**NOTE:** in this example `PrimarySMTPAddress` may be an object holding additional data if your script is running on an on-premises installation of Exchange. In this case you may want to use option 3 ...

3. COMPLEX

If you know the upcoming data fields hold more info than you need in the log or you want it to be modified in anyway you can predefine the "Columns" or data fields using an array of Name/Expression-hashtables, as you would use it for Select-Object:

    $splat_LogAnalytics = @{
        WorkspaceId = 'yourworkspaceguid'
        SharedKey = 'yoursharedkey'
        Table = 'nameofyourlogtable'
        Columns = @(
            @{
                Name = 'DisplayName'
                Expression = { $_.DisplayName }
            }
            @{
                Name = 'UserPrincipalName'
                Expression = { if ( $_.UserPrincipalName ) { $_.UserPrincipalName.ToLower() } }
            }
            @{
                Name = 'PrimarySMTPAddress'
                Expression = { if ( $_.PrimarySMTPAddress -is [string] ) { $_.PrimarySMTPAddress } else { $_.PrimarySMTPAddress.Address } }
            }
            @{
                Name = 'RecipientTypeDetails'
                Expression = { $_.RecipientTypeDetails }
            }
            @{
                Name = 'EmailAddressPolicyEnabled'
                Expression = { $_.EmailAddressPolicyEnabled }
            }
        )
        Events = 'Start','Info','Warning','Error','Create','Stop'
    }

    $Log = New-LogAnalyticsLog @splat_LogAnalytics


**All this must only be defined ONCE at the beginning of the script, before you start logging anything!**

### New-LogAnalyticsLine -Log LogAnalyticsLog -EventType string -Message string
### New-LogAnalyticsLine -Log LogAnalyticsLog -EventType string -Data psobject[]

Creates a new instance of a LogAnalyticsLogLine class which can then be posted to LogAnalytics.

|Parameter|Description|
|---|---|
|`Log`|receives the $Log variable previously created with `New-LogAnalyticsLog`.|
|`EventType`|use one of the Event names you predefined with `New-LogAnalyticsLog`.|
|`Message`|if you just want to post some text to the log, use the message parameter.|
|`Data`|post the object(s) containing the data you want to post here.|

`Message` and `Data` cannot be used at the same time.

#### Example:

    # using the $Log variable created previously
    New-LogAnalyticsLine -Log $Log -EventType 'Start' -Message 'Starting script'

    # create multiple log lines for the same EventType from data structures using the pipeline
    $Lines = 'einstein','newton','tesla' | Get-Mailbox | New-LogAnalyticsLine -Log $Log -EventType 'Info'

    # OR without pipeline
    $Mbx = 'einstein','newton','tesla' | Get-Mailbox
    $Lines = New-LogAnalyticsLine -Log $Log -EventType 'Info' -Data $Mbx

    # OR collect several lines using different Events
    $Lines = New-LogAnalyticsLine -Log $Log -EventType 'Info' -Message 'Hello World!'
    $Lines += New-LogAnalyticsLine -Log $Log -EventType 'Warning' -Message 'This may be interesting ...'
    $Lines += Get-Mailbox einstein | New-LogAnalyticsLine -Log $Log -EventType 'Info'


### Write-LogAnalytics -Log LogAnalyticsLog -Data LogAnalyticsLogLine[]

Post all prepared lines to LogAnalytics.

|Parameter|Description|
|---|---|
|`Log`|receives the $Log variable previously created with `New-LogAnalyticsLog`.|
|`Data`|receives the $Lines prepares using `New-LogAnalyticsLine`. See previous example.|

#### Example:

    # post lines using pipeline
    $result = $Lines | Write-LogAnalytics -Log $Log

    # OR without pipeline
    $result = Write-LogAnalytics -Log $Log -Data $Lines

`$result` will be empty on success (my choice). Consult the [return codes](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api?tabs=powershell#return-codes) for more details.


### Write-LogAnalyticsLine -Log LogAnalyticsLog -EventType string -Message string
### Write-LogAnalyticsLine -Log LogAnalyticsLog -EventType string -Data psobject

Posts a single line or data object to LogAnalytics. Does not need a `New-LogAnalyticsLine` in advance, so it can be use similar to e.g. `Write-Information` in code.

|Parameter|Description|
|---|---|
|`Log`|receives the $Log variable previously created with `New-LogAnalyticsLog`.|
|`EventType`|use one of the Event names you predefined with `New-LogAnalyticsLog`.|
|`Message`|if you just want to post some text to the log, use the message parameter.|
|`Data`|receives the $Lines prepares using `New-LogAnalyticsLine`. See previous example.|

#### Example:

    # post a message to LogAnalytics
    $result = Write-LogAnalyticsLine -Log $Log -EventType 'Info' -Message 'Hello World!'

    # post a data object to LogAnalytics
    $result = Get-Mailbox einstein | Write-LogAnalyticsLine -Log $Log -EventType 'Create'

    # OR without pipeline
    $result = Write-LogAnalytics -Log $Log -EventType 'Create' -Data ( Get-Mailbox einstein )

* `Message` and `Data` cannot be used at the same time.
* `$result` will be empty on success (my choice). Consult the [return codes](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api?tabs=powershell#return-codes) for more details.