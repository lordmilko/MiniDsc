function Component
{
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [Hashtable]$Definition,

        [Parameter(Mandatory = $false, ParameterSetName="Default")]
        [string]$Extends,

        [Parameter(Mandatory = $false, ParameterSetName="Default")]
        [CmdletType]$CmdletType = "Name",

        [Parameter(Mandatory = $false)]
        [Hashtable[]]$ExtraParameters,

        [Parameter(Mandatory = $false, ParameterSetName="Dsc")]
        [switch]$Dsc,

        [Parameter(Mandatory = $false, ParameterSetName="Dsc")]
        [string]$DscName,

        [Alias("ModuleName","DscModule","DscModuleName")]
        [Parameter(Mandatory = $false, ParameterSetName="Dsc")]
        [string]$Module = "PSDesiredStateConfiguration"
    )

    if($PSCmdlet.ParameterSetName -eq "Dsc")
    {
        if(!$DscName)
        {
            $DscName = $Name
        }

        $CmdletType = "Custom"
    }

    $def = [PSCustomObject]$Definition
    $properties = $def.PSObject.Properties

    $component = $null

    if($Extends)
    {
        $prototype = [Component]::GetComponentPrototype($Extends)

        $component = $prototype | Copy-DscComponentPrototype
        $component.Type = $Name

        $component | Add-Member Base (New-Object PSObject) -Force
    }
    else
    {
        $component = New-DscComponentPrototype $Name -Dsc:$($PSCmdlet.ParameterSetName -eq "Dsc") -DscName $DscName -DscModule $Module
    }

    $realMethods = [Component].GetMethods().Name | where { $_ -notlike "get_*" -and $_ -notlike "set_*" }

    foreach($property in $properties)
    {
        if($Extends)
        {
            $original = $component.PSObject.Members[$property.Name]

            if($original)
            {
                $value = $null

                if($original.MemberType -eq "ScriptMethod")
                {
                    $value = $original.Script
                }
                else
                {
                    $value = $original.Value
                }

                $component.Base | Add-Member $original.MemberType $original.Name $value
            } 
        }

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

    if ($PSCmdlet.ParameterSetName -eq "Dsc")
    {
        if($ExtraParameters -eq $null)
        {
            $ExtraParameters = @()
        }

        $excluded = @()

        foreach($key in $Definition.Keys)
        {
            $value = $Definition[$key]

            if($value -is [ScriptBlock])
            {
                $excluded += $key
                continue
            }

            $config = @{Name=$key; Mandatory=$false; Type="object"}

            if($value -is [int])
            {
                $config.Mandatory = $true
                $config.Position = $value
            }

            $ExtraParameters += $config
        }

        $nextPosition = 0

        $lastPosition = $ExtraParameters|sort { $_.Position }

        if($lastPosition)
        {
            $nextPosition = ($lastPosition|select -last 1).Position + 1
        }

        $ExtraParameters += @{Name="ScriptBlock"; Type="ScriptBlock"; Mandatory=$false; Position = $nextPosition}

        $ExtraParameters += @{
            Name="Ensure"
            Mandatory=$false
            Attributes="[ValidateSet('Present', 'Absent')]"
            Default="Present"
        }

        $component | Add-Member DscMembers ($Definition.Keys | where { $_ -notin $excluded })
    }

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

            if(!$item.ContainsKey("Mandatory"))
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

        Custom {
            Register-MiniDscFunction $Name $ExtraParameters
        }

        default {
            throw "Don't know how to handle cmdlet type '$CmdletType'"
        }
    }
}