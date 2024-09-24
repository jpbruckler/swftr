BeforeDiscovery {
    Set-Location -Path $PSScriptRoot
    $PathToManifest = [System.IO.Path]::Combine('..', '..', '..', 'src', $ModuleName, "$ModuleName.psd1")
    #if the module is already in memory, remove it
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force
    Import-Module $PathToManifest -Force
}


InModuleScope 'swftr' {
    Describe 'New-SwftrTaskInfo Function Tests' -Tag Unit {
        BeforeAll {

            $sbWithParams = @"
<#
.OUTPUTS
    Greeting
#>
param(
    [Parameter(Mandatory)]
    [string]`$Name,
    [Parameter(Mandatory = `$false)]
    [string] `$Salutation
)
if (`$Salutation) {
    Write-Output "`$Salutation, `$Name!"
}
else {
    Write-Output "Hello, `$Name!"
}
"@
            $sbNoParams = @"
Get-Process
"@

            $sbBadSyntax = @"
return @{ Name: "Tim" }
"@
            $sbWithParams | Set-Content -Path (Join-Path $TestDrive 'valid-sb-params.ps1') #"TestDrive:\valid-sb-params.ps1"
            $sbNoParams   | Set-Content -Path (Join-Path $TestDrive 'valid-sb-noparams.ps1')
            $sbBadSyntax  | Set-Content -Path (Join-Path $TestDrive 'invalid-sb.ps1')
        }

        Context 'Path parameter set' {
            It 'Creates a TaskInfo object from a path' {
                $ti = New-SwftrTaskInfo -Path (Join-Path $TestDrive 'valid-sb-params.ps1')
                $ti.TaskName | Should -BeExactly 'valid-sb-params'
                $ti.Outputs  | Should -Be 'Greeting'

                $ti.Parameters.Count | Should -BeExactly 2
                $ti.Parameters[0].ParameterName | Should -Be 'Name'
                $ti.Parameters[0].Type | Should -Be 'String'
                $ti.Parameters[0].IsMandatory | Should -Be $true

                $ti.Parameters[1].ParameterName | Should -Be 'Salutation'
                $ti.Parameters[1].Type | Should -Be 'String'
                $ti.Parameters[1].IsMandatory | Should -Be $false
            }

            It 'Outputs an error when a nonexistent Path is given' {
                New-SwftrTaskInfo -Path c:\thisdoesntexist.ps1 -ErrorVariable err -ErrorAction SilentlyContinue
                $err.Exception.Message | Should -Be "Unable to create TaskInfo from c:\thisdoesntexist.ps1"
            }

            It 'Outputs an error when an invalid script file is given' {
                New-SwftrTaskInfo -Path (Join-Path $TestDrive 'invalid-sb.ps1') -ErrorVariable err -ErrorAction SilentlyContinue
                $err.Exception[0] | Should -BeOfType System.Management.Automation.RuntimeException
            }
        }

        Context 'Scriptblock parameter set' {
            BeforeAll {
                $sbWithParams = [scriptblock]::Create(@"
<#
.OUTPUTS
    Greeting
#>
param(
    [Parameter(Mandatory)]
    [string]`$Name,
    [Parameter(Mandatory = `$false)]
    [string] `$Salutation
)
if (`$Salutation) {
    Write-Output "`$Salutation, `$Name!"
}
else {
    Write-Output "Hello, `$Name!"
}
"@)
            }
            It 'Creates a TaskInfo objectg from a scriptblock' {
                $ti = New-SwftrTaskInfo -TaskName 'valid-sb-params' -Scriptblock $sbWithParams
                $ti.TaskName | Should -BeExactly 'valid-sb-params'
                $ti.Outputs  | Should -Be 'Greeting'

                $ti.Parameters.Count | Should -BeExactly 2
                $ti.Parameters[0].ParameterName | Should -Be 'Name'
                $ti.Parameters[0].Type | Should -Be 'String'
                $ti.Parameters[0].IsMandatory | Should -Be $true

                $ti.Parameters[1].ParameterName | Should -Be 'Salutation'
                $ti.Parameters[1].Type | Should -Be 'String'
                $ti.Parameters[1].IsMandatory | Should -Be $false
            }
        }
    }
}