# Creates a copy of a DscComponentPrototype for use in constructing a new instance of that class or another prototype that extends the underlying one
function Copy-DscComponentPrototype
{
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [PSTypeName("ComponentPrototype")]
        $Prototype,

        [Parameter(Mandatory=$false)]
        [switch]$AsInstance
    )

    # All New-DscComponentPrototype really does is create a new Component and bind our desired
    # ScriptMethod members to it. Perfect! That's all we really need
    $newComponent = New-DscComponentPrototype $Prototype.Type

    foreach($property in $Prototype.PSObject.Properties)
    {
        if($property.MemberType -eq "NoteProperty")
        {
            $newComponent | Add-Member $property.Name $property.Value -Force
        }
    }

    foreach($method in $Prototype.PSObject.Methods|where { $_.Name -notlike "get_*" -and $_.Name -notlike "set-*" })
    {
        if($method.MemberType -eq "ScriptMethod")
        {
            $newComponent | Add-Member ScriptMethod $method.Name $method.Value.Script -Force
        }
    }

    foreach($typeName in $Prototype.PSObject.TypeNames)
    {
        if(!$newComponent.PSObject.TypeNames.Contains($typeName))
        {
            $newComponent.PSObject.TypeNames.Add($typeName)
        }
    }

    if ($AsInstance)
    {
        $newComponent.PSObject.TypeNames.Remove("ComponentPrototype") | Out-Null
        $newComponent.PSObject.TypeNames.Add("ComponentInstance")

        $base = $newComponent.PSObject.Properties["Base"]

        if($base)
        {
            foreach($method in $newComponent.Base.PSObject.Methods)
            {
                if($method.MemberType -eq "ScriptMethod")
                {
                    $newComponent.Base | Add-Member ScriptMethod $method.Name { $method.Script.InvokeWithContext($null, (New-Object PSVariable "this", $newComponent)) }.GetNewClosure() -Force
                }
            }
        }
    }

    return $newComponent
}