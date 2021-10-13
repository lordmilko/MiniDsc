# Creates a new component prototype for a given type
function New-DscComponentPrototype
{
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Type
    )

    $component = New-Object Component $Type
    $component.PSObject.TypeNames.Add("ComponentPrototype")

    $methods = @{
        GetLast     = { param($type) $global:currentExecutor.GetLast($type) }

        LogInfo     = { param($message) $global:currentExecutor.LogInfo($message) }
        LogWarning  = { param($message) $global:currentExecutor.LogWarning($message) }

        HasMethod   = { param($name) ($this.PSObject.Methods|where Name -eq $name).Count -gt 0 }
        HasProperty = { param($name) ($this.PSObject.Properties|where Name -eq $name).Count -gt 0 }
        ToString    = {
            $name = $this.PSObject.Properties|where Name -eq "Name"

            if($name)
            {
                return "[$($this.Type)] $($name.Value)"
            }
            else
            {
                return $this.Type
            }
        }

        GetParent   = {
            param($type)

            $parent = $this.Parent

            while($parent -ne $null)
            {
                if($parent.Type -eq $type)
                {
                    return $parent
                }

                $parent = $parent.Parent
            }

            throw "Could not find parent of type '$type'"
        }

        GetChildren = {
            param($type)

            $found = $false

            foreach($child in $this.Children)
            {
                if($child.Type -eq $type)
                {
                    $child

                    $found = $true
                }
            }

            if(!$found)
            {
                throw "Could not find any children of type '$type'"
            }
        }

        Find = {
            param($type)

            $parent = $this.Parent

            if($parent -eq $null)
            {
                $parent = $this
            }

            while($true)
            {
                if ($parent.Type -eq $type)
                {
                    return $parent
                }

                if($parent.Parent -eq $null)
                {
                    break
                }

                $parent = $parent.Parent
            }

            $findInternal = {
                param($parent, $type)

                foreach($child in $parent.Children)
                {
                    if($child.Type -eq $type)
                    {
                        return $child
                    }

                    return & $findInternal $child $type
                }

                return $null
            }

            $match = & $findInternal $parent $type

            if(!$match)
            {
                throw "Could not find a component of type '$type' in the tree."
            }

            return $match
        }
    }

    foreach($method in $methods.Keys)
    {
        $value = $methods[$method]

        $component | Add-Member ScriptMethod $method $value -Force
    }

    return $component
}