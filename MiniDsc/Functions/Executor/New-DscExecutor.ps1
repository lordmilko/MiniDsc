function New-DscExecutor
{
    $executor = New-Object PSObject
    $executor.PSObject.TypeNames.Add("Executor")

    $executor | Add-Member LastOfType @{}
    $executor | Add-Member Level 0
    $executor | Add-Member Quiet $false
    $executor | Add-Member ScriptMethod IncrementLevel { $this.Level++ }
    $executor | Add-Member ScriptMethod DecrementLevel { $this.Level-- }
    $executor | Add-Member ScriptMethod LogLevel       { param($message) $this.Log($message, "Magenta") }
    $executor | Add-Member ScriptMethod LogSuccess     { param($message) $this.Log($message, "Green") }
    $executor | Add-Member ScriptMethod LogWarning     { param($message) $this.Log($message, "Yellow") }
    $executor | Add-Member ScriptMethod LogInfo        { param($message) $this.Log($message, "Cyan") }
    $executor | Add-Member ScriptMethod LogQuiet       { param($message) $this.Log($message, "Gray") }
    $executor | Add-Member ScriptMethod Log {
        param($message, $color)

        if($this.Quiet)
        {
            return
        }

        $indent = "    " * $this.Level

        Write-Host "$($indent)$message" -ForegroundColor $color
    }
    $executor | Add-Member ScriptMethod GetLast {
        param($type)

        if($this.LastOfType.ContainsKey($type))
        {
            return $this.LastOfType.$type
        }

        throw "Cannot get last '$type': a component of this type has never been processed"
    }

    return $executor
}