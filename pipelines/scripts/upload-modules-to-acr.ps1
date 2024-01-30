[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]
    $containerRegistryName,

    [Parameter(Mandatory = $true)]
    [String]
    $modulePath
)

Write-Host "###################################################"
Write-Host "Container Registry Name: $containerRegistryName"
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
        if (Test-Path -Path $file) {
            $fileLocation = (Get-ChildItem -Path $file)
            $folder = $fileLocation.DirectoryName.Split('\')[-1]
            $fileName = $fileLocation.BaseName
            $filePath = $fileLocation.FullName

            $repository = $filePath.ToLower().Split('modules/')[-1].Replace('.bicep', '')

            Write-Host "Folder: $folder"
            Write-Host "Filepath: $filePath"

            Write-Host "Starting to upload module: $repository"

            Write-Host "Get current latest version from ACR"
            if ($null -ne $(az acr repository show --name $containerRegistryName --repository "$repository")) {
                $PublishedVersion = az acr repository show-tags --name "$($containerRegistryName)" --repository "$repository" --orderby time_asc --output json | ConvertFrom-Json

                if ($PublishedVersion.GetType().IsArray) {
                    $currentLatestVersion = $PublishedVersion[-1]
                }
                else {
                    $currentLatestVersion = $PublishedVersion
                }

                $acrMajorVersion = [int]$currentLatestVersion.Split('.')[0]
                $acrMinorVersion = [int]$currentLatestVersion.Split('.')[1]
                $acrIncrementVersion = [int]$currentLatestVersion.Split('.')[-1]
            
                Write-Host "Current latest version on ACR: $acrMajorVersion.$acrMinorVersion.$acrIncrementVersion"
            }
            else {
                $acrMajorVersion = 0
                $acrMinorVersion = 0
                $acrIncrementVersion = 0
                Write-Host "No module found in ACR."
            }

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
                $versions[$fileName.ToLower()] = $versionNumber
            }
            else {
                Write-Error "No version number was found. Module will not be uploaded to ACR."
            }
        }
        else {
            Write-Host "$file was either removed or renamed. Skipping this file."
        }
    }
    else {
        Write-Host "$file is not a bicep file. Skipping this file."
    }
}

Write-Host "##vso[task.setvariable variable=ModuleVersions]$($versions | ConvertTo-Json -Compress)"
