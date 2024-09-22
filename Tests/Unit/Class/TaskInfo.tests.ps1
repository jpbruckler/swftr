
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
param()

Describe 'TaskInfo Class Tests' {
    BeforeAll {
        Set-Location -Path $PSScriptRoot
        $ModuleName = 'swftr'
        $ClassesPath = [System.IO.Path]::Combine('..', '..', '..', 'src', $ModuleName, 'Classes')

        # Import the class definitions
        . "$ClassesPath\TaskInfo.class.ps1"
    }


    Context 'Method Tests' {
        It 'Should parse parameters and outputs from scriptblock using ParseScriptblock' {
            $scriptBlock = {
                <#
    .OUTPUTS
    ResultData
#>
                param(
                    [Parameter(Mandatory)]
                    [string]$InputData
                )
                # Script content
            }

            $taskName = 'TestTask'
            $taskInfo = [TaskInfo]::ParseScriptblock($taskName, $scriptBlock)

            $taskInfo.TaskName | Should -Be $taskName
            $taskInfo.Parameters.Count | Should -Be 1
            $taskInfo.Outputs.Count | Should -Be 1

            # Verify parameter
            $param = $taskInfo.Parameters[0]
            $param.ParameterName | Should -Be 'InputData'
            $param.Type | Should -Be 'String'
            $param.IsMandatory | Should -Be $true

            # Verify output
            $taskInfo.Outputs | Should -Contain 'ResultData'
        }

        It 'Should successully parse parameters and outputs from script file using ParseFile' {
            # Create a temporary script file
            $scriptContent = @"
<#
    .OUTPUTS
        foo
#>
param(
    [Parameter(Mandatory)]
    [string]`$Name,
    `$Age
)
Write-Output "Hello, `$Name!"
"@
            $tempFile = Join-Path $TestDrive -ChildPath 'TestTask.task.ps1'
            Set-Content -Path $tempFile -Value $scriptContent

            $scriptFile = Get-Item $tempFile
            $taskInfo = [TaskInfo]::ParseFile($scriptFile)

            $taskInfo.TaskName | Should -Be 'TestTask'
            $taskInfo.Parameters.Count | Should -Be 2
            $taskInfo.Outputs.Count | Should -Be 1

            # Verify parameters
            $param1 = $taskInfo.Parameters[0]
            $param1.ParameterName | Should -Be 'Name'
            $param1.Type | Should -Be 'String'
            $param1.IsMandatory | Should -Be $true

            $param2 = $taskInfo.Parameters[1]
            $param2.ParameterName | Should -Be 'Age'
            $param2.Type | Should -Be 'Object'
            $param2.IsMandatory | Should -Be $false

            # Verify output
            $taskInfo.Outputs | Should -Contain 'foo'
        }

        It 'Should throw an error when script file is missing' {
            { [TaskInfo]::ParseFile('c:\nonexistent.task.ps1') } | Should -Throw
        }

        It 'Should throw an error when parsing an invalid script file' {
            # Create a temporary script file
            $scriptContent = @'
@{ foo = "bar", }
'@

            $tempFile = Join-Path $TestDrive -ChildPath 'InvalidTask.task.ps1'
            Set-Content -Path $tempFile -Value $scriptContent

            $scriptFile = Get-Item $tempFile

            { [TaskInfo]::new($scriptFile) } | Should -Throw
        }
    }
}
