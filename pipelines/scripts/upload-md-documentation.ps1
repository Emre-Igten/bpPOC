[CmdletBinding()]
 
Param (
    [Parameter(Mandatory = $true)][string]$MarkdownFolder,
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $false)][String]$ModuleVersions,
    [Parameter(Mandatory = $true)][String]$WikiFolder
)
 
BEGIN {
    Write-Host ("MarkdownFolder       : $($MarkdownFolder)")
 
    $templateNameSuffix = "*.md"
}
PROCESS {
    try {
        Set-Location $WikiFolder

        $files = Get-ChildItem -Path "$MarkdownFolder" -Filter $templateNameSuffix -Recurse
        $versions = $ModuleVersions | ConvertFrom-Json 
        Write-Host $versions

        foreach ( $file in $files) {

            foreach ( $key in $versions.PSObject.Properties) {
                if ( $key.Name -eq $file.BaseName) {
                    if (!(Test-Path -Path $file.BaseName)) {
                        mkdir $file.BaseName | Out-Null
                    }
                    $DocsVersionNumber = $key.Value

                    Set-Location $file.BaseName | Out-Null

                    Copy-Item $file.FullName -Destination "$($DocsVersionNumber).md"

                    Write-Host "$($file.BaseName)/$($DocsVersionNumber).md copied"

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