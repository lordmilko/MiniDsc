function Register-MiniDscFunction
{
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [Hashtable[]]$Parameters,

        [Parameter(Mandatory = $false)]
        [string]$Body
    )

    $Parameters += @{Name="ForEach"; Type="string"; Mandatory=$false}

    $builder = New-Object System.Text.StringBuilder

    $builder.Append("function global:").AppendLine($Name) | Out-Null
    $builder.AppendLine("{")                              | Out-Null
    $builder.AppendLine("    [CmdletBinding()]")          | Out-Null
    $builder.AppendLine("    param(")                     | Out-Null

    $defaultParameters = @()

    for($i = 0; $i -lt $Parameters.Count; $i++)
    {
        $parameter = $Parameters[$i]

        $mandatory = $parameter.Mandatory.ToString().ToLower()
        $name = $parameter.Name
        $type = $parameter.Type

        $builder.Append("        [Parameter(Mandatory = `$$mandatory") | Out-Null

        if($parameter.ContainsKey("Position"))
        {
            $position = $parameter.Position

            $builder.Append(", Position = $position") | Out-Null
        }

        $builder.AppendLine(")]") | Out-Null

        if($parameter.ContainsKey("Attributes"))
        {
            foreach($attribute in @($parameter.Attributes))
            {
                $builder.Append("        ").AppendLine($attribute) | Out-Null
            }
        }

        $builder.Append("        [$type]`$$name") | Out-Null

        if($parameter.ContainsKey("Default"))
        {
            $defaultParameters += $name
            $builder.Append(" = '$($parameter.Default)'") | Out-Null
        }

        if($i -lt $Parameters.Count - 1)
        {
            $builder.AppendLine(",") | Out-Null
        }

        $builder.AppendLine() | Out-Null
    }

    $builder.AppendLine("    )") | Out-Null
    $builder.AppendLine() | Out-Null

    foreach($defaultParameter in $defaultParameters)
    {
        # If a default parameter isn't overridden by the user, its default value won't be included in the bound parameters; force re-add all of these values
        $builder.AppendLine("    `$PSCmdlet.MyInvocation.BoundParameters['$defaultParameter'] = `$$defaultParameter") | Out-Null
    }

    if($Body)
    {
        $lines = $Body.Split(@("`n", "`r"), [System.StringSplitOptions]::RemoveEmptyEntries)

        foreach($line in $lines)
        {
            $builder.Append("    ").AppendLine($line) | Out-Null
        }

        $builder.AppendLine() | Out-Null
    }

    $builder.AppendLine("    New-DscComponentInstance `$PSCmdlet") | Out-Null

    $builder.Append("}") | Out-Null

    $str = $builder.ToString()

    Invoke-Expression $str
}