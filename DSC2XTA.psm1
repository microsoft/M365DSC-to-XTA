function ConvertFrom-DSCToXTA
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter()]
        [System.String]
        $Path,

        [Parameter()]
        [System.String]
        $Content,

        [Parameter()]
        [System.Boolean]
        $Compress = $true
    )
    # Initialization - Skip 
    $Global:M365DSCSkipDependenciesValidation = $true

    # Initialization - Load the Mapping Information
    $mappingPath = Join-Path -Path $PSScriptRoot -ChildPath 'DSC2XTAMappings.psd1' -Resolve
    $mappings = Import-PowerShellDataFile $mappingPath

    # Initialization - Load the XTA Template
    $templatePath = Join-Path -Path $PSScriptRoot -ChildPath 'XTATemplate.json' -Resolve
    $templateContent = Get-Content -Path $templatePath -Raw
    $template = ConvertFrom-JSON $templateContent
    
    # If a path to a file is provided, then get its raw content
    if ([System.String]::IsNullOrEmpty($Content) -and -not [System.String]::IsNullOrEmpty($Path))
    {
        $Content = Get-Content -Path $Path -Raw
    }

    # Use the DSCParser to convert the file's content into an array of
    # PowerShell objects (Hashtables).
    $parsedContent = ConvertTo-DSCObject -Content $Content `
                                         -IncludeCIMInstanceInfo $false

    # Loop through all the resources and convert them to XTA
    $allResources = @()
    foreach ($resource in $parsedContent)
    {
        $mappedNamespace = $mappings.($resource.ResourceName)
        if (-not [System.String]::IsNullOrEmpty($mappedNamespace))
        {
            $currentResource = @{
                name = $resource.ResourceInstanceName
                type = $mappedNamespace
            }

            $resource.Remove("ResourceInstanceName") | Out-Null
            $resource.Remove("ResourceName") | Out-Null
            $resource.Remove("Credential") | Out-Null
            $resource.Remove("ApplicationId") | Out-Null
            $resource.Remove("TenantId") | Out-Null
            $resource.Remove("CertificateThumbprint") | Out-Null
            $resource.Remove("ApplicationSecret") | Out-Null
            $resource.Remove("CertificatePath") | Out-Null
            $resource.Remove("CertificatePassword") | Out-Null
            $currentResource.Add("properties", $resource)
            $allResources += $currentResource
        }
    }
    $template.Resources = $allResources
    return (ConvertTo-Json $template -Depth 99 -Compress:$Compress)
}
