Remove-Module MiniDsc -ErrorAction SilentlyContinue # Mocks don't work when you reimport the module
ipmo $PSScriptRoot\..\..\MiniDsc -Force -DisableNameChecking