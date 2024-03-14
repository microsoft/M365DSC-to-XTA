function ConvertFrom-DSCToXTA
{
    [CmdletBinding()]
    [OutputPath([System.String])]
    param(
        [Parameter()]
        [System.String]
        $Path,

        [Parameter()]
        [System.String]
        $Content
    )
    $Global:M365DSCSkipDependenciesValidation = $true
    if ([System.String]::IsNullOrEmpty($Content) -and -not [System.String]::IsNullOrEmpty($Path))
    {
        $Content = Get-Content -Path $Path -Raw
    }

    $parsedContent = ConvertTo-DSCObject -Content $Content
}