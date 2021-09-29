function Config
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Hashtable]$Config
    )

    $Config.PSObject.TypeNames.Add("Config")

    $Config
}