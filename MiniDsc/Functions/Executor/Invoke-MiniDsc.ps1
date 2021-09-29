function invoke-MiniDsc
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
        [switch]$Revert
    )

    $executor = New-DscExecutor

    $global:currentExecutor = $executor

    try
    {
        switch ($PSCmdlet.ParameterSetName) {
            "Test" {
                throw "Test is not currently supported"
            }

            "Apply" {
                $executor | Invoke-ApplyRunner $Root
            }

            "Revoke" {
                throw "Revoke is not currently supported"
            }
        }

        
    }
    finally
    {
        $global:currentExecutor = $null
    }
}