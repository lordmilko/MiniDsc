function New-DscComponentInstance
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        $Cmdlet
    )

    Get-CallerPreference $PSCmdlet $ExecutionContext.SessionState

    $componentName = $Cmdlet.MyInvocation.MyCommand.Name
    $prototype = [Component]::GetComponentPrototype($componentName)
    $component = $prototype | Copy-DscComponentPrototype -AsInstance
    $parameters = $Cmdlet.MyInvocation.BoundParameters

    EnterParent $component

    try
    {
        $component.Children = Get-DscComponentChildren $component $parameters

        if($parameters.ContainsKey("ForEach"))
        {
            $component.ForEach = $parameters["ForEach"]
        }

        Apply-DscBoundParameters $component $Cmdlet
        MaybeTestConfig $component $prototype

        if($component.HasMethod("Verify"))
        {
            $component.Verify()
        }
    }
    finally
    {
        ExitParent
    }

    return $component
}

$script:miniDscParentStack = $null

function EnterParent($component)
{
    if($null -eq $script:miniDscParentStack)
    {
        $script:miniDscParentStack = New-Object System.Collections.Generic.Stack[Component]
    }
    else
    {
        $component.Parent = $script:miniDscParentStack.Peek()
    }

    $script:miniDscParentStack.Push($component)
}

function ExitParent
{
    $script:miniDscParentStack.Pop() | Out-Null

    if($script:miniDscParentStack.Count -eq 0)
    {
        $script:miniDscParentStack = $null
    }
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
            Apply-DscConfigMember $component $config
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

function Apply-DscConfigMember($component, $config)
{
    $realMembers = $component.PSObject.Properties | where MemberType -eq NoteProperty

    foreach ($property in ([PSCustomObject]$config).PSObject.Properties)
    {
        $match = $realMembers | where Name -eq $property.Name

        if($match)
        {
            if($property.Value -is [Hashtable]) # Is it a Hashtable of more config values?
            {
                $match.Value = (ConvertTo-PsObject $property.Value)
            }
            elseif($property.Value -is [object[]] -and !($property.Value|where { $_ -isnot [Hashtable] })) # Is it an array of only Hashtables?
            {
                $match.Value = $property.Value | foreach { ConvertTo-PsObject $_ }
            }
            else
            {
                if($property.Value -is [ScriptBlock]) # Is it an expression specifying how its value should be computed?
                {
                    # Replace this NoteProperty with a ScriptProperty!
                    $component.PSObject.Properties.Remove($match.Name)
                    $component | Add-Member ScriptProperty $match.Name $property.Value
                }
                else # It's just some value; assign it
                {
                    $match.Value = $property.Value
                }
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
                $value = $cmdlet.MyInvocation.BoundParameters[$member.Name]

                if($value -is [ScriptBlock])
                {
                    # Replace the NoteProperty with a ScriptProperty
                    $component.PSObject.Properties.Remove($member.Name)
                    $component | Add-Member ScriptProperty $member.Name $value
                }
                else
                {
                    $component.$($member.Name) = $value
                }
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