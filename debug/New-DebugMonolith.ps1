$Functions = @{
    private = Get-ChildItem "$PSScriptRoot\..\private\*.ps1"
    public = Get-ChildItem "$PSScriptRoot\..\public\*.ps1"
}

$File = "$PSScriptRoot\DebugMonolith.ps1"

'### JUST FOR DEBUGGING ###' | Out-File $File
$Functions.private | ForEach-Object -Process { Get-Content $_.Fullname | Out-File $File -Append }
$Functions.public | ForEach-Object -Process { Get-Content $_.Fullname | Out-File $File -Append }