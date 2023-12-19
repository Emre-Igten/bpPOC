[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]
    $containerRegistryName,

    [Parameter(Mandatory = $true)]
    [String]
    $modulePath,

    [Parameter(Mandatory = $false)]
    [String]
    $acrRepositoryPrefix = ""
)

Write-Host "###################################################"
Write-Host "Container Registry Name: $containerRegistryName"
Write-Host "ACR Repository Prefix: $acrRepositoryPrefix"
Write-Host "Module Path: $modulePath"
Write-Host "###################################################"

Write-Host "[SECTION] Fetch changed files"
$changedFiles = git diff --name-only origin/main^ origin/main --
$versions = @{}

Write-Host "[SECTION] These modules will receive a new version:"
foreach ($file in $changedFiles) {
    Write-Host $file
}

Write-Host "[SECTION] Loop through changed files and upload to ACR"
foreach ($file in $changedFiles) {
    if ([IO.Path]::GetExtension($file) -eq '.bicep') {
        $fileLocation = (Get-ChildItem -Path $file)
        $folder = $fileLocation.DirectoryName.Split('\')[-1]
        $fileName = $fileLocation.BaseName.ToLower()
        $filePath = $fileLocation.FullName

        Write-Host "Starting to upload module: $fileName"

        Write-Host "Get current latest version from ACR"
        $repository = ""
        if ($acrRepositoryPrefix -eq "") {
            $repository = $fileName
        }
        else {
            $repository = "$acrRepositoryPrefix/$fileName"
        }
        
        $PublishedVersion = az acr repository show-tags --name "$($containerRegistryName)" --repository "$repository" --orderby time_asc --output json | ConvertFrom-Json
        $currentLatestVersion = $PublishedVersion[-1]
        $acrMajorVersion = [int]$currentLatestVersion.Split('.')[0]
        $acrMinorVersion = [int]$currentLatestVersion.Split('.')[1]
        $acrIncrementVersion = [int]$currentLatestVersion.Split('.')[-1]

        Write-Host "Current latest version on ACR: $acrMajorVersion.$acrMinorVersion.$acrIncrementVersion"

        Write-Host "Fetch majorversion and minorversion from bicep file"
        az bicep build --file $filePath

        $armTemplate = Get-Content -Path "$folder/$fileName.json" -Raw | ConvertFrom-Json

        $majorVersion = $armTemplate.metadata.majorVersion
        $minorVersion = $armTemplate.metadata.minorVersion

        Write-Host "Version in file: $majorVersion.$minorVersion.x"
    
        Write-Host "Decide the correct new version number"
        $versionNumber = ""
        if ($majorVersion -gt $acrMajorVersion) {
            $versionNumber = "$majorVersion.0.0"
            Write-Host "Major version is higher than the major version of the module in the ACR. New version number will be: $versionNumber"
        }
        elseif ($majorVersion -eq $acrMajorVersion) {
            if ($minorVersion -gt $acrMinorVersion) {
                $versionNumber = "$majorVersion.$minorVersion.0"
                Write-Host "Minor version is higher than the minor version of the module in the ACR. New version number will be: $versionNumber"
            }
            elseif ($minorVersion -eq $acrMinorVersion) {
                $acrIncrementVersion++
                $versionNumber = "$majorVersion.$minorVersion.$acrIncrementVersion"
                Write-Host "The minor version of the module is equal to the minor version of the module in the ACR. New version number will be: $versionNumber"
            }
            else {
                Write-Error "The minor version of the module is lower than the minor version of the module in the ACR. This is not allowed."
            }
        }
        else {
            Write-Error "The major version of the module is lower than the major version of the module in the ACR. This is not allowed."
        }
    
        Write-Host "Publish module with correct version to ACR"
        if ($versionNumber -ne "") {
            az bicep publish --file $filePath --target br:$($containerRegistryName).azurecr.io/$($repository):$($versionNumber)
            Write-Host "Module added on following location: $($containerRegistryName).azurecr.io/$($repository):$($versionNumber)"
            $versions[$fileName] = $versionNumber
        }
        else {
            Write-Error "No version number was found. Module will not be uploaded to ACR."
        }
    }
}

Write-Host "##vso[task.setvariable variable=ModuleVersions]$($versions | ConvertTo-Json -Compress)"
