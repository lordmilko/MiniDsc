#region Apply

function Invoke-ApplyRunner
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$false)]
        [string]$InvokeType,

        [Parameter(Mandatory=$true)]
        [string]$WaitMode
    )

    $stepConfig = $Executor | InvokeRunnerInit $Node -InvokeType $InvokeType -WaitMode $WaitMode

    if($WaitMode -ne "Continue")
    {
        $Executor | InvokeRunnerDynamicSteps $Node -Mode Apply
        $Executor | InvokeRunnerNormalSteps $Node $stepConfig -Mode Apply -WaitMode $WaitMode
    }

    if($WaitMode -eq "None" -or $WaitMode -eq "Continue")
    {
        $Executor | InvokeRunnerChildren $Node -Mode Apply
    }

    $Executor | InvokeRunnerEnd $Node
}

#endregion
#region Revert

function Invoke-RevertRunner
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$false)]
        [string]$InvokeType
    )

    $stepConfig = $Executor | InvokeRunnerInit $Node -InvokeType $InvokeType -WaitMode None

    $Executor | InvokeRunnerChildren $Node -Mode Revert
    $Executor | InvokeRunnerNormalSteps $Node $stepConfig -Mode Revert -WaitMode None
    $Executor | InvokeRunnerDynamicSteps $Node -Mode Revert

    $Executor | InvokeRunnerEnd $Node
}

#endregion
#region Common

function InvokeRunnerInit
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$false)]
        [string]$InvokeType,

        [Parameter(Mandatory=$true)]
        [string]$WaitMode
    )

    if($InvokeType)
    {
        $InvokeType = "[$InvokeType]"
    }

    $processingType = "Processing"

    if($WaitMode -eq "Continue")
    {
        $processingType = "Continuing"
    }

    $Executor.LogLevel("$($InvokeType)$($processingType) node '$Node'")
    $Executor.LastOfType.$($Node.Type) = $Node
    $Executor.IncrementLevel()

    if($Node.HasMethod("Init"))
    {
        $Node.Init() | Out-Null
    }

    $steps = @($null)
    $largestLength = $null

    if($Node.HasProperty("Steps"))
    {
        $steps = @($Node.Steps)
        $largestLength = $steps|foreach {$_.Length}|sort -Descending|select -first 1
    }

    return [PSCustomObject]@{
        Steps = $steps
        LargestLength = $largestLength
    }
}

function InvokeRunnerDynamicSteps
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$true)]
        $Mode
    )

    if($Node.HasMethod("DynamicSteps"))
    {
        $dynamicSteps = $Node.DynamicSteps()

        if($Mode -eq "Revert")
        {
            [array]::Reverse($dynamicSteps)
        }

        foreach($dynamicStep in $dynamicSteps)
        {
            $dynamicStep.Parent = $Node

            $Executor | RecurseInvokeRunner $dynamicStep -Mode $Mode -WaitMode None
        }
    }
}

function InvokeRunnerNormalSteps
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$true, Position = 1)]
        $StepConfig,

        [Parameter(Mandatory=$true)]
        $Mode,

        [Parameter(Mandatory=$true)]
        $WaitMode
    )

    if($Mode -eq "Revert" -and !($StepConfig.Steps.Count -eq 1 -and $StepConfig.Steps[0] -eq $null))
    {
        [array]::Reverse($StepConfig.Steps)
    }

    foreach($step in $StepConfig.Steps)
    {
        $prefix = $null
        $testMessage = $null
        $applyMessage = $null
        $alreadyAppliedMessage=$null

        $pastTense = "applied"

        if($Mode -ne "Apply")
        {
            $pastTense = $Mode.ToLower() + "ed"
        }

        if($step -ne $null)
        {
            $Node | Assert-HasMethod "Test$step" -Extra " Tests for all actions specified in 'Steps' must be defined."

            $reason = " Specific step methods must be defined when 'Steps' is defined (i.e. TestFoo, ApplyFoo, RevertFoo)."

            $Node | Assert-NotHasMethod "Test" -Extra $reason
            $Node | Assert-NotHasMethod "Apply" -Extra $reason
            $Node | Assert-NotHasMethod "Revert" -Extra $reason

            $prefix = "$($step.PadRight($($StepConfig.LargestLength))) : "
            $applyMessage = "$($prefix)$($Mode)ing step"
            $alreadyAppliedMessage = "$($prefix)Step has already been $pastTense"
        }
        else
        {
            $applyMessage = "$($Mode)ing node '$node'"
            $alreadyAppliedMessage = "Node '$Node' has already been $pastTense"
        }

        if($Node.HasMethod("Test$step"))
        {
            $testResult = $node."Test$step"()

            if(!$Executor.Results.ContainsKey($Node))
            {
                $Executor.Results.Add($node, @{})
            }

            $key = $step

            if($step -eq $null)
            {
                $key = "Default"
            }

            $Executor.Results[$Node].Add($key, $testResult)

            if([Component]::IsPermanent.Equals($testResult))
            {
                $shouldProcess = $false
            }
            else
            {
                if($Mode -eq "Revert")
                {
                    if($testResult)
                    {
                        $shouldProcess = $true
                    }
                }
                else
                {
                    if(!$testResult)
                    {
                        $shouldProcess = $true
                    }
                }
            }

            if($shouldProcess)
            {
                $Executor.LogSuccess($applyMessage)

                $Node | Assert-HasMethod "$Mode$step"

                try
                {
                    $Node."$Mode$($step)"() | Out-Null
                }
                catch
                {
                    throw $_.Exception.InnerException
                }
            }
            else
            {
                if([Component]::IsPermanent.Equals($testResult))
                {
                    $Executor.LogWarning("Node '$Node' is a permanent resource and cannot be modified")
                }
                else
                {
                    $Executor.LogWarning($alreadyAppliedMessage)
                }                
            }
        }
        else
        {
            $Executor.LogQuiet("No 'Test' method found on container '$Node' with $($Node.Children.Count) children")
        }
    }
}

function InvokeRunnerChildren
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$true)]
        $Mode
    )

    if($Mode -ne "Revert")
    {
        $Executor | InvokeRunnerNormalChildren $Node -Mode $Mode
        $Executor | InvokeRunnerForEachChildren $Node -Mode $Mode
    }
    else
    {
        $Executor | InvokeRunnerForEachChildren $Node -Mode $Mode
        $Executor | InvokeRunnerNormalChildren $Node -Mode $Mode
    }
}

function InvokeRunnerNormalChildren
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$true)]
        $Mode
    )

    if($Node.Children)
    {
        $waitMode = "None"

        $children = @($Node.Children|where { !$_.ForEach })

        if($Mode -eq "Revert")
        {
            [array]::Reverse($children)
        }
        else
        {
            $waitable = $children | where { $_.HasMethod("WaitAsync") -or $_.HasProperty("WaitAsync") }

            if($waitable)
            {
                $Executor | InvokeWaitableChildren $Waitable -Mode $Mode

                # Children with no children of their own don't need to be continued
                $children = $children | where { $_.Children.Count -gt 0 }
                $waitMode = "Continue"
            }
        }

        foreach($child in $children)
        {
            $Executor | RecurseInvokeRunner $child -Mode $Mode -WaitMode $waitMode
        }
    }
}

function InvokeWaitableChildren
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Waitable,

        [Parameter(Mandatory=$true)]
        $Mode
    )

    foreach($child in $Waitable)
    {
        $Executor | RecurseInvokeRunner $child -Mode $Mode -WaitMode Wait
    }

    $Waitable = @($Waitable | where { @($Executor.Results[$_].Values | where { !$_ }).Count -gt 0 })

    if($Waitable.Count -eq 0)
    {
        return
    }

    $str = if($Waitable.Count -eq 1) { "child" } else { "children" }

    $Executor.LogInfo("")
    $Executor.LogInfo("Waiting for $($Waitable.Count) asynchronous $str to complete...")
    $Executor.LogInfo("")

    $items = @()

    for($i = 0; $i -lt $Waitable.Count; $i++)
    {
        $child = $Waitable[$i]

        $waitAsync = $null

        if($child.HasMethod("WaitAsync"))
        {
            $waitAsync = @{
                Title = ""
                Stages = @{
                    Name = ""
                    Test = { $child.WaitAsync() }.GetNewClosure()
                }
            }
        }
        else
        {
            $waitAsync = $child.WaitAsync
        }        

        if(!$waitAsync.ContainsKey("Title"))
        {
            throw "Member 'WaitAsync' on component type '$child' does not implement property 'Title'"
        }

        if(!$waitAsync.ContainsKey("Stages"))
        {
            throw "Member 'WaitAsync' on component type '$($child.Type)' does not implement property 'Stages'"
        }

        $items += [PSCustomObject]@{
            Component = $child
            Index = $i
            Title = "$child $($waitAsync.Title)"
            $i = 0
            Stages = @(@($waitAsync.Stages) | foreach {

                if(!$_.ContainsKey("Name"))
                {
                    throw "Member 'WaitAsync -> Stage[$i]' on component type '$($child.Type)' does not implement property 'Name'"
                }

                if(!$_.ContainsKey("Test"))
                {
                    throw "Member 'WaitAsync -> Stage[$i]' on component type '$($child.Type)' does not implement property 'Test'"
                }

                ([PSCustomObject]$_) | Add-Member Completed $false -PassThru

                $i++
            })
            Completed = $false
        }
    }

    while($items|where Completed -eq $false)
    {
        foreach($item in $items)
        {
            $stage = ($item.Stages | where Completed -eq $false | select -first 1)

            $status = "Waiting for event '$($stage.Name)'"

            if([string]::IsNullOrEmpty($stage.Name))
            {
                $status = "Waiting for component to complete"
            }

            $progressArgs = @{
                Id = $item.Index
                Activity = $item.Title
                Status = $status
                PercentComplete = ([array]::IndexOf($item.Stages, $stage) + 1) / $item.Stages.Length * 100
            }

            if(!$stage)
            {
                if($item.Completed)
                {
                    continue
                }

                $progressArgs.Completed = $true
                $item.Completed = $true
            }

            Write-Progress @progressArgs

            if($stage)
            {
                $result = $stage.Test.InvokeWithContext($null, (New-Object PSVariable "this", $item.Component))

                if($result)
                {
                    $stage.Completed = $true
                }
            }
        }

        sleep 3
    }
}

function InvokeRunnerForEachChildren
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$true)]
        $Mode
    )

    $parent = $Node.Parent

    while($parent -ne $null)
    {
        $forEachChildren = $parent.Children | where { $_.ForEach -eq $Node.Type }

        if($forEachChildren)
        {
            if($Mode -eq "Reverse")
            {
                [array]::Reverse($forEachChildren)
            }

            foreach($child in $forEachChildren)
            {
                $Executor | RecurseInvokeRunner $child -Mode $Mode -InvokeType ForEach -WaitMode None
            }
        }

        $parent = $parent.Parent
    }
}

function RecurseInvokeRunner
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node,

        [Parameter(Mandatory=$true)]
        $Mode,

        [Parameter(Mandatory=$false)]
        [string]$InvokeType,

        [Parameter(Mandatory=$false)]
        [string]$WaitMode
    )

    switch($Mode)
    {
        "Apply" {
            $Executor | Invoke-ApplyRunner $Node -InvokeType $InvokeType -WaitMode $WaitMode
        }

        "Revert" {
            $Executor | Invoke-RevertRunner $Node -InvokeType $InvokeType
        }

        default {
            throw "Don't know how to invoke recurse runner for mode '$Mode'"
        }
    }
}

function InvokeRunnerEnd
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]
        $Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node
    )

    if($Node.HasMethod("End"))
    {
        $Node.End() | Out-Null
    }

    $Executor.DecrementLevel()
}

#endregion