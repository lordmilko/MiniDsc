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

        HasMethod   = { param($name) $this.PSObject.Methods|where Name -eq $name }
        HasProperty = { param($name) $this.PSObject.Properties|where Name -eq $name }
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

        GetParent   = { param($type) }
        Find        = { param($type) throw }
    }

    foreach($method in $methods.Keys)
    {
        $value = $methods[$method]

        $component | Add-Member ScriptMethod $method $value -Force
    }

    return $component
}