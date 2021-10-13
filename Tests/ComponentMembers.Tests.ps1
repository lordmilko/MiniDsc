ipmo $PSScriptRoot\..\MiniDsc -Force -DisableNameChecking

Describe "ComponentMembers" {
    BeforeAll {
        $originalDefaultParameterValues = $global:PSDefaultParameterValues.Clone()

        $global:PSDefaultParameterValues["Invoke-MiniDsc:Quiet"] = $true
    }

    AfterAll {
        $Global:PSDefaultParameterValues = $originalDefaultParameterValues
    }

    BeforeEach {
        [Component]::KnownComponents.Remove("TestComponent")
        [Component]::KnownComponents.Remove("TestChildComponent")
        [Component]::KnownComponents.Remove("TestExtendedComponent")
        
        Remove-Variable testVal -Scope Global -ErrorAction SilentlyContinue
    }

    It "gets the parent of a component" {
        
        Component TestComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent
        }

        $tree.Children[0].Parent.Type | Should Be Root
    }

    It "gets the children of a component" {
        
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

    It "gets the parent of a specified type" {

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

    It "gets children of a specified type" {

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

    It "throws when a parent of a specified type does not exist" {
        
        Component TestComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent
        }

        $child = $tree.Children[0]
        $child.Type | Should Be TestComponent

        { $child.GetParent("foo") } | Should Throw "Could not find parent of type 'foo'"
    }

    It "throws when a child of a specified type does not exist" {
        
        Component TestComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent
        }

        $tree.Type | Should Be Root

        { $tree.GetChildren("foo") } | Should Throw "Could not find any children of type 'foo'"
    }

    It "finds a node of a specified type in the tree" {

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

    It "throws when a node of a specified type cannot be found in the tree" {
        
        Component TestComponent -CmdletType Empty  @{}
        Component TestChildComponent -CmdletType Empty  @{}

        $tree = Root {
            TestComponent {
                TestChildComponent
            }
        }

        { $tree.Find("foo") } | Should Throw "Could not find a component of type 'foo' in the tree."
    }

    It "gets the last node of a specified type that was executed before this node" {
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

    It "indicates whether a method is present via HasMethod" {

        Component TestComponent -CmdletType Empty @{
            Init={}
        }

        $tree = TestComponent
        $tree.HasMethod("Init") | Should Be $true
        $tree.HasMethod("End") | Should Be $false
    }

    It "indicates whether a property is present via HasProperty" {
        
        Component TestComponent -CmdletType Empty @{
            Name=$null
        }

        $tree = TestComponent
        $tree.HasProperty("Name") | Should Be $true
        $tree.HasProperty("Foo") | Should Be $false
    }

    It "automatically overrides ToString when a Name property is present" {
        
        Component TestComponent @{
            Name=$null
        }

        $tree = TestComponent foo

        $tree.ToString() | Should Be "[TestComponent] foo"
    }

    It "overrides ToString with a custom method override" {
        
        Component TestComponent @{
            Name=$null

            ToString={
                "custom"
            }
        }

        $tree = TestComponent foo

        $tree.ToString() | Should Be custom
    }

    It "returns the component's type when a suitable ToString override is not found" {
        
        Component TestComponent -CmdletType Empty @{}

        $tree = TestComponent

        $tree.ToString() | Should Be TestComponent
    }

    It "stores values in Vars" {
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
}