# Creates a new component prototype for a given type
function New-DscComponentPrototype
{
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Type,

        [Parameter(Mandatory=$false)]
        [switch]$Dsc,

        [Parameter(Mandatory=$false)]
        [string]$DscName,

        [Parameter(Mandatory=$false)]
        [string]$DscModule
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

    # Dsc parameters are only specified to New-DscComponentPrototype on the original prototype; when we create a dummy prototype for
    # the purposes of creating a new instance, all of the members below will be copied by the new instance object via Copy-DscComponentPrototype
    if($Dsc)
    {
        $dscMethods = @{
            Init={
                $config = Get-DscLocalConfigurationManager

                if($config.RefreshMode -ne "Disabled")
                {
                    throw "Cannot apply DSC node '$this': DSC refresh mode must be set to 'Disabled', however current LCM setting is '$($config.RefreshMode)'. LCM must disabled in order to invoke DSC resources manually. For more information please see Disable-DscLcm."
                }

                if($Global:miniDscKnownDscModules -eq $null)
                {
                    $Global:miniDscKnownDscModules = @()
                }

                $match = $Global:miniDscKnownDscModules | where { $_ -eq $this.DscModule }

                if(!$match)
                {
                    $module = GetModule $this.DscModule

                    if($module)
                    {
                        $Global:miniDscKnownDscModules += $module.Name
                    }
                    else
                    {
                        $this.LogWarning("DSC module '$($this.DscModule)' is not installed; installing module...")

                        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

                        InstallPackage $this.DscModule | Out-Null

                        $Global:miniDscKnownDscModules += $this.DscModule
                    }
                }
            }

            Test={
                $result = $this.InvokeDscResource("Test", $this.Ensure)

                return $result.InDesiredState
            }
            
            Apply={
                $this.InvokeDscResource("Set", $this.Ensure)
            }

            Revert={
                $ensure = if ($this.Ensure -eq "Present") { "Absent" } else { "Present" }

                $this.InvokeDscResource("Set", $ensure)
            }

            InvokeDscResource={
                param($method, $ensure)

                $property = @{}

                foreach($member in $this.DscMembers)
                {
                    if($this.$member -ne $null)
                    {
                        $property.$member = $this.$member
                    }                    
                }

                $property.Ensure = $ensure

                $dscArgs=@{
                    Name=$this.DscName
                    Method=$method
                    ModuleName=$this.DscModule
                    Property=$property
                }

                return InvokeDscResource $dscArgs
            }
        }

        foreach($method in $dscMethods.Keys)
        {
            $value = $dscMethods[$method]

            $component | Add-Member ScriptMethod $method $value -Force
        }

        $component | Add-Member DscName $DscName
        $component | Add-Member DscModule $DscModule
        $component | Add-Member Ensure $null
    }

    return $component
}

# Helper functions to work around Pester's dodgy mocking

function GetModule($name)
{
    Get-Module $name -ListAvailable
}

function InvokeDscResource($dscArgs)
{
    Invoke-DscResource @dscArgs
}

function InstallPackage($name)
{
    Install-Package $name -ForceBootstrap -Force
}