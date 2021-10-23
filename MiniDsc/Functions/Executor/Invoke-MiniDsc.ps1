function Invoke-MiniDsc
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Component]$Root,

        [Parameter(Mandatory=$true, ParameterSetName="Test")]
        [switch]$Test,

        [Parameter(Mandatory=$true, ParameterSetName="Apply")]
        [switch]$Apply,

        [Parameter(Mandatory=$true, ParameterSetName="Revert")]
        [switch]$Revert,

        [Parameter(Mandatory=$false)]
        [switch]$Quiet
    )

    $executor = New-DscExecutor
    $executor.Quiet = $Quiet

    $global:currentExecutor = $executor

    try
    {
        switch ($PSCmdlet.ParameterSetName) {
            "Test" {
                throw "Test is not currently supported"
            }

            "Apply" {
                $executor | Invoke-ApplyRunner $Root -WaitMode None
            }

            "Revert" {
                $executor | Invoke-RevertRunner $Root
            }

            default {
                throw "Don't know how to handle parameter set '$($PSCmdlet.ParameterSetName)'"
            }
        }

        
    }
    finally
    {
        $global:currentExecutor = $null
    }
}