BeforeDiscovery {
    Set-Location -Path $PSScriptRoot
    $ModuleName = '$$var_ModuleName'

    $PathToManifest = [System.IO.Path]::Combine('..', '..', '..', 'src', $ModuleName, "$ModuleName.psd1")
    #if the module is already in memory, remove it
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force
}


InModuleScope '$$var_ModuleName' {
    Describe '$$var_FunctionName Function Tests' -Tag Unit {
        BeforeAll {

        }
        It '...' {

        }
    }
}