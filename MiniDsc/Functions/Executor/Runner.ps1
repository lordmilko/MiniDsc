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
        [string]$InvokeType
    )

    $stepConfig = $Executor | InvokeRunnerInit $Node -InvokeType $InvokeType

    $Executor | InvokeRunnerDynamicSteps $Node -Mode Apply
    $Executor | InvokeRunnerNormalSteps $Node $stepConfig -Mode Apply
    $Executor | InvokeRunnerChildren $Node -Mode Apply

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

    $stepConfig = $Executor | InvokeRunnerInit $Node -InvokeType $InvokeType

    $Executor | InvokeRunnerChildren $Node -Mode Revert
    $Executor | InvokeRunnerNormalSteps $Node $stepConfig -Mode Revert
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
        [string]$InvokeType
    )

    if($InvokeType)
    {
        $InvokeType = "[$InvokeType]"
    }

    $Executor.LogLevel("$($InvokeType)Processing node '$Node'")
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

            $Executor | RecurseInvokeRunner $dynamicStep -Mode $Mode
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
        $Mode
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
                if($testResult -eq [Component]::IsPermanent)
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
        $children = @($Node.Children|where { !$_.ForEach })

        if($Mode -eq "Revert")
        {
            [array]::Reverse($children)
        }

        foreach($child in $children)
        {
            $Executor | RecurseInvokeRunner $child -Mode $Mode
        }
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
                $Executor | RecurseInvokeRunner $child -Mode $Mode -InvokeType ForEach
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
        [string]$InvokeType
    )

    switch($Mode)
    {
        "Apply" {
            $Executor | Invoke-ApplyRunner $Node -InvokeType $InvokeType
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