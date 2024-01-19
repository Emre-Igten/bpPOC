[CmdletBinding()]
 
Param (
    [Parameter(Mandatory = $true)][string]$MarkdownFolder,
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $false)][String]$ModuleVersions,
    [Parameter(Mandatory = $true)][String]$WikiFolder
)
 
BEGIN {
    Write-Host ("MarkdownFolder       : $($MarkdownFolder)")
 
    $templateNameSuffixFilter = "*.md"
    $templateNameSuffix = ".md"
}
PROCESS {
    try {
        Set-Location $WikiFolder

        $files = Get-ChildItem -Path "$MarkdownFolder" -Filter $templateNameSuffixFilter -Recurse
        Write-Host "files: $files"
        Write-Host "----------------"
        $versions = $ModuleVersions | ConvertFrom-Json 
        Write-Host $versions
        Write-Host $versions.PSObject.Properties
        Write-Host "Moduleversions: $ModuleVersions"

        foreach ( $file in $files) {
            Write-Host "FILE: $file"
            Write-Host "File base name: $($file.BaseName)"
            foreach ( $key in $versions.PSObject.Properties) {
                if ( $key.Name -eq $file.BaseName) {
                    $FilePath = $file.FullName.Split("$MarkdownFolder/")[-1].Replace($templateNameSuffix,'')
                    Get-ChildItem
                    Write-Host "KEY: $key"
                    Write-Host "KeyName: $($key.name)"
                    Write-Host "File path: $FilePath"

                    if (!(Test-Path -Path $FilePath)) {
                        mkdir -p $FilePath | Out-Null
                    }
                    Write-Host "KeyValue: $($key.Value)"
                    $DocsVersionNumber = $key.Value

                    Set-Location $FilePath | Out-Null

                    Copy-Item $file.FullName -Destination "$($DocsVersionNumber).md"

                    Write-Host "$($FilePath)/$($DocsVersionNumber).md copied"

                    Set-Location "$RootPath/$WikiFolder"
                }
            }
        }  
    }
    catch {
        Write-Host "Something went wrong while uploading the documentation: $_"
    }
}
END {}