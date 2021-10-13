ipmo $PSScriptRoot\..\MiniDsc -Force -DisableNameChecking

function Verify
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [Hashtable]$Body,

        [Parameter(Mandatory=$false)]
        [ScriptBlock]$Children,

        [Parameter(Mandatory=$true, Position=1, ParameterSetName="ScriptBlock")]
        [ScriptBlock]$Verifier,

        [Parameter(Mandatory=$true, ParameterSetName="Throws")]
        [string]$Throws
    )

    Component TestComponent -CmdletType Empty $Body

    switch($PSCmdlet.ParameterSetName)
    {
        "ScriptBlock" {
            TestComponent $Children | Invoke-MiniDsc -Apply

            & $Verifier
        }

        "Throws" {
            { TestComponent $Children | Invoke-MiniDsc -Apply } | Should Throw $Throws
        }

        default {
            throw "Don't know how to handle parameter set '$($PSCmdlet.ParameterSetName)'"
        }
    }
}

Describe "Invoke-MiniDsc" {
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
        
        Remove-Variable testVal -Scope Global -ErrorAction SilentlyContinue
    }

    It "invokes an Init method" {

        $body = @{
            Init={
                throw "Init was called"
            }
        }

        Verify $body -Throws "Init was called"
    }

    It "executes steps" {

        $Global:testVal = @()

        $body = @{
            Steps="First","Second"

            TestFirst={ $Global:testVal += "TestFirst" }
            TestSecond={ $Global:testVal += "TestSecond" }
            ApplyFirst={ $Global:testVal += "ApplyFirst" }
            ApplySecond={ $Global:testVal += "ApplySecond" }
        }

        Verify $body {
            $Global:testVal -join "," | Should Be "TestFirst,ApplyFirst,TestSecond,ApplySecond"
        }
    }

    It "throws when methods for each step aren't implemented" {

        $body = @{
            Steps="First","Second"
        }

        Verify $body -Throws "Cannot invoke method 'TestFirst' on value 'TestComponent': method does not exist"
    }

    It "executes dynamic steps" {
        
        $Global:testVal = @()

        Component TestChildComponent @{
            Name=$null

            Init={
                $Global:testVal += $this.Name
            }
        }

        $body = @{
            DynamicSteps={
                TestChildComponent "first"
                TestChildComponent "second"
            }
        }

        Verify $body {
            $Global:testVal -join "," | Should Be "first,second"
        }
    }

    It "executes an End method" {
        
        $body = @{
            End={
                throw "End was called"
            }
        }

        Verify $body -Throws "End was called"
    }

    It "verifies a parent" {
        
        Component TestChildComponent @{
            VerifyParent={
                param($parent)

                $parent.Type | Should Be TestComponent

                $Global:testVal = $true
            }
        }

        $children = {
            TestChildComponent foo
        }

        Verify @{} -Children $children {
            $Global:testVal | Should Be $true
        }
    }

    It "applies a config" {
        $body = @{
            First=$null
            Second=$null

            Init={
                $Global:testVal = "$($this.First),$($this.Second)"
            }
        }

        $children = {
            Config @{
                First="firstConfig"
                Second="secondConfig"
            }
        }

        Verify $body -Children $children {
            $Global:testVal | Should Be "firstConfig,secondConfig"
        }
    }

    It "verifies a config" {
        $body = @{
            First=$null

            Init={
                $Global:testVal = "$($this.First.Child1.Grandchild1),$($this.First.Child2)"
            }

            VerifyConfig=@(
                @{Path="First"; Children="Child1","Child2"}
                @{Path="First","Child1"; Children="Grandchild1"}
            )
        }

        $children = {
            Config @{
                First=@{
                    Child1=@{
                        Grandchild1="gc1"
                    }

                    Child2="c2"
                }
            }
        }

        Verify $body -Children $children {
            $Global:testVal | Should Be "gc1,c2"
        }
    }

    It "throws when a config is not valid" {
        $body = @{
            First=$null

            VerifyConfig=@(
                @{Path="First"; Children="Child1","Child2"}
                @{Path="First","Child1"; Children="Grandchild1"}
            )
        }

        $children = {
            Config @{
                First=@{
                    Child1=@{}

                    Child2="c2"
                }
            }
        }

        Verify $body -Children $children -Throws "Config at path 'First.Child1' did not contain mandatory member(s) 'Grandchild1'"
    }

    It "doesn't throw when an optional config value is not specified" {
        $body = @{
            First=$null

            VerifyConfig=@(
                @{Path="First"; Children="Child1","Child2"}
                @{Path="First","Child1"; Children="Grandchild1?"}
            )
        }

        $children = {
            Config @{
                First=@{
                    Child1=@{}

                    Child2="c2"
                }
            }
        }

        Verify $body -Children $children {}
    }

    Context "Apply" {
        It "applies a tree" {
            $tree = Folder $TestDrive {
                Folder foo
            }

            Test-Path $TestDrive | Should Be $true
            Test-Path $tree.Children[0].GetPath() | Should Be $false

            $tree | Invoke-MiniDsc -Apply

            Test-Path $tree.Children[0].GetPath() | Should Be $true
        }        
    }

    Context "Revert" {
        It "reverts a tree" {
            $tree = Folder $TestDrive {
                Folder foo
            }

            Test-Path $TestDrive | Should Be $true
            Test-Path $tree.Children[0].GetPath() | Should Be $false

            $tree | Invoke-MiniDsc -Apply

            Test-Path $tree.Children[0].GetPath() | Should Be $true

            $tree | Invoke-MiniDsc -Revert

            Test-Path $tree.Children[0].GetPath() | Should Be $false
        }   
    }
}