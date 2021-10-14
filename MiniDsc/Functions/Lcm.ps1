function Disable-DscLcm
{
    [CmdletBinding()]
    param()

    SetDscLcm "Disabled"
}

function Enable-DscLcm
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet("Pull", "Push")]
        $RefreshMode = "Push"
    )

    if($RefreshMode -eq "Pull")
    {
        throw "'Pull' refresh mode requires a configuration repository be specified, which is outside the scope of this cmdlet. Please construct a DSC configuration to Set the LCM 'RefreshMode' to 'Pull' manually."
    }

    SetDscLcm $RefreshMode
}

function SetDscLcm($mode)
{
    [DscLocalConfigurationManager()]
    Configuration LCMSettings {
        Node localhost
        {
            Settings
            {
                RefreshMode = $mode
            }
        }
    }

    $path = Join-Path $env:temp LCMSettings

    LCMSettings -OutputPath $path | Out-Null

    Set-DscLocalConfigurationManager -Path $path

    Remove-Item $path -Recurse -Force
}