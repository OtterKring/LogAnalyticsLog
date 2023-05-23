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