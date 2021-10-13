function Component
{
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [Hashtable]$Definition,

        [Parameter(Mandatory = $false)]
        [string]$Extends,

        [Parameter(Mandatory = $false)]
        [CmdletType]$CmdletType = "Name",

        [Parameter(Mandatory = $false)]
        [Hashtable[]]$ExtraParameters
    )

    $def = [PSCustomObject]$Definition
    $properties = $def.PSObject.Properties

    $component = $null

    if($Extends)
    {
        $prototype = [Component]::GetComponentPrototype($Extends)

        $component = $prototype | Copy-DscComponentPrototype
        $component.Type = $Name
    }
    else
    {
        $component = New-DscComponentPrototype $Name
    }

    $realMethods = [Component].GetMethods().Name | where { $_ -notlike "get_*" -and $_ -notlike "set_*" }

    foreach($property in $properties)
    {
        if($property.Value -is [ScriptBlock])
        {
            $component | Add-Member ScriptMethod $property.Name $property.Value -Force
        }
        else
        {
            $component | Add-Member $property.Name $property.Value -Force
        }
    }

    [Component]::KnownComponents.$Name = $component

    RegisterFunctionForCmdletType $Name $CmdletType $ExtraParameters
}

function RegisterFunctionForCmdletType($Name, $CmdletType, $ExtraParameters)
{
    if($CmdletType -ne "None")
    {
        Get-Item Function:\$Name -ErrorAction SilentlyContinue|Remove-Item
    }

    if($ExtraParameters)
    {
        foreach($item in $ExtraParameters)
        {
            if(!$item.Type)
            {
                $item.Type = "string"
            }

            if(!$item.Mandatory)
            {
                $item.Mandatory=$true
            }
        }
    }
    else
    {
        $ExtraParameters =@()
    }

    $configBody = @"
`$PSCmdlet.MyInvocation.BoundParameters.Remove('Hashtable') | Out-Null
`$PSCmdlet.Myinvocation.BoundParameters['ScriptBlock'] = {
    Config `$Hashtable
}.GetNewClosure()
"@

    switch($CmdletType)
    {
        None {}

        Empty {
            Register-MiniDscFunction $Name @(
                @{Name="ScriptBlock"; Type="ScriptBlock"; Mandatory=$false; Position = 0}
                $ExtraParameters
            )
        }

        Name {
            Register-MiniDscFunction $Name @(
                @{Name="Name";        Type="string";      Mandatory=$true;  Position = 0}
                @{Name="ScriptBlock"; Type="ScriptBlock"; Mandatory=$false; Position = 1}
                $ExtraParameters
            )
        }

        Config {
            Register-MiniDscFunction $Name @(
                @{Name="Hashtable"; Type="Hashtable";    Mandatory=$false;  Position = 0}
                $ExtraParameters
            ) -Body $configBody
        }

        NamedConfig {
            Register-MiniDscFunction $Name @(
                @{Name="Name";      Type="string";      Mandatory=$true;  Position = 0}
                @{Name="Hashtable"; Type = "Hashtable"; Mandatory=$false; Position = 1}
                $ExtraParameters
            ) -Body $configBody
        }

        NamedValue {
            Register-MiniDscFunction $Name @(
                @{Name="Name"; Type="string"; Mandatory=$true; Position=0}
                @{Name="Value"; Type="object"; Mandatory=$true; Position=1}
                $ExtraParameters
            )
        }

        Value {
            Register-MiniDscFunction $Name @(
                @{Name="Value"; Type="object"; Mandatory=$true;  Position = 0}
                $ExtraParameters
            )
        }

        default {
            throw "Don't know how to handle cmdlet type '$CmdletType'"
        }
    }
}