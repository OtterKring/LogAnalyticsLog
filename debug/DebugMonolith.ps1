### JUST FOR DEBUGGING ###
# CLASS to hold the basic information about the LogAnalytics Table the logging should occur to
#
# REQUIRED INPUT:
# Name ...... the name of the table to post to
# Columns ... string array holding the column names to be used in this log. Column names will be used to extract the logging-relevant data from larger structures, like output from Get-Mailbox, Get-ADUser, ...
# Events .... string array holding the events to log
#
class LogAnalyticsLog {

    [guid] $WorkspaceId
    [string] $SharedKey
    [string] $Name          # table name
    [string] $ContentType = 'application/json'
    [string] $Resource = '/api/logs'
    [string] $ApiVersion = '2016-04-01'
    [uri] $Uri
    [psobject[]] $Columns
    [hashtable] $Events = @{}

    # encryption class used to create the signature to post each line
    # does not change in the process, so we only create it once for the log
    hidden [System.Security.Cryptography.HMACSHA256] $sha256
    hidden [bool] $hashColumns = $true
    
    # CONSTRUCTOR without Column info
    LogAnalyticsLog ( [guid] $wsid, [string] $skey, [string] $Name, [string[]] $Events ) {
        $this.Init( $wsid, $skey, $Name, $Events )
    }

    # CONSTRUCTOR with Column info
    LogAnalyticsLog ( [guid] $wsid, [string] $skey, [string] $Name, [psobject[]] $Columns, [string[]] $Events ) {
        $this.Init( $wsid, $skey,$Name, $Events )
        $this.InitColumns( $Columns )
    }

    # CREATE SIGNATURE for posting each line
    # 2 different overrides to allow different kinds of complexity
    [string] getSignature ( [datetime] $TimeStamp, [string] $BodyJSON ) {
        return $this.getSignature( 'POST', $TimeStamp, $BodyJSON, $this.ContentType, $this.Resource )
    }

    # main method for SIGNATURE creation
    [string] getSignature ( [string] $Method, [datetime] $TimeStamp, [string] $BodyJSON, [string] $ContentType, [string] $resource ) {

        $xHeaders = 'x-ms-date:' + $TimeStamp.ToUniversalTime().ToString('r')
        $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes( $BodyJSON )
        $BytesToHash = [System.Text.Encoding]::UTF8.GetBytes( ( @( $Method, $BodyBytes.Count, $ContentType, $xHeaders, $Resource ) -join "`n" ) )
        $Hash = [System.Convert]::ToBase64String( $this.sha256.ComputeHash( $BytesToHash ) )
        return ( 'SharedKey {0}:{1}' -f $this.WorkspaceId, $Hash )

    }

    [UInt32] Post ( [LogAnalyticsLogLine[]] $Lines ) {

        $this.Validate()
        $UtcNow = [datetime]::UtcNow
        $Json = $Lines | Select-Object -Property ( Get-Member -InputObject $_ -MemberType Property,NoteProperty ).Name | ConvertTo-Json -Depth 1

        $response = Invoke-WebRequest -Uri $this.Uri -Method 'POST' -ContentType $this.ContentType -Headers $this.getHeader( $UtcNow, $Json ) -Body ( [System.Text.Encoding]::UTF8.GetBytes( $Json ) )

        return $response.StatusCode

    }

    [void] Validate () {
        if ( -not $this.WorkspaceId ) { Throw 'WorkspaceId mssing' }
        if ( -not $this.sharedKey )  { Throw 'SharedKey mssing' }
        if ( -not $this.Name )       { Throw 'Log table name missing' }
    }

    hidden [hashtable] getHeader ( [datetime] $Time, [string] $JsonBody ) {
        return @{
            "Authorization" = $this.getSignature( $Time, $JsonBody )
            "Log-Type" = $this.Name
            "x-ms-date" = $Time.ToString('r')
            "time-generated-field" = 'TimeStamp'
        }
    }

    # INITIALIZATION code, for both ctors
    hidden [void] Init ( [guid] $wsid, [string] $skey, [string] $Name, [string[]] $Events ) {

        $this.Name = $Name
        $this.WorkspaceId = $wsid
        $this.SharedKey = $skey
        $this.sha256 = [System.Security.Cryptography.HMACSHA256]::new( [System.Convert]::FromBase64String( $this.SharedKey ) )
        $this.Uri = 'https://' + $this.WorkspaceId + '.ods.opinsights.azure.com' + $this.Resource + '?api-version=' + $this.ApiVersion

        # save the events to be used in this table
        foreach ( $e in $Events ) {
            $eValue = if ( -not [string]::IsNullOrEmpty( $e ) ) { $e.ToUpper() } else { $e }
            $this.Events.Add( $e, $eValue )
        }

    }

    hidden [void] InitColumns ( [psobject[]] $Columns ) {
        # save the columns to be used in this table
        # perform an actual copy of the array to be on the safe side

        $this.Columns = if ( $Columns -as [hashtable[]] )  {
            foreach ( $hash in $Columns ) {
                if ( $hash.Keys -contains 'Name' -and $hash.Keys -contains 'Expression' -and $hash.Expression -is [scriptblock] ) {
                    @{
                        Name = $hash.Name
                        Expression = $hash.Expression
                    }
                } else {
                    $this.hashColumns = $false
                    Throw 'Columns must either be an array of strings or an array of hashtables containing the keys "Name" and "Expression", with the latter referncing a scriptblock.'
                }
            }
        } else {
            $this.hashColumns = $false
            foreach ( $c in $Columns ) { $c }
        }
    }

}


# CLASS to be created for each line to post to LogAnalytics
#
# HARD-CODED Fields to be logged:
# TimeStamp ..... when an instance of the class / a line is created
# Type .......... the Eventtype to be logged, depends on the Events array of the LogAnalyticsLog class instance
# Description ... some text field to hold whatever you want to write to the log instead or in addition to the logged object data
#
# ADDITIONAL LOG DATA
# 
# additional fields for logging are added depending on the Colums string array of the LogAnalyticsLog class instance.
# if the data object passed to the class holds fields name as lined out in the Columns array, the fields will be logged.
#
class LogAnalyticsLogLine {
    
    [datetime] $TimeStamp =  [datetime]::now
    [string] $Type
    [string] $Description

    # DEFAULT CONSTRUCTOR
    LogAnalyticsLogLine () {}

    # CONSTRUCTOR to log MESSAGES
    LogAnalyticsLogLine ( [LogAnalyticsLog]$Log, [string] $EventType, [string] $Description ) {
        $this.Type = $Log.Events[ $EventType ]
        $this.Description = $Description
    }

    # CONSTRUCTOR to log DATA
    LogAnalyticsLogLine ( [LogAnalyticsLog] $Log, [string] $EventType, [psobject] $Data ) {

        $this.Type = $Log.Events[ $EventType ]

        # extract the data defined in the LogAnalyticsLog.Columns (if so) from the object data
        $filteredData = @{}

        if ( $Log.Columns.Count -eq 0 ) {
            # NO COLUMNS CHOSEN: get all properties of the data object and add them to the class instance
            $NewProperties = ( Get-Member -InputObject $Data -MemberType Property ).Name
            foreach ( $np in $NewProperties ) {
                $filteredData.Add( $np, $Data.$np)
            }
        } elseif ( $Log.hashColumns ) {
            # COLUMNS ARE HASHTABLES (Name/Expression-Pairs): mimic Select-Object and add the chose fields with the given modification to the class instance
            foreach ( $c in $Log.Columns ) {
                $filteredData.Add( $c.Name, ( $Data | ForEach-Object -Process $c.Expression ) )
            }
        } else {
            # COLUMNS ARE STRINGS: add the named fields to the class instance
            foreach ( $c in $Log.Columns ) {
                $filteredData.Add( $c, $Data.$c )
            }
        }

        Add-Member -InputObject $this -NotePropertyMembers $filteredData

    }

    # return the log data as JSON, EXCLUDING the TimeStamp, since this will be passed to the API differently
    [string] asJson () {
        return ( $this | Select-Object -Property ( Get-Member -InputObject $this -MemberType Property,NoteProperty ).Name | Convertto-JSON -Depth 1 )
    }

    # return the log data as JSON-BYTE-Array. The Api like it that way.
    [byte[]] asJsonBytes () {
        return $this.asJsonBytes( $this.asJson() )
    }

    [byte[]] asJsonBytes ( [string] $Json ) {
        return [System.Text.Encoding]::UTF8.GetBytes( $Json )
    }

    # POST the fully prepared line to LogAnalytics
    [UInt32] Post ( [LogAnalyticsLog] $Log ) {
        $Log.Validate()
        $Json = $this.AsJson()
        $response = Invoke-WebRequest -Uri $Log.Uri -Method 'POST' -ContentType $Log.ContentType -Headers $Log.getHeader( $this.TimeStamp.ToUniversalTime(), $Json ) -Body $this.asJsonBytes( $Json )

        return $response.StatusCode
        
    }

}
<#
.SYNOPSIS
Wrapper function to create a new line to post on your LogAnalytics table

.DESCRIPTION
Wrapper function to create a new line to post on your LogAnalytics table. Requires an instance of LogAnalyticsLog for meta-data of the table.

Returns a [LogAnalyticsLogLine] object.

.PARAMETER Log
Instance of LogAnalyticsLog, prefarrably as a variable, which holds old necessary information about the log you want to write to.

.PARAMETER EventType
The name of the event you want to be shown in the log line. Ideally use one you defined in the Events array of your LogAnalyticsLog instance.

.PARAMETER Message
If you are not logging some object data, this is to just post a custom text message to the log

.PARAMETER Data
The data object which holds the data to be logged. If it holds more data than needed, the data outlined in the Columns array of your LogAnalyticsLog instance will be extracted (if the fields are available)

.EXAMPLE
# create a LogAnalyticsLog instance
$Log = New-LogAnalyticsLog -Table MyTable -Columns @( 'SamAccountName','DistinguishedName','Enabled' ) -Events @( 'Info','Warning','Error' )

# use the log instance to prepare a log line
$Line = New-LogAnalyticsLine -Log $Log -EventType 'Info' -Message 'Hello World!'

.EXAMPLE
# create a LogAnalyticsLog instance
$splat = @{
    WorkspaceId = yourworkspaceid
    SharedKey = yoursharedkey
    Table = yourloganalyticstablename
    Columns = 'DisplayName','PrimarySMTPAddress','RecipientTypeDetails'
    Events = 'Info','Warning','Error'
}
$Log = New-LogAnalyticsLog @splat

# use the log instance to create multiple log lines for the same EventType from data structures
$Lines = 'einstein','newton','tesla' | Get-Mailbox | New-LogAnalyticsLine -Log $Log -EventType 'Info'

.NOTES
2023-05-17 ... initial version by Maximilian Otter
#>
function New-LogAnalyticsLine {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [LogAnalyticsLog]
        $Log,

        [Parameter( Mandatory )]
        [string]
        $EventType,

        [Parameter( ParameterSetName = 'Text' )]
        [string]
        $Message,

        [Parameter( ParameterSetName = 'Data', ValueFromPipeline )]
        [psobject[]]
        $Data
    )

    process {

        if ( $PSCmdlet.ParameterSetName -eq 'Data' ) {
            foreach ( $dataset in $Data ) {
                [LogAnalyticsLogLine]::new( $Log, $Log.Events[ $EventType ], $dataset )
            }
        } else {
            [LogAnalyticsLogLine]::new( $Log, $Log.Events[ $EventType ], $Message )
        }

    }

}
<#
.SYNOPSIS
Wrapper function to create an instance of the LogAnalyticsLog class

.DESCRIPTION
Wrapper function to create an instance of the LogAnalyticsLog class. The output must be saved in a variable for further use when posting log lines.

.PARAMETER WorkspaceId
Id of your LogAnalytics workspace

.PARAMETER SharedKey
the SharedKey allowing you to post to your LogAnalytics workspace

.PARAMETER Table
the name of the table you are posting to

.PARAMETER Columns
An array of strings, the names of the columns to be used in this log.

The columns will also be used to extract the data from a data object you want to log.

.PARAMETER Events
An array of strings, the names of the events you want to use for logging (e.g. Info, Warning, Error, etc.)

.EXAMPLE
$splat = @{
    WorkspaceId = yourworkspaceid
    SharedKey = yoursharedkey
    Table = yourloganalyticstablename
    Columns = 'SamAccountName','DistinguishedName','Enabled'
    Events = 'Info','Warning','Error'
}
$Log = New-LogAnalyticsLog @splat 

.NOTES
2023-05-16 ... initial version by Maximilian Otter
#>
function New-LogAnalyticsLog {
    [CmdletBinding()]
    param (
        [Parameter()]
        [guid]
        $WorkspaceId,

        [Parameter()]
        [string]
        $SharedKey,

        [Parameter( Mandatory )]
        [string]
        $Table,

        [Parameter()]
        [psobject]
        $Columns,

        [Parameter( Mandatory )]
        [string[]]
        $Events
    )

    if ( $Columns.Count -eq 0 ) {
        [LogAnalyticsLog]::new( $WorkspaceId, $SharedKey, $Table, $Events )
    } else {
        [LogAnalyticsLog]::new( $WorkspaceId, $SharedKey, $Table, $Columns, $Events )
    }
}
<#
.SYNOPSIS
Wrapper function to post data to your LogAnalytics table

.DESCRIPTION
Wrapper function to post data to your LogAnalytics table. Requires an instance of LogAnalyticsLog, so it knows where to post to.

.PARAMETER Log
Instance of LogAnalyticsLog, prefarrably as a variable, which holds old necessary information about the log you want to write to.

.PARAMETER Data
A LogAnalyticsLogLine or an array of LogAnalyticLogLine objects which will be posted to LogAnalytics in one post. Multiple lines coming from the pipeline will be collected an posted in one post, too.

.EXAMPLE
# create a LogAnalyticsLog instance
$Log = New-LogAnalyticsLog -Table MyTable -Columns @( 'SamAccountName','DistinguishedName','Enabled' ) -Events @( 'Info','Warning','Error' )

# create a couple of lines
$Lines = New-LogAnalyticsLine -Log $Log -EventType 'Info' -Message 'Hello World!'
$Lines += New-LogAnalyticsLine -Log $Log -EventType 'Warning' -Message 'This may be interesting ...'
$Lines += Get-ADUser einstein | New-LogAnalyticsLine -Log $Log -EventType 'Info'

# post the lines to LogAnalytics in one go
$result = Write-LogAnalytics -Log $Log -Data $Lines

.EXAMPLE
# create a LogAnalyticsLog instance
$splat = @{
    WorkspaceId = yourworkspaceid
    SharedKey = yoursharedkey
    Table = yourloganalyticstablename
    Columns = 'DisplayName','PrimarySMTPAddress','RecipientTypeDetails','ExchangeUserAccountControl'
    Events = 'Info','Warning','Error'
}
$Log = New-LogAnalyticsLog @splat

# create data for the log
$Lines = Get-Mailbox -RecipientTypeDetails 'SharedMailbox' |
    Where-Object ExchangeUserAccountControl -ne 'AccountDisabled' |
    New-LogAnalyticsLine -Log $Log -EventType 'Warning'

# post all lines to LogAnalytics in one go, this time using the pipeline
$result = $Lines | Write-LogAnalytics-Log $Log

.NOTES
2023-05-17 ... initial version by Maximilian Otter
#>
function Write-LogAnalytics {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [LogAnalyticsLog]
        $Log,

        [Parameter( Mandatory, ValueFromPipeline )]
        [LogAnalyticsLogLine[]]
        $Data
    )

    begin {
        $Lines = [System.Collections.Generic.List[LogAnalyticsLogLine]]::new()
    }

    process {
        
        # collect individual lines in one Generic List, regardless if they are single lines or arrays, coming from the pipeline or not
        foreach ( $dataset in $Data ) {
            $Lines.Add( $dataset )
        }

    }

    end {
        $result = $Log.Post( $Lines )
        if ( $result -ne 200 ) { $result }
    }

}
<#
.SYNOPSIS
Wrapper function to post a line to your LogAnalytics table

.DESCRIPTION
Wrapper function to post a line to your LogAnalytics table. Requires an instance of LogAnalyticsLog, so it knows where to post to.

.PARAMETER Log
Instance of LogAnalyticsLog, prefarrably as a variable, which holds old necessary information about the log you want to write to.

.PARAMETER EventType
The name of the event you want to be shown in the log line. Ideally use one you defined in the Events array of your LogAnalyticsLog instance.

.PARAMETER Message
If you are not logging some object data, this is to just post a custom text message to the log

.PARAMETER Data
The data object which holds the data to be logged. If it holds more data than needed, the data outlined in the Columns array of your LogAnalyticsLog instance will be extracted (if the fields are available)

.EXAMPLE
# create a LogAnalyticsLog instance
$Log = New-LogAnalyticsLog -Table MyTable -Columns @( 'SamAccountName','DistinguishedName','Enabled' ) -Events @( 'Info','Warning','Error' )

# use the log instance for posting a log line
$result = Write-LogAnalyticsLine -Log $Log -EventType 'Info' -Message 'Hello World!'

.EXAMPLE
# create a LogAnalyticsLog instance
$splat = @{
    WorkspaceId = yourworkspaceid
    SharedKey = yoursharedkey
    Table = yourloganalyticstablename
    Columns = 'DisplayName','PrimarySMTPAddress','RecipientTypeDetails'
    Events = 'Info','Warning','Error'
}
$Log = New-LogAnalyticsLog @splat

# use the log instance for posting a data structure
$result = Write-LogAnalyticsLine -Log $Log -EventType 'Info' -Data ( Get-Mailbox einstein )

.NOTES
2023-05-16 ... initial version by Maximilian Otter
#>
function Write-LogAnalyticsLine {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [LogAnalyticsLog]
        $Log,

        [Parameter( Mandatory )]
        [string]
        $EventType,

        [Parameter( ParameterSetName = 'Text' )]
        [string]
        $Message,

        [Parameter( ParameterSetName = 'Data' )]
        [psobject]
        $Data
    )

    $Line = New-LogAnalyticsLine @PSBoundParameters

    $result = $Line.Post( $Log )

    if ( $result -ne 200 ) { $result }

}
