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