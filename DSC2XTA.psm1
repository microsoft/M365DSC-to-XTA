function Get-DSCVariables
{
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param(
        [Parameter()]
        [System.String]
        $Content
    )

    $Tokens = $null
    $ParseErrors = $null
    $AST = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$Tokens, [ref]$ParseErrors)

    $variables = @()
    foreach ($token in $Tokens)
    {
        if ($token.Kind -eq 'Variable')
        {
            $variables += $token.Extent.Text
        }
    }

    $variablesToExclude = @('$null', '$false', '$true')

    # sort variable by length descending to avoid partial matches
    return $variables | Where-Object { $_ -notin $variablesToExclude } | Select-Object -Unique | Sort-Object -Property Length -Descending

}

function Parse-XTAProperty
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter()]
        [System.String]
        $Property,

        [Parameter()]
        [System.String[]]
        $Variables
    )

    foreach($variable in $Variables)
    {
        # matches params of the type : [parameters('FQDN')] where the parameter value is used as a single value.
        if ($Property -eq $variable)
        {
            $Property = "[parameters($($variable.Substring(1)))]"
            return $Property
        }
    }

    # matches params of the type : [concat('admin_', parameters('FQDN'), '@', parameters('Domain'), '.com')] where the parameter value is used within a list.
    $hasVariable = $false
    foreach($variable in $Variables) 
    {
        $hasVariable = $hasVariable -or $Property.Contains($variable)

        $property = $Property -replace $variable, ",parameters($($variable.Substring(1))),"
    }

    if($hasVariable)
    {
        $property = "[concat($property)]"
    }

    return $Property
}

function Parse-XTAProperties
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [System.Collections.Hashtable]
        $Resource,

        [Parameter()]
        [System.String[]]
        $Variables
    )

    $ParsedResource = @{}

    foreach ($key in $Resource.Keys)
    {
        $value = $Resource[$key]
        $parsedValue = $value

        if ($value -is [System.String])
        {
            $parsedValue = Parse-XTAProperty -Property $value -Variables $Variables
        }
        elseif ($value -is [System.Collections.Hashtable])
        {
            $parsedValue = Parse-XTAProperties -Resource $value -Variables $Variables
        }
        elseif ($value -is [System.Collections.ArrayList])
        {
            $parsedValue = @()
            foreach ($item in $value)
            {
                if ($item -is [System.String])
                {
                    $parsedItem = Parse-XTAProperty -Property $item -Variables $Variables
                    $parsedValue += $parsedItem
                }
                elseif ($item -is [System.Collections.Hashtable])
                {
                    $parsedItem = Parse-XTAProperties -Resource $item -Variables $Variables
                    $parsedValue += $parsedItem
                }
            }
        }

        $ParsedResource.Add($key, $parsedValue)
    }

    return $ParsedResource
}

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
        $Compress = $false
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

    # Get all the variables used in the DSC configuration
    $variables = Get-DSCVariables -Content $Content

    # Loop through all the resources and convert them to XTA
    $allResources = @()
    foreach ($resource in $parsedContent)
    {
        $mappedNamespace = $mappings.($resource.ResourceName)
        if (-not [System.String]::IsNullOrEmpty($mappedNamespace))
        {
            $currentResource = @{
                displayname = $resource.ResourceInstanceName
                resourceType = $mappedNamespace
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

            $resource = Parse-XTAProperties -Resource $resource -Variables $variables

            $currentResource.Add("properties", $resource)
            $allResources += $currentResource
        }
    }
    $template.Resources = $allResources
    return (ConvertTo-Json $template -Depth 99 -Compress:$Compress)
}
