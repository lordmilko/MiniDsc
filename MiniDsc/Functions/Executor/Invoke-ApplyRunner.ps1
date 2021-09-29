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
        [string]$ApplyType
    )

    if($ApplyType)
    {
        $ApplyType = "[$ApplyType]"
    }

    $Executor.LogLevel("$($ApplyType)Processing node '$Node'")
    $Executor.LastOfType.$($Node.Type) = $Node
    $Executor.IncrementLevel()

    if($Node.HasMethod("Init"))
    {
        $Node.Init()
    }

    $steps = @($null)
    $largestLength = $null

    if($Node.HasProperty("Steps"))
    {
        $steps = @($Node.Steps)
        $largestLength = $steps|foreach {$_.Length}|sort -Descending|select -first 1
    }

    foreach($step in $steps)
    {
        $prefix = $null
        $testMessage = $null
        $applyMessage = $null
        $alreadyAppliedMessage=$null

        if($step -ne $null)
        {
            $Node | Assert-HasMethod "Test$step" -Extra " Tests for all actions specified in 'Steps' must be defined."

            $reason = " Specific step methods must be defined when 'Steps' is defined (i.e. TestFoo, ApplyFoo, RevertFoo)."

            $Node | Assert-NotHasMethod "Test" -Extra $reason
            $Node | Assert-NotHasMethod "Apply" -Extra $reason
            $Node | Assert-NotHasMethod "Revert" -Extra $reason

            $prefix = "$($step.PadRight($largestLength)) : "
            $applyMessage = "$($prefix)Applying step"
            $alreadyAppliedMessage = "$($prefix)Step has already been applied"
        }
        else
        {
            $applyMessage = "Applying node '$node'"
            $alreadyAppliedMessage = "Node '$Node' has already been applied"
        }

        if($Node.HasMethod("Test$step"))
        {
            $test = $node."Test$step"()

            if(!$test)
            {
                $Executor.LogSuccess($applyMessage)

                $Node | Assert-HasMethod "Apply$step"

                try
                {
                    $Node."Apply$($step)"() | Out-Null
                }
                catch
                {
                    throw $_.Exception.InnerException
                }
            }
            else
            {
                $Executor.LogWarning($alreadyAppliedMessage)
            }
        }
        else
        {
            $Executor.LogQuiet("No 'Test' method found on container '$Node' with $($Node.Children.Count) children")
        }
    }

    $Executor | Invoke-ChildApplyRunner $Node

    if($Node.HasMethod("End"))
    {
        $Node.End()
    }

    $Executor.DecrementLevel()
}