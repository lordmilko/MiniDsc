function Get-DscComponentMember
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        $Name
    )

    $members = @(
        @{Name="Apply"; Type="ScriptBlock"; Description="Applies the configuration described in component."}
        @{Name="Revert"; Type="ScriptBlock"; Description="Reverts the configuration described in the component."}
        @{Name="Test"; Type="ScriptBlock"; Description="Tests whether the component has already been applied."}
        @{Name="Init"; Type="ScriptBlock"; Description="Performs an initialization function when the component begins executing."}
        @{Name="End"; Type="ScriptBlock"; Description="Performs a finalization function when the component ends executing."}
        @{Name="Verify"; Type="ScriptBlock"; Description="Verifies that the values specified to a component are valid immediately after the component has been created"}
        @{Name="VerifyParent"; Type="ScriptBlock"; Description="Verifies that the specified parent is valid for this node. Takes the `$parent component as an argument."}
        @{Name="VerifyConfig"; Type="Hashtable[]"; Description="Validates a complex Hashtable configuration against the required specification."}
        @{Name="Steps"; Type="string[]"; Description="Specifies the multiple step names that are required to execute this component. Test/Apply/Revert methods can then be split into separate methods for each individual step."}
        @{Name="DynamicSteps"; Type="ScriptBlock"; Description="Specifies a set of dynamic child components that should be evaluated for this node prior to evaluating its specified Steps or itself."}
        @{Name="Vars"; Type="Hashtable"; Description="Provides a scratch storage space for component methods to store variables within a component invocation."}
        @{Name="Base"; Type="Component"; Description="Provides access to the methods of the base component when one component -Extends another one."}
    )

    $results = $members | foreach { [PSCustomObject]$_|select Name,Type,Description }

    if($Name)
    {
        $results = $results | where Name -Like $Name
    }

    $results
}