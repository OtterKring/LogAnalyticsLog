$Functions = @{
    private = Get-ChildItem "$PSScriptRoot\private\*.ps1"
    public = Get-ChildItem "$PSScriptRoot\public\*.ps1"
}

$Functions.private | ForEach-Object -Process { . $_.Fullname }
$Functions.public | ForEach-Object -Process { . $_.Fullname }
Export-ModuleMember -Function $Functions.public.BaseName