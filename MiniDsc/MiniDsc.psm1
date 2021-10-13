$files = "Functions","Components" | foreach { gci (Join-Path $PSScriptRoot $_) -Recurse -File }

foreach($file in $files)
{
    . $file.FullName -Force
}

Component Root -CmdletType Empty @{}

enum CmdletType
{
    None        # Don't generate a cmdlet
    Empty       # Cmdlet takes a ScriptBlock
    Name        # Cmdlet takes a name and a ScriptBlock
    Config      # Cmdlet takes a hashtable
    NamedConfig # Cmdlet takes a name and a hashtable
    NamedValue  # Cmdlet takes a name and a value
    Value       # Cmdlet takes a value
}

function Assert-HasMethod
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $Node,

        [Parameter(Mandatory=$true, Position=0)]
        $Name,

        [Parameter(Mandatory=$false)]
        $Extra
    )

    if(!$Node.HasMethod($Name))
    {
        throw "Cannot invoke method '$Name' on value '$Node': method does not exist.$Extra"
    }
}

function Assert-NotHasMethod
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $Node,

        [Parameter(Mandatory=$true, Position=0)]
        $Name,

        [Parameter(Mandatory=$false)]
        $Extra
    )

    if($Node.HasMethod($Name))
    {
        throw "Expected value '$Node' to not have a '$Name' method: $Extra"
    }
}

# Based on https://powershell.org/2014/01/revisited-script-modules-and-variable-scopes/
function Get-CallerPreference
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ $_.GetType().FullName -eq 'System.Management.Automation.PSScriptCmdlet' })]
        $Cmdlet,

        [Parameter(Mandatory = $true, Position = 1)]
        [System.Management.Automation.SessionState]
        $SessionState,

        [Parameter(Mandatory = $false)]
        [string]$DefaultErrorAction
    )

    $preferences = @{
        'ErrorActionPreference' = 'ErrorAction'
        'DebugPreference' = 'Debug'
        'ConfirmPreference' = 'Confirm'
        'WhatIfPreference' = 'WhatIf'
        'VerbosePreference' = 'Verbose'
        'WarningPreference' = 'WarningAction'
    }

    foreach($preference in $preferences.GetEnumerator())
    {
        # If this preference wasn't specified to our inner cmdlet
        if(!$Cmdlet.MyInvocation.BoundParameters.ContainsKey($preference.Value))
        {
            if($PSCmdlet.MyInvocation.BoundParameters.ContainsKey("Default$($preference.Value)"))
            {
                $variable = [PSCustomObject]@{
                    Name = $preference.Name
                    Value = $PSCmdlet.MyInvocation.BoundParameters["Default$($preference.Value)"]
                }
            }
            else
            {
                # Get the value of this preference from the outer scope
                $variable = $Cmdlet.SessionState.PSVariable.Get($preference.Key)
            }

            # And apply it to our inner scope
            if($null -ne $variable -and $null -ne $variable.Value)
            {
                if ($SessionState -eq $ExecutionContext.SessionState)
                {
                    #todo: what is "scope 1"?
                    Set-Variable -Scope 1 -Name $variable.Name -Value $variable.Value -Force -Confirm:$false -WhatIf:$false
                }
                else
                {
                    $SessionState.PSVariable.Set($variable.Name, $variable.Value)
                }
            }
        }
    }
}