


#region BuildSetup

# import build settings
$ModuleName = [regex]::Match((Get-Item $BuildFile).Name, '^(.*)\.build\.ps1$').Groups[1].Value
. "./$ModuleName.Settings.ps1"

Enter-Build {
    $script:ModuleName = [regex]::Match((Get-Item $BuildFile).Name, '^(.*)\.build\.ps1$').Groups[1].Value

    # Identify other required paths
    $script:ProjectSrcPath = Join-Path -Path $BuildRoot -ChildPath 'src'
    $script:ModuleSrcPath = Join-Path -Path $script:ProjectSrcPath -ChildPath $script:ModuleName
    $script:ModuleFiles = Join-Path -Path $script:ModuleSrcPath -ChildPath '*'
    $script:PublicFuncPath = Join-Path -Path $script:ModuleSrcPath -ChildPath 'Public'
    $script:ModuleManifest = Join-Path -Path $script:ModuleSrcPath -ChildPath "$($script:ModuleName).psd1"

    $manifestInfo = Import-PowerShellDataFile -Path $script:ModuleManifest
    $script:ModuleVersion = [version] $manifestInfo.ModuleVersion
    $script:ModuleDesc = $manifestInfo.Description
    $script:ExportedFuncs = $manifestInfo.FunctionsToExport
    $script:VersionTarget = [version] (Get-Content (Join-Path $BuildRoot 'version.txt'))

    $script:TestsPath = Join-Path -Path $BuildRoot -ChildPath 'Tests'
    $script:UnitTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Unit'
    $script:IntTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Integration'

    $script:ArtifactsPath = Join-Path -Path $BuildRoot -ChildPath 'build\Artifacts'
    $script:ArchivePath = Join-Path -Path $BuildRoot -ChildPath 'build\Archive'

    $script:BuildPSMFile = Join-Path -Path $script:ArtifactsPath -ChildPath "$($script:ModuleName).psm1"

    # Ensure our builds fail until if below a minimum defined code test coverage threshold
    $script:coverageThreshold = 30
    $script:testOutputFormat = 'NUnitXML'
    [version]$script:MinPesterVersion = '5.2.2'
    [version]$script:MaxPesterVersion = '5.99.99'

    $headerMsgs = @(
        "Building module....: $script:ModuleName",
        "Manifest Version...: $script:ModuleVersion",
        "Target Version.....: $script:VersionTarget",
        "Description........: $script:ModuleDesc",
        "Functions to Export: $($script:ExportedFuncs -join ', ')"
    )
    Write-Build White (Format-BoxedMessage -Messages $headerMsgs)
}

Set-BuildHeader {
    param($Path)

    $headerMsgs = @(
        "Task Name..........: $($Task.Name.replace('_', '').ToUpper())",
        "Task Path..........: $Path",
        "Task Synopsis......: $(Get-BuildSynopsis $Task)"
    )
    Write-Build Cyan (Format-BoxedMessage -Messages $headerMsgs)
}

Set-BuildFooter {
    param($Path)

    $footerMsgs = @(
        "Task Path..........: $Path",
        "Duration...........: $($Task.Elapsed)"
    )
    Write-Build DarkYellow (Format-BoxedMessage -Messages $footerMsgs)
}
#endregion

# Synopsis: "Hello, World!"
task HelloWorld {
    Write-Build Green 'Hello, World!'
}

task UpdateManifestExports {
    Write-Build White "`tUpdating module manifest with exported functions..."
    $patternArr = '(?ms)(FunctionsToExport\s*=\s*@\()(.*?)(\))' # Matches array of functions
    $patternWld = "(?ms)(FunctionsToExport\s*=\s*\')(.*?)(\')"  # Matches wildcard
    $functionNames = Get-ChildItem -Path $script:PublicFuncPath -Filter '*.ps1' | ForEach-Object { $_.BaseName }

    $psd1Content = Get-Content -Path $script:ModuleManifest -Raw

    # Build the new FunctionsToExport content
    Write-Build DarkGray "`tBuilding new FunctionsToExport content..."
    $functionsToExportContent = 'FunctionsToExport = @(' + "`n"
    foreach ($functionName in $functionNames) {
        Write-Build DarkGray "`t`tAdding function: $functionName"
        $functionsToExportContent += "`t`t'$functionName'" + "`n"
    }
    $functionsToExportContent += "`t)"

    if ($psd1Content -match $patternArr) {
        Write-Build DarkGray "`tFunctionsToExport = '*' found, updating..."
        $psd1Content = $psd1Content -replace $patternArr, $functionsToExportContent
    }
    elseif ($psd1Content -match $patternWld) {
        Write-Build DarkGray "`tNo FunctionsToExport = @(...) found, updating..."
        $psd1Content = $psd1Content -replace $patternWld, $functionsToExportContent
    }
    else {
        Write-Build DarkGray "`tNo FunctionsToExport found, adding..."
        $psd1Content += "`n$functionsToExportContent"
    }

    Write-Build DarkGray "`tWriting changes to manifest..."
    # Write the updated content back to the PSD1 file
    $psd1Content | Set-Content -Path $script:ModuleManifest -Encoding UTF8

    Write-Build Green "`t...Manifest updated!"
}

# Synopsis: Perform a PSScriptAnalyzer check on the module
task Analyze {
    $scriptAnalyzerParams = @{
        Path    = $script:ModuleSrcPath
        Setting = 'PSScriptAnalyzerSettings.psd1'
        Recurse = $true
        Verbose = $false
    }

    Write-Build White "`tPerforming Module ScriptAnalyzer checks..."
    $scriptAnalyzerResults = Invoke-ScriptAnalyzer @scriptAnalyzerParams

    if ($scriptAnalyzerResults) {
        $scriptAnalyzerResults | Format-Table
        throw "`tOne or more PSScriptAnalyzer errors/warnings where found."
    }
    else {
        Write-Build Green "`t...Module Analyze Complete!"
    }
} #Analyze

# Synopsis: Invokes Script Analyzer against the Tests path if it exists
task AnalyzeTests -After Analyze {
    if (Test-Path -Path $script:TestsPath) {

        $scriptAnalyzerParams = @{
            Path        = $script:TestsPath
            Setting     = 'PSScriptAnalyzerSettings.psd1'
            ExcludeRule = 'PSUseDeclaredVarsMoreThanAssignments'
            Recurse     = $true
            Verbose     = $false
        }

        Write-Build White "`tPerforming Test ScriptAnalyzer checks..."
        $scriptAnalyzerResults = Invoke-ScriptAnalyzer @scriptAnalyzerParams

        if ($scriptAnalyzerResults) {
            $scriptAnalyzerResults | Format-Table
            throw "`tOne or more PSScriptAnalyzer errors/warnings where found."
        }
        else {
            Write-Build Green "`t...Test Analyze Complete!"
        }
    }
} #AnalyzeTests

# Synopsis: Analyze scripts to verify if they adhere to desired coding format (Stroustrup / OTBS / Allman)
task FormattingCheck {

    $scriptAnalyzerParams = @{
        Setting     = 'CodeFormattingStroustrup'
        ExcludeRule = 'PSUseConsistentWhitespace'
        Recurse     = $true
        Verbose     = $false
    }

    Write-Build White "`tPerforming script formatting checks..."
    $scriptAnalyzerResults = Get-ChildItem -Path $script:ModuleSourcePath -Exclude '*.psd1' | Invoke-ScriptAnalyzer @scriptAnalyzerParams

    if ($scriptAnalyzerResults) {
        $scriptAnalyzerResults | Format-Table
        throw "`tPSScriptAnalyzer code formatting check did not adhere to {0} standards" -f $scriptAnalyzerParams.Setting
    }
    else {
        Write-Build Green "`t...Formatting Analyze Complete!"
    }
} #FormattingCheck

#Synopsis: Invokes all Pester Unit Tests in the Tests\Unit folder (if it exists)
task Test {

    Write-Build White "      Importing desired Pester version. Min: $script:MinPesterVersion Max: $script:MaxPesterVersion"
    Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue # there are instances where some containers have Pester already in the session
    Import-Module -Name Pester -MinimumVersion $script:MinPesterVersion -MaximumVersion $script:MaxPesterVersion -ErrorAction 'Stop'

    $codeCovPath = "$script:ArtifactsPath\ccReport\"
    $testOutPutPath = "$script:ArtifactsPath\testOutput\"
    if (-not(Test-Path $codeCovPath)) {
        New-Item -Path $codeCovPath -ItemType Directory | Out-Null
    }
    if (-not(Test-Path $testOutPutPath)) {
        New-Item -Path $testOutPutPath -ItemType Directory | Out-Null
    }
    if (Test-Path -Path $script:UnitTestsPath) {
        $pesterConfiguration = New-PesterConfiguration
        $pesterConfiguration.run.Path = $script:UnitTestsPath
        $pesterConfiguration.Run.PassThru = $true
        $pesterConfiguration.Run.Exit = $false
        $pesterConfiguration.CodeCoverage.Enabled = $true
        $pesterConfiguration.CodeCoverage.Path = "..\..\..\src\$ModuleName\*\*.ps1"
        $pesterConfiguration.CodeCoverage.CoveragePercentTarget = $script:coverageThreshold
        $pesterConfiguration.CodeCoverage.OutputPath = "$codeCovPath\CodeCoverage.xml"
        $pesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'
        $pesterConfiguration.TestResult.Enabled = $true
        $pesterConfiguration.TestResult.OutputPath = "$testOutPutPath\PesterTests.xml"
        $pesterConfiguration.TestResult.OutputFormat = $script:testOutputFormat
        $pesterConfiguration.Output.Verbosity = 'Detailed'

        Write-Build White "`tPerforming Pester Unit Tests..."
        # Publish Test Results
        $testResults = Invoke-Pester -Configuration $pesterConfiguration

        # This will output a nice json for each failed test (if running in CodeBuild)
        if ($env:CODEBUILD_BUILD_ARN) {
            $testResults.TestResult | ForEach-Object {
                if ($_.Result -ne 'Passed') {
                    ConvertTo-Json -InputObject $_ -Compress
                }
            }
        }

        $numberFails = $testResults.FailedCount
        Assert-Build($numberFails -eq 0) ('Failed "{0}" unit tests.' -f $numberFails)

        Write-Build Gray ("`t...CODE COVERAGE - CommandsExecutedCount: {0}" -f $testResults.CodeCoverage.CommandsExecutedCount)
        Write-Build Gray ("`t...CODE COVERAGE - CommandsAnalyzedCount: {0}" -f $testResults.CodeCoverage.CommandsAnalyzedCount)

        if ($testResults.CodeCoverage.NumberOfCommandsExecuted -ne 0) {
            $coveragePercent = '{0:N2}' -f ($testResults.CodeCoverage.CommandsExecutedCount / $testResults.CodeCoverage.CommandsAnalyzedCount * 100)

            <#
            if ($testResults.CodeCoverage.NumberOfCommandsMissed -gt 0) {
                'Failed to analyze "{0}" commands' -f $testResults.CodeCoverage.NumberOfCommandsMissed
            }
            Write-Host "PowerShell Commands not tested:`n$(ConvertTo-Json -InputObject $testResults.CodeCoverage.MissedCommands)"
            #>
            if ([Int]$coveragePercent -lt $coverageThreshold) {
                throw ('Failed to meet code coverage threshold of {0}% with only {1}% coverage' -f $coverageThreshold, $coveragePercent)
            }
            else {
                Write-Build Cyan "`t$('Covered {0}% of {1} analyzed commands in {2} files.' -f $coveragePercent,$testResults.CodeCoverage.CommandsAnalyzedCount,$testResults.CodeCoverage.FilesAnalyzedCount)"
                Write-Build Green "`t...Pester Unit Tests Complete!"
            }
        }
        else {
            # account for new module build condition
            Write-Build Yellow "`tCode coverage check skipped. No commands to execute..."
        }

    }
} #Test

# Synopsis: Used to generate xml file to graphically display code coverage in VSCode using Coverage Gutters
task DevCC {
    Write-Build White "`tGenerating code coverage report at root..."
    Write-Build White "`tImporting desired Pester version. Min: $script:MinPesterVersion Max: $script:MaxPesterVersion"
    Remove-Module -Name Pester -Force -ErrorAction SilentlyContinue # there are instances where some containers have Pester already in the session
    Import-Module -Name Pester -MinimumVersion $script:MinPesterVersion -MaximumVersion $script:MaxPesterVersion -ErrorAction 'Stop'
    $pesterConfiguration = New-PesterConfiguration
    $pesterConfiguration.run.Path = $script:UnitTestsPath
    $pesterConfiguration.CodeCoverage.Enabled = $true
    $pesterConfiguration.CodeCoverage.Path = "$PSScriptRoot\src\$ModuleName\*\*.ps1"
    $pesterConfiguration.CodeCoverage.CoveragePercentTarget = $script:coverageThreshold
    $pesterConfiguration.CodeCoverage.OutputPath = '..\..\cov.xml'
    $pesterConfiguration.CodeCoverage.OutputFormat = 'CoverageGutters'

    Invoke-Pester -Configuration $pesterConfiguration
    Write-Build Green "`t...Code Coverage report generated!"
} #DevCC