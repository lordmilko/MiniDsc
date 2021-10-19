. $PSScriptRoot\Support\Init.ps1

# Tests complex extension methods that are defined on the component prototype or methods that are able to execute
# independently of Invoke-MiniDsc

Describe "ComponentExtensions" {
    BeforeAll {
        $originalDefaultParameterValues = $global:PSDefaultParameterValues.Clone()

        $global:PSDefaultParameterValues["Invoke-MiniDsc:Quiet"] = $true
    }

    AfterAll {
        $Global:PSDefaultParameterValues = $originalDefaultParameterValues
    }

    BeforeEach {
        "TestComponent","TestChildComponent","TestGrandChildComponent","TestExtendedComponent" | foreach {
            [Component]::KnownComponents.Remove($_)
            Get-Item Function:\$_ -ErrorAction SilentlyContinue|Remove-Item
        }
        
        Remove-Variable testVal -Scope Global -ErrorAction SilentlyContinue
    }

    It "Parent: gets the parent of a component" {
        
        Component TestComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent
        }

        $tree.Children[0].Parent.Type | Should Be Root
    }

    It "Children: gets the children of a component" {
        
        Component TestComponent @{
            Name=$null
        }

        $tree = Root {
            TestComponent first
            TestComponent second
        }

        $tree.Children.Count | Should Be 2
        $tree.Children[0].Name | Should Be first
        $tree.Children[1].Name | Should Be second
    }

    It "GetParent(`$type): gets the parent of a specified type" {

        Component TestComponent -CmdletType Empty  @{}
        Component TestChildComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent {
                TestChildComponent
            }
        }

        $grandChild = $tree.Children[0].Children[0]
        $grandChild.Type | Should Be TestChildComponent

        $parent = $grandChild.GetParent("TestComponent")
        $parent.Type | Should Be TestComponent

        $grandParent = $grandChild.GetParent("Root")
        $grandParent.Type | Should Be Root
    }

    It "VerifyParent(`$parent): gets the grandparent of a specified type" {

        Component TestComponent -CmdletType Empty @{}
        Component TestChildComponent -CmdletType Empty @{}

        Component TestGrandChildComponent -CmdletType Empty @{
            VerifyParent={
                param($parent)

                $parent = $this.GetParent("TestComponent")

                $Global:testVal = $parent
            }
        }

        $tree = TestComponent {
            TestChildComponent {
                TestGrandChildComponent
            }
        }

        $Global:testVal | Should Be $tree
    }

    It "GetChildren(`$type): gets children of a specified type" {

        Component TestComponent  @{
            Name=$null
        }

        Component TestChildComponent @{
            Name=$null
        }

        $tree = Root {
            TestComponent first

            TestComponent second
        }

        $child = $tree.GetChildren("TestComponent")

        $child.Count | Should Be 2
        $child[0].Name | Should Be first
        $child[1].Name | Should Be second
    }

    It "GetParent(`$type): throws when a parent of a specified type does not exist" {
        
        Component TestComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent
        }

        $child = $tree.Children[0]
        $child.Type | Should Be TestComponent

        { $child.GetParent("foo") } | Should Throw "Could not find parent of type 'foo'"
    }

    It "GetChildren(`$type): throws when a child of a specified type does not exist" {
        
        Component TestComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent
        }

        $tree.Type | Should Be Root

        { $tree.GetChildren("foo") } | Should Throw "Could not find any children of type 'foo'"
    }

    It "Find(`$type): finds a node of a specified type in the tree" {

        Component TestComponent -CmdletType Empty  @{}
        Component TestChildComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent {
                TestChildComponent
            }
        }

        $result = $tree.Find("TestChildComponent")

        $result.Type | Should Be TestChildComponent
    }

    It "Find(`$type): throws when a node of a specified type cannot be found in the tree" {
        
        Component TestComponent -CmdletType Empty  @{}
        Component TestChildComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent {
                TestChildComponent
            }
        }

        { $tree.Find("foo") } | Should Throw "Could not find a component of type 'foo' in the tree."
    }

    It "GetLast(`$type): gets the last node of a specified type that was executed before this node" {
        $Global:testVal = @()

        Component TestComponent -CmdletType Empty @{
            Init={
                $last = $this.GetLast("TestChildComponent")

                $Global:testVal += $last.Name
            }
        }

        Component TestChildComponent @{
            Name=$null
        }

        $tree = Root {
            TestChildComponent first
            TestChildComponent second

            TestComponent -ForEach TestChildComponent
        }

        $tree | Invoke-MiniDsc -Apply

        $Global:testVal -join "," | Should Be "first,second"
    }

    It "HasMethod(): indicates whether a method is present via HasMethod" {

        Component TestComponent -CmdletType Empty @{
            Init={}
        }

        $tree = TestComponent
        $tree.HasMethod("Init") | Should Be $true
        $tree.HasMethod("End") | Should Be $false
    }

    It "HasProperty(): indicates whether a property is present via HasProperty" {
        
        Component TestComponent -CmdletType Empty @{
            Name=$null
        }

        $tree = TestComponent
        $tree.HasProperty("Name") | Should Be $true
        $tree.HasProperty("Foo") | Should Be $false
    }

    It "ToString(): automatically overrides ToString when a Name property is present" {
        
        Component TestComponent @{
            Name=$null
        }

        $tree = TestComponent foo

        $tree.ToString() | Should Be "[TestComponent] foo"
    }

    It "ToString(): overrides ToString with a custom method override" {
        
        Component TestComponent @{
            Name=$null

            ToString={
                "custom"
            }
        }

        $tree = TestComponent foo

        $tree.ToString() | Should Be custom
    }

    It "ToString(): returns the component's type when a suitable ToString override is not found" {
        
        Component TestComponent -CmdletType Empty @{}

        $tree = TestComponent

        $tree.ToString() | Should Be TestComponent
    }

    It "VerifyParent(`$parent): verifies a parent" {
        
        Component TestComponent -CmdletType Empty @{}

        Component TestChildComponent -CmdletType Empty @{
            VerifyParent={
                param($parent)

                $parent.Type | Should Be TestComponent

                $Global:testVal = $true
            }
        }

        $tree = TestComponent {
            TestChildComponent
        }

        $Global:testVal | Should Be $true
    }

    It "Verify(): verifies a components state" {

        Component TestComponent -CmdletType Empty @{
            Verify={
                $Global:testVal = "verifySuccess"
            }
        }

        $tree = TestComponent

        $Global:testVal | Should Be verifySuccess
    }

    It "Vars: stores values in Vars" {
        Component TestComponent -CmdletType Empty @{
            Init={
                $this.Vars.Foo = "bar"
            }

            End={
                $Global:testVal = $this.Vars.Foo
            }
        }

        $tree = TestComponent

        $tree | Invoke-MiniDsc -Apply

        $Global:testVal | Should Be bar
    }

    It "Base: calls a base method" {
        $Global:testVal = @()

        Component TestComponent -CmdletType Empty @{
            Init={
                $Global:testVal += "base"
            }
        }

        Component TestExtendedComponent -Extends TestComponent -CmdletType Empty @{
            Init={
                $Global:testVal += "derived"

                $this.Base.Init()
            }
        }

        TestExtendedComponent | Invoke-MiniDsc -Apply

        $Global:testVal -join "," | Should Be "derived,base"
    }
}