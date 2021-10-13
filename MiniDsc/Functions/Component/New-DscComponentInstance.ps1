function New-DscComponentInstance
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        $Cmdlet
    )

    Get-CallerPreference $PSCmdlet $ExecutionContext.SessionState

    $componentName = $Cmdlet.MyInvocation.MyCommand.Name

    $parameters = $Cmdlet.MyInvocation.BoundParameters

    $prototype = [Component]::GetComponentPrototype($componentName)

    $component = $prototype | Copy-DscComponentPrototype -AsInstance

    $component.Children = Get-DscComponentChildren $component $parameters

    if($parameters.ContainsKey("ForEach"))
    {
        $component.ForEach = $parameters["ForEach"]
    }

    Apply-DscBoundParameters $component $Cmdlet
    MaybeTestConfig $component $prototype

    return $component
}

function Get-DscComponentChildren($component, $parameters)
{
    if ($parameters.ContainsKey("ScriptBlock"))
    {
        $scriptBlock = $parameters["ScriptBlock"]

        # If ScriptBlock wasn't a mandatory parameter, its value could simply be null
        if(!$scriptBlock)
        {
            return
        }

        $initialChildren = & $scriptBlock

        $config = $initialChildren | where { $_ -is [Hashtable] -and $_.PSObject.TypeNames.Contains("Config") }

        if($config)
        {
            Apply-DscConfigMember $component
        }

        $children = $initialChildren | where { $_ -ne $config }

        foreach($child in $children)
        {
            if ($child.HasMethod("VerifyParent"))
            {
                $child.VerifyParent($component) | Out-Null
            }

            $child.Parent = $component
        }

        $parameters.Remove("ScriptBlock") | Out-Null

        return $children
    }
}

function Apply-DscConfigMember($component)
{
    $realMembers = $component.PSObject.Properties | where MemberType -eq NoteProperty

    foreach ($property in ([PSCustomObject]$config).PSObject.Properties)
    {
        $match = $realMembers | where Name -eq $property.Name

        if($match)
        {
            if($property.Value -is [Hashtable])
            {
                $match.Value = (ConvertTo-PsObject $property.Value)
            }
            elseif($property.Value -is [object[]] -and !($property.Value|where { $_ -isnot [Hashtable] }))
            {
                $match.Value = $property.Value | foreach { ConvertTo-PsObject $_ }
            }
            else
            {
                $match.Value = $property.Value
            }
        }
    }
}

function Apply-DscBoundParameters($component, $cmdlet)
{
    foreach($member in $component.PSObject.Properties)
    {
        if($member.MemberType -eq "NoteProperty")
        {
            if($member.Name -eq "VerifyConfig")
            {
                $component.PSObject.Properties.Remove("VerifyConfig")
            }

            if($cmdlet.MyInvocation.BoundParameters.ContainsKey($member.Name))
            {
                $component.$($member.Name) = $cmdlet.MyInvocation.BoundParameters[$member.Name]
            }
        }
    }
}

function MaybeTestConfig($component, $prototype)
{
    if($prototype.PSObject.Properties|where Name -eq VerifyConfig)
    {
        $roots = $prototype.VerifyConfig

        foreach($record in $roots)
        {
            Test-DscConfigMember $component $record
        }
    }
}