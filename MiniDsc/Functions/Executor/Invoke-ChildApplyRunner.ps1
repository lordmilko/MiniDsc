function Invoke-ChildApplyRunner
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSTypeName("Executor")]$Executor,

        [Parameter(Mandatory=$true, Position=0)]
        $Node
    )

    if($Node.Children)
    {
        foreach($child in @($Node.Children|where { !$_.ForEach }))
        {
            $Executor | Invoke-ApplyRunner $child
        }
    }

    $parent = $node.Parent

    while($parent -ne $null)
    {
        $forEachChildren = $parent.Children | where { $_.ForEach -eq $Node.Type }

        if($forEachChildren)
        {
            foreach($child in $forEachChildren)
            {
                $Executor | Invoke-ApplyRunner $child -ApplyType ForEach
            }
        }

        $parent = $parent.Parent
    }
}