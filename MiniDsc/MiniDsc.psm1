$files = "Functions","Components" | foreach { gci (Join-Path $PSScriptRoot $_) -Recurse -File }

foreach($file in $files)
{
    . $file.FullName -Force
}

Component Root -CmdletType Empty @{}

enum CmdletType
{
    None        # Don't generate a cmdlet
    Empty       # Cmdlet takes a ScriptBlock
    Name        # Cmdlet takes a name and a ScriptBlock
    Config      # Cmdlet takes a hashtable
    NamedConfig # Cmdlet takes a name and a hashtable
    Value       # Cmdlet takes a value
}

function Assert-HasMethod
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $Node,

        [Parameter(Mandatory=$true, Position=0)]
        $Name,

        [Parameter(Mandatory=$false)]
        $Extra
    )

    if(!$Node.HasMethod($Name))
    {
        throw "Cannot invoke method '$Name' on value '$Node': method does not exist.$Extra"
    }
}

function Assert-NotHasMethod
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $Node,

        [Parameter(Mandatory=$true, Position=0)]
        $Name,

        [Parameter(Mandatory=$false)]
        $Extra
    )

    if($Node.HasMethod($Name))
    {
        throw "Expected value '$Node' to not have a '$Name' method: $Extra"
    }
}