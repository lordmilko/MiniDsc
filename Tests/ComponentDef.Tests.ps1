ipmo $PSScriptRoot\..\MiniDsc -Force -DisableNameChecking

Describe "ComponentDef" {
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

    It "extends a component" {
        $Global:testVal = @()

        Component TestComponent -CmdletType Empty @{
            Init={
                $Global:testVal += "originalInit"
            }

            End={
                $Global:testVal += "originalEnd"
            }
        }

        TestComponent | Invoke-MiniDsc -Apply
        $Global:testVal -join "," | Should Be "originalInit,originalEnd"

        $Global:testVal = @()

        Component TestExtendedComponent -Extends TestComponent -CmdletType Empty @{
            Init={
                $Global:testVal += "extendedInit"
            }
        }

        TestExtendedComponent | Invoke-MiniDsc -Apply
        $Global:testVal -join "," | Should Be "extendedInit,originalEnd"
    }

    It "executes ForEach" {
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
}