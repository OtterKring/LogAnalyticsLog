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