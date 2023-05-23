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