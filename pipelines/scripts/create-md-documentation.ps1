[CmdletBinding()]
 
Param (
    [Parameter(Mandatory = $true)][string]$TemplateFolder,
    [Parameter(Mandatory = $true)][string]$OutputFolder,
    [Parameter(Mandatory = $true)][string]$ModuleVersions,
    [Parameter(Mandatory = $false)][bool]$KeepStructure = $True,
    [Parameter(Mandatory = $false)][bool]$IncludeWikiTOC = $false,
    [Parameter(Mandatory = $true)][string]$organizationName,
    [Parameter(Mandatory = $true)][string]$projectName,
    [Parameter(Mandatory = $true)][string]$repoName,
    [Parameter(Mandatory = $false)][string]$targetBranch = "main"
)
 
BEGIN {
    Write-Host ("TemplateFolder       : $($TemplateFolder)")
    Write-Host ("OutputFolder         : $($OutputFolder)")
    Write-Host ("KeepStructure        : $($KeepStructure)")
    Write-Host ("IncludeWikiTOC       : $($IncludeWikiTOC)")
    Write-Host ("organizationName     : $($organizationName)")
    Write-Host ("projectName          : $($projectName)")
    Write-Host ("repoName             : $($repoName)")
    Write-Host ("targetBranch         : $($targetBranch)")
 
    $templateNameSuffix = ".md"
}
PROCESS {

    try {
        az config set extension.use_dynamic_install=yes_without_prompt
        Write-Host ("Starting documentation generation for folder $($TemplateFolder)")
 
        if (!(Test-Path $OutputFolder)) {
            Write-Host ("Output path does not exists creating the folder: $($OutputFolder)")
            New-Item -ItemType Directory -Force -Path $OutputFolder
        }

        $versions = $ModuleVersions | ConvertFrom-Json
        Write-Host $versions
 
        # Get the scripts from the folder
        $bicepTemplates = Get-Childitem $TemplateFolder -Filter "*.bicep" -Recurse

        foreach ($bicepTemplate in $bicepTemplates) {
            foreach ( $key in $versions.PSObject.Properties) {
                if ($key -eq $bicepTemplate.BaseName) {
                    Write-Host ("Converting bicep to json: $($bicepTemplate.FullName)")
            
                    az bicep build --file $bicepTemplate.FullName
                }
            }
        }

        $armTemplates = Get-Childitem $TemplateFolder -Filter "*.json" -Recurse
        for ($i = 0; $i -lt $armTemplates.Length; $i++) {
            foreach ($armTemplate in $armTemplates[$i]) {
                $templateContent = Get-Content -Path $armTemplate -Raw
                $pattern = '(?<="description": ".*?)\\r\\n(?=(.*?"))'
                $templateContent = $templateContent -replace $pattern, "<br />"
                $templateObject = ConvertFrom-Json $templateContent -ErrorAction Stop

                Write-Output $templateObject
                Write-Output "BaseName: $($armTemplate.BaseName)"  

                if (!$templateObject) {
                    Write-Host ("Template file is not a valid json, please review the template")
                }
                else {
                    $outputFile = ("$($OutputFolder)$($armTemplate.FullName.Split($TemplateFolder)[-1].Replace('.json',''))$($templateNameSuffix)")
                    
                    if (!(Test-Path $outputFile)) {
                        Write-Host ("Output path does not exist, creating the folder: $($outputFile.Replace("/$($armTemplate.BaseName)$templateNameSuffix",''))")
                        New-Item -ItemType Directory -Force -Path $outputFile.Replace("/$($armTemplate.BaseName)$templateNameSuffix",'')
                    }

                    Write-Host $outputFile
                    Out-File -FilePath $outputFile
                }
                Write-Host "Include Wiki TOC: $IncludeWikiTOC"
                if ($IncludeWikiTOC) {
                    ("[[_TOC_]]`n") | Out-File -FilePath $outputFile
                    "`n" | Out-File -FilePath $outputFile -Append
                }
                $isNewLanguageVersion = $false
                Write-Host 'Getting languageversion'
                if ((($templateObject | get-member).name) -match "languageVersion") {
                    $isNewLanguageVersion = $true
                }

                Write-Host 'Getting metadata'
                if ((($templateObject | get-member).name) -match "metadata") {
                    if ((($templateObject.metadata | get-member).name) -match "Description") {
                        Write-Host ("Description found. Adding to parent page and top of the template specific page")
                            ("## Description") | Out-File -FilePath $outputFile -Append
                        $templateObject.metadata.Description | Out-File -FilePath $outputFile -Append
                    }
                }
                
                Write-Host 'Add Pull Request data'
                az devops configure --defaults organization=https://dev.azure.com/$organizationName/
                $pullrequests = az repos pr list --project $projectName --repository $repoName --status completed --target-branch $targetBranch --include-links | ConvertFrom-Json
                $lastpr = $pullrequests[0]

                if ($null -eq $lastpr) {
                    Write-Host "No pull requests found"
                    continue
                }
                else {
                    $StringBuilderParameter = @()
                    $StringBuilderParameter += "## Pull Request Details"
                    $StringBuilderParameter += "Title: $($lastpr.title)"
                    $StringBuilderParameter += "Url: https://dev.azure.com/$organizationName/$projectName/_git/$repoName/pullrequest/$($lastpr.pullRequestId)"
                    $StringBuilderParameter | Out-File -FilePath $outputFile -Append
                }

                Write-Host 'Getting parameters'
                if ((($templateObject | get-member).name) -match "parameters") {
                ("## Parameters") | Out-File -FilePath $outputFile -Append
                    # Create a Parameter List Table
                    $parameterHeader = "| Parameter Name | Parameter Type | Parameter Description | Parameter DefaultValue | Parameter AllowedValues |"
                    $parameterHeaderDivider = "| --- | --- | --- | --- | --- | "
                    $parameterRow = " | {0}| {1} | {2} | {3} | {4} |"
 
                    $StringBuilderParameter = @()
                    $StringBuilderParameter += $parameterHeader
                    $StringBuilderParameter += $parameterHeaderDivider
 
                    $StringBuilderParameter += $templateObject.parameters | get-member -MemberType NoteProperty | ForEach-Object { $parameterRow -f $_.Name , $templateObject.parameters.($_.Name).type , ($templateObject.parameters.($_.Name)).metadata.description , $templateObject.parameters.($_.Name).defaultValue , (($templateObject.parameters.($_.Name).allowedValues) -join '<br />') }
                    
                    $StringBuilderParameter | Out-File -FilePath $outputFile -Append
                }
                else {
                    Write-Host ("This template does not contain parameters")
                }

                Write-Host 'Getting variables'
                if ((($templateObject | get-member).name) -match "variables") {
                ("## Variables") | Out-File -FilePath $outputFile -Append
                    #Variables
                    $Variables = foreach ($property in $templateObject.variables.PSObject.Properties) {
                        $propertyValue = $property.Value
                        $propertyValue = $propertyValue -Replace "\[", "" -Replace "\]", ""
                        [PSCustomObject]@{
                            Name  = $property.Name
                            Value = $propertyValue
                        }
                    }

                    # Create a Variable List Table
                    $variableHeader = "| Variable Name | Variable Value |"
                    $variableHeaderDivider = "| --- | --- |"
                    $variableRow = " | {0} | {1} |"
 
                    $StringBuilderVariable = @()
                    $StringBuilderVariable += $variableHeader
                    $StringBuilderVariable += $variableHeaderDivider
 
                    $StringBuilderVariable += $Variables | ForEach-Object { $variableRow -f $_.Name, $_.Value }
                    $StringBuilderVariable | Out-File -FilePath $outputFile -Append
                }
                else {
                    Write-Host ("This template does not contain variables")
                }

                Write-Host 'Getting resources'
                if ((($templateObject | get-member).name) -match "resources") {
                    ("## Resources") | Out-File -FilePath $outputFile -Append
                    # Create a Resource List Table
                    $resourceHeader = "| Resource Name | Resource Type |"
                    $resourceHeaderDivider = "| --- | --- | "
                    $resourceRow = " | {0} | {1} |"

                    $StringBuilderResource = @()
                    $StringBuilderResource += $resourceHeader
                    $StringBuilderResource += $resourceHeaderDivider
                    
                    $listOfResources = @()
                    $resources = @()

                    if ($isNewLanguageVersion) {
                        $listOfResources = $templateObject.resources | get-member -MemberType NoteProperty
                        $resources = foreach ($resource in $listOfResources) {
                            $name = $resource.Name
                            $resourceName = $templateObject.resources.($name).name
                            if ($resourceName.StartsWith("[format('")) {
                                $resourceName = $resourceName.Replace("[format('", "").Replace("')]", "")
                                $resourceName = $resourceName.Replace(" ", "")
                                $resourceName = $resourceName.Substring($resourceName.IndexOf(",") + 1)
                                $resourceName = $resourceName.Replace(",", "/").Replace("'", "").Trim()
                            }
                            $resourceRow -f $resource.Name, $templateObject.resources.($name).type
                        }
                    }
                    else {
                        $listOfResources = $templateObject.resources
                        $resources = foreach ($resource in $listOfResources) {
                            $name = $resource.Name
                            if ($name.StartsWith("[format('")) {
                                $name = $name.Replace("[format('", "").Replace("')]", "")
                                $name = $name.Replace(" ", "")
                                $name = $name.Substring($name.IndexOf(",") + 1)
                                $name = $name.Replace(",", "/").Replace("'", "").Trim()
                            }
                            $resourceRow -f $name, $resource.Type
                        }
                    }

                    $StringBuilderResource += $resources
                    $StringBuilderResource | Out-File -FilePath $outputFile -Append
                }
                else {
                    Write-Error ("This is not a valid template, a template needs to contain resources")
                }
                
                Write-Host 'Getting outputs'
                if ((($templateObject | get-member).name) -match "outputs") {
                    Write-Host ("Output objects found.")
                    if (Get-Member -InputObject $templateObject.outputs -MemberType 'NoteProperty') {
                            ("## Outputs") | Out-File -FilePath $outputFile -Append
                        # Create an Output List Table
                        $outputHeader = "| Output Name | Output Type | Output Value |"
                        $outputHeaderDivider = "| --- | --- | --- |  "
                        $outputRow = " | {0}| {1} | {2} | "
 
                        $StringBuilderOutput = @()
                        $StringBuilderOutput += $outputHeader
                        $StringBuilderOutput += $outputHeaderDivider
 
                        $StringBuilderOutput += $templateObject.outputs | get-member -MemberType NoteProperty | ForEach-Object { $outputRow -f $_.Name , $templateObject.outputs.($_.Name).type , $templateObject.outputs.($_.Name).value }
                        $StringBuilderOutput | Out-File -FilePath $outputFile -Append
                    }
                }
                else {
                    Write-Host ("This template does not contain outputs")
                }
            }
        }
    }
    catch {
        Write-Host "Something went wrong while generating the output documentation: $_"
        Write-Debug 
    }
}
END {}