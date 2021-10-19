. $PSScriptRoot\Support\Init.ps1

Describe "ComponentDef" {
    BeforeAll {
        $originalDefaultParameterValues = $global:PSDefaultParameterValues.Clone()

        $global:PSDefaultParameterValues["Invoke-MiniDsc:Quiet"] = $true
    }

    AfterAll {
        $Global:PSDefaultParameterValues = $originalDefaultParameterValues
    }

    BeforeEach {
        "TestComponent","TestChildComponent","TestExtendedComponent","File" | foreach {
            [Component]::KnownComponents.Remove($_)
            Get-Item Function:\$_ -ErrorAction SilentlyContinue|Remove-Item
        }
        
        Remove-Variable testVal -Scope Global -ErrorAction SilentlyContinue
    }

    AfterEach {
        gci $TestDrive | Remove-Item -Recurse -Force
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

    It "implements a ScriptProperty via a simple assignment" {

        Component TestComponent @{
            Name=$null
        }

        Component TestChildComponent -CmdletType Value @{
            Value=$null
        }

        $tree = TestComponent foo {
            TestChildComponent { $this.GetParent("TestComponent").Name }
        }

        $tree.Name | Should Be foo
        $tree.Children[0].Value | Should Be foo
    }

    It "implements a ScriptProperty via a Config block" {

        Component TestComponent @{
            Name=$null
        }

        Component TestChildComponent -CmdletType Empty @{
            Value=$null
        }

        $tree = TestComponent bar {
            TestChildComponent {
                Config @{
                    Value={ $this.GetParent("TestComponent").Name }
                }
            }
        }

        $tree.Name | Should Be bar
        $tree.Children[0].Value | Should Be bar
    }

    Context "Dsc" {
        It "defines a DSC resource with a -Name" {

            Component File -Dsc @{
                DestinationPath=0
                Contents=1
            }

            $path = Join-Path $TestDrive "foo.txt"

            File $path "Test1" | Invoke-MiniDsc -Apply

            gc $path | Should Be Test1
        }

        It "defines a DSC resource with a -Name and a -DscName" {
            Component DscFile -DscName File -Dsc @{
                DestinationPath=0
                Contents=1
            }

            $path = Join-Path $TestDrive "foo.txt"

            { File $path Test2 } | Should Throw "The term 'File' is not recognized as the name of a cmdlet"

            DscFile $path "Test2" | Invoke-MiniDsc -Apply

            gc $path | Should Be Test2
        }

        It "doesn't generate positional parameters when parameter values are null" {

            Component File -Dsc @{
                DestinationPath=$null
                Contents=$null
            }

            $path = Join-Path $TestDrive "foo.txt"

            { File $path "Test4" } | Should Throw "Cannot process argument transformation on parameter 'ScriptBlock'"

            File -DestinationPath $path -Contents "Test4" | Invoke-MiniDsc -Apply

            gc $path | Should Be Test4
        }

        It "doesn't generate positional parameters when parameter values are strings" {

            Component File -Dsc @{
                DestinationPath=0
                Contents="1"
            }

            $path = Join-Path $TestDrive "foo.txt"

            { File $path "Test5" } | Should Throw "Cannot process argument transformation on parameter 'ScriptBlock'"

            File $path -Contents "Test5" | Invoke-MiniDsc -Apply

            gc $path | Should Be Test5
        }

        It "ignores ScriptBlock parameters" {
            Component File -Dsc @{
                DestinationPath=0
                Contents=1

                VerifyParent={}
            }

            $path = Join-Path $TestDrive "foo.txt"

            File $path "Test6" | Invoke-MiniDsc -Apply

            gc $path | Should Be Test6
        }

        It "defines a DSC resource with a -Module" {        

            Mock "GetModule" {
                $true
            } -ModuleName MiniDsc -ParameterFilter { $name -eq "foo" } -Verifiable

            Mock "InvokeDscResource" {

                "Method","Property","Name","ModuleName" | foreach {
                    if(!$dscArgs.ContainsKey($_))
                    {
                        throw "Did not have parameter '$_'"
                    }
                }

                if($dscArgs.Method -eq "Set")
                {
                    return
                }

                foreach($key in $dscArgs.Keys)
                {
                    $val = $dscArgs[$key]

                    switch($key)
                    {
                        "Method" {
                            $val | Should Be Test
                        }

                        "Property" {
                            "Contents","DestinationPath","Ensure" | foreach {

                                if(!$val.ContainsKey($_))
                                {
                                    throw "Did not have property '$_'"
                                }
                            }

                            foreach($propertyKey in $val.Keys)
                            {
                                $propertyVal = $val[$propertyKey]

                                switch($propertyKey)
                                {
                                    "Contents" {
                                        $propertyVal | Should Be bar
                                    }

                                    "DestinationPath" {
                                        $propertyVal | Should Be "C:\test.txt"
                                    }

                                    "Ensure" {
                                        $propertyVal | Should Be Present
                                    }

                                   default {
                                        throw "Don't know how to handle property '$key'"
                                    } 
                                }
                            }
                        }

                        "Name" {
                            $val | Should Be File
                        }

                        "ModuleName" {
                            $val | Should Be foo
                        }

                        default {
                            throw "Don't know how to handle parameter '$key'"
                        }
                    }
                }
            } -ModuleName MiniDsc -Verifiable

            Component File -Module foo @{
                DestinationPath=0
                Contents=1
            }

            File "C:\test.txt" "bar" | Invoke-MiniDsc -Apply

            Assert-VerifiableMocks
        }
    }
}