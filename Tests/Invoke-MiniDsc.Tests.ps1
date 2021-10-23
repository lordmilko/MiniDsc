. $PSScriptRoot\Support\Init.ps1

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

function MockInvokeDscResource($path = "C:\test.txt", $ensure = "Present")
{
    Mock "InvokeDscResource" {

        param($dscArgs)

        "Method","Property","Name","ModuleName" | foreach {
            if(!$dscArgs.ContainsKey($_))
            {
                throw "Did not have parameter '$_'"
            }
        }

        if($dscArgs.Method -eq "Test")
        {
            return [PSCustomObject]@{
                InDesiredState=$true
            }
        }

        foreach($key in $dscArgs.Keys)
        {
            $val = $dscArgs[$key]

            switch($key)
            {
                "Method" {
                    $val | Should Be Set
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
                                $propertyVal | Should Be $path
                            }

                            "Ensure" {
                                $propertyVal | Should Be $ensure
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
    }.GetNewClosure() -ModuleName MiniDsc -Verifiable
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
        "TestComponent","TestChildComponent" | foreach {
            [Component]::KnownComponents.Remove($_)
            Get-Item Function:\$_ -ErrorAction SilentlyContinue|Remove-Item
        }

        $Global:miniDscKnownDscModules = $null
        
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

        It "throws when WaitAsync is missing a title" {

            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync=@{}
            }

            $children = {
                TestChildComponent
            }

            Verify @{} -Children $children -Throws "Member 'WaitAsync' on component type 'TestChildComponent' does not implement property 'Title'"
        }

        It "throws when WaitAsync is missing stages" {
            
            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync=@{Title="Foo"}
            }

            $children = {
                TestChildComponent
            }

            Verify @{} -Children $children -Throws "Member 'WaitAsync' on component type 'TestChildComponent' does not implement property 'Stages'"
        }

        It "throws when a WaitAsync stage is missing a name" {
            
            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync=@{
                    Title="Foo"
                    Stages=@{}
                }
            }

            $children = {
                TestChildComponent
            }

            Verify @{} -Children $children -Throws "Member 'WaitAsync -> Stage[0]' on component type 'TestChildComponent' does not implement property 'Name'"
        }

        It "throws when a WaitAsync stage is missing a test" {

            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync=@{
                    Title="Foo"
                    Stages=@(
                        @{Name="Bar"; Test={}}
                        @{Name="Baz"}
                    )
                }
            }

            $children = {
                TestChildComponent
            }

            Verify @{} -Children $children -Throws "Member 'WaitAsync -> Stage[1]' on component type 'TestChildComponent' does not implement property 'Test'"
        }

        It "executes WaitAsync with a single stage" {

            $Global:testVal = 0

            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync=@{
                    Title="Foo"
                    Stages=@{
                        Name="Bar"
                        Test={
                            $Global:testVal++

                            if($Global:testVal -eq 2)
                            {
                                return $true
                            }
                            else
                            {
                                return $false
                            }
                        }
                    }
                }
            }

            $children = {
                TestChildComponent
            }

            Mock Start-Sleep {} -ModuleName "MiniDsc"

            Verify @{} -Children $children {
                $Global:testVal | Should Be 2
            }
        }

        It "executes WaitAsync with a ScriptBlock" {
            
            $Global:testVal = 0

            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync={
                    $Global:testVal++

                    if($Global:testVal -eq 2)
                    {
                        return $true
                    }
                    else
                    {
                        return $false
                    }
                }
            }

            $children = {
                TestChildComponent
            }

            Mock Start-Sleep {} -ModuleName "MiniDsc"

            Verify @{} -Children $children {
                $Global:testVal | Should Be 2
            }
        }

        It "doesn't execite WaitAsync when a step has already been applied" {
            Component TestChildComponent @{
                Name=$null

                Test={$this.Name -eq "first"}
                Apply={}

                WaitAsync={
                    if($this.Name -eq "first")
                    {
                        throw "Wait should not have been called for child 'first'"
                    }

                    $Global:testVal++

                    return $true
                }
            }

            $children = {
                TestChildComponent first
                TestChildComponent second
            }

            Verify @{} -Children $children {
                $Global:testVal | Should Be 1
            }
        }

        It "executes WaitAsync with a single stage in an array" {
            
            $Global:testVal = 0

            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync=@{
                    Title="Foo"
                    Stages=@(@{
                        Name="Bar"
                        Test={
                            $Global:testVal++

                            if($Global:testVal -eq 2)
                            {
                                return $true
                            }
                            else
                            {
                                return $false
                            }
                        }
                    })
                }
            }

            $children = {
                TestChildComponent
            }

            Mock Start-Sleep {} -ModuleName "MiniDsc"

            Verify @{} -Children $children {
                $Global:testVal | Should Be 2
            }
        }

        It "executes WaitAsync with multiple stages" {
            
            $Global:testVal = @{}

            Component TestChildComponent -CmdletType Empty @{
                Test={$false}
                Apply={}

                WaitAsync=@{
                    Title="Foo"
                    Stages=@(
                        @{
                            Name="Bar"
                            Test={
                                $Global:testVal.First++

                                if($Global:testVal.First -eq 2)
                                {
                                    return $true
                                }
                                else
                                {
                                    return $false
                                }
                            }
                        },

                        @{
                            Name="Baz"
                            Test={
                                $Global:testVal.Second++

                                if($Global:testVal.Second -eq 2)
                                {
                                    return $true
                                }
                                else
                                {
                                    return $false
                                }
                            }
                        }
                    )
                }
            }

            $children = {
                TestChildComponent
            }

            Mock Start-Sleep {} -ModuleName "MiniDsc"

            Verify @{} -Children $children {
                $Global:testVal.First | Should Be 2
                $Global:testVal.Second | Should Be 2
            }
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

    Context "DSC" {
        It "applies a DSC resource" {

            MockInvokeDscResource

            Mock "GetModule" {
                return $true
            } -ModuleName MiniDsc

            Component File -Module foo @{
                DestinationPath=0
                Contents=1
            }

            File "C:\test.txt" "bar" | Invoke-MiniDsc -Apply

            Assert-VerifiableMocks
        }

        It "reverts a DSC resource" {
            
            $path = Join-Path $TestDrive "text.txt"

            MockInvokeDscResource $path Absent

            Component File -Module foo @{
                DestinationPath=0
                Contents=1
            }

            New-Item $path -Force
            Set-Content $path "bar" -NoNewline

            File $path "bar" | Invoke-MiniDsc -Revert

            Assert-VerifiableMocks
        }

        It "installs a missing DSC module" {

            Mock "GetModule" {
                $false
            } -ModuleName MiniDsc -ParameterFilter { $name -eq "foo" } -Verifiable

            Mock "InstallPackage" {
                $name | Should Be foo
            } -ModuleName MiniDsc -Verifiable

            Mock "InvokeDscResource" {} -ModuleName MiniDsc

            Component File -Module foo @{
                DestinationPath=0
                Contents=1
            }

            File "C:\test.txt" "bar" | Invoke-MiniDsc -Apply

            Assert-VerifiableMocks
        }

        It "applies a DSC resource with optional parameters" {

            Component File -Dsc @{
                DestinationPath=0
                Contents=1

                Attributes=$null
            }

            Mock "InvokeDscResource" {
                $property = $dscArgs.Property

                $property.Count | Should Be 3

                "Contents","DestinationPath","Ensure" | foreach { $property.ContainsKey($_) | Should Be $true }

                $property.ContainsKey("Attributes") | Should Be $false
            } -ModuleName MiniDsc -Verifiable

            File "C:\test.txt" "bar" | Invoke-MiniDsc -Apply

            Assert-VerifiableMocks
        }
    }
}