
#region CompoundTasks
task . Clean, ValidateRequirements, TestModuleManifest, UpdateManifestExports, Analyze, AnalyzeTests, FormattingCheck, Test, CreateHelpStart, AssetCopy, Build, Archive
task LocalHelp Clean, ImportModuleManifest, CreateHelpStart
task StyleCheck ?Analyze, FormattingCheck
#endregion

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
    $script:ModuleDescription = $manifestInfo.Description
    $script:FunctionsToExport = $manifestInfo.FunctionsToExport
    $script:VersionTarget = [version] (Get-Content (Join-Path $BuildRoot 'version.txt'))

    $script:TestsPath = Join-Path -Path $BuildRoot -ChildPath 'Tests'
    $script:UnitTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Unit'
    $script:IntTestsPath = Join-Path -Path $script:TestsPath -ChildPath 'Integration'

    $script:ArtifactsPath = Join-Path -Path $BuildRoot -ChildPath 'build\Artifacts'
    $script:ArchivePath = Join-Path -Path $BuildRoot -ChildPath 'build\Archive'

    $script:BuildPSMFile = Join-Path -Path $script:ArtifactsPath -ChildPath "$($script:ModuleName).psm1"

    # Ensure our builds fail until if below a minimum defined code test coverage threshold
    $script:coverageThreshold = 3
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

# Synopsis: Clean and reset Artifacts/Archive Directory
Add-BuildTask Clean {
    Write-Build White "`tClean up our Artifacts/Archive directory..."

    $null = Remove-Item $script:ArtifactsPath -Force -Recurse -ErrorAction 0
    $null = New-Item $script:ArtifactsPath -ItemType:Directory
    $null = Remove-Item $script:ArchivePath -Force -Recurse -ErrorAction 0
    $null = New-Item $script:ArchivePath -ItemType:Directory

    Write-Build Green "`t...Clean Complete!"
} #Clean

# Synopsis: Validate system requirements are met
task ValidateRequirements {
    # this setting comes from the *.Settings.ps1
    Write-Build White "`tVerifying at least PowerShell $script:requiredPSVersion..."
    Assert-Build ($PSVersionTable.PSVersion -ge $script:requiredPSVersion) "At least Powershell $script:requiredPSVersion is required for this build to function properly"
    Write-Build Green "`t...Verification Complete!"
} #ValidateRequirements

# Synopsis: Import the current module manifest file for processing
task TestModuleManifest -Before ImportModuleManifest {
    Write-Build White "`tRunning module manifest tests..."
    Assert-Build (Test-Path $script:ModuleManifest) 'Unable to locate the module manifest file.'
    Assert-Build (Test-ManifestBool -Path $script:ModuleManifest) 'Module Manifest test did not pass verification.'
    Write-Build Green "`t...Module Manifest Verification Complete!"
}

task UpdateManifestExports -Before TestModuleManifest{
    Write-Build White "`tUpdating module manifest with exported functions..."
    $patternArr = '(?ms)(FunctionsToExport\s*=\s*@\()(.*?)(\))' # Matches array of functions
    $patternWld = "(?ms)(FunctionsToExport\s*=\s*\')(.*?)(\')"  # Matches wildcard
    $script:FunctionsToExport = Get-ChildItem -Path $script:PublicFuncPath -Filter '*.ps1' | ForEach-Object { $_.BaseName }

    $psd1Content = Get-Content -Path $script:ModuleManifest -Raw

    # Build the new FunctionsToExport content
    Write-Build DarkGray "`tBuilding new FunctionsToExport content..."
    $functionsToExportContent = 'FunctionsToExport = @(' + "`n"
    foreach ($functionName in $script:FunctionsToExport) {
        Write-Build DarkGray "`t`tAdding function: $functionName"
        $functionsToExportContent += "        '$functionName'" + ",`n"
    }
    $functionsToExportContent = $functionsToExportContent.TrimEnd(",`n")
    $functionsToExportContent += "`n    )"

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

#region TestAndAnalyze
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

    Write-Build White "`tImporting desired Pester version. Min: $script:MinPesterVersion Max: $script:MaxPesterVersion"
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
        $pesterConfiguration.CodeCoverage.Path = "$ModuleSrcPath\*\*.ps1"
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

# Synopsis: Load the module project
task ImportModuleManifest {
    Write-Build White "`tAttempting to load the project module."
    try {
        Import-Module $script:ModuleManifest -Force -PassThru -ErrorAction Stop
    }
    catch {
        throw 'Unable to load the project module'
    }
    Write-Build Green "`t...$script:ModuleName imported successfully"
}
#endregion

#region BuildHelpDocs

# Synopsis: Starts the help documentation generation process
Add-BuildTask CreateHelpStart {
    Write-Build White "`tPerforming all help related actions."

    Write-Build Gray "`tImporting platyPS v0.12.0 ..."
    Remove-Module platyPS -Force -ErrorAction SilentlyContinue
    Import-Module platyPS #-RequiredVersion 0.12.0 -ErrorAction SilentlyContinue
    Write-Build Gray "`t...platyPS imported successfully."
} #CreateHelpStart

# Synopsis: Build markdown help files for module and fail if help information is missing
task CreateMarkdownHelp -After CreateHelpStart {
    $ModulePage = "$script:ArtifactsPath\docs\$($ModuleName).md"

    $markdownParams = @{
        Module         = $ModuleName
        OutputFolder   = "$script:ArtifactsPath\docs\"
        Force          = $true
        WithModulePage = $true
        Locale         = 'en-US'
        FwLink         = 'NA'
        HelpVersion    = $script:ModuleVersion
    }

    Write-Build Gray "`tGenerating markdown files..."
    $null = New-MarkdownHelp @markdownParams
    Write-Build Gray "`t...Markdown generation completed."

    Write-Build Gray "`tReplacing markdown elements..."
    # Replace multi-line EXAMPLES
    $OutputDir = "$script:ArtifactsPath\docs\"
    $OutputDir | Get-ChildItem -File | ForEach-Object {
        # fix formatting in multiline examples
        $content = Get-Content $_.FullName -Raw
        $newContent = $content -replace '(## EXAMPLE [^`]+?```\r\n[^`\r\n]+?\r\n)(```\r\n\r\n)([^#]+?\r\n)(\r\n)([^#]+)(#)', '$1$3$2$4$5$6'
        if ($newContent -ne $content) {
            Set-Content -Path $_.FullName -Value $newContent -Force
        }
    }
    # Replace each missing element we need for a proper generic module page .md file
    $ModulePageFileContent = Get-Content -Raw $ModulePage
    $ModulePageFileContent = $ModulePageFileContent -replace '{{Manually Enter Description Here}}', $script:ModuleDescription
    $ModulePageFileContent = $ModulePageFileContent -replace '{{ Fill in the Description }}', $script:ModuleDescription
    $script:FunctionsToExport | ForEach-Object {
        Write-Build DarkGray "             Updating definition for the following function: $($_)"
        $TextToReplace = "{{Manually Enter $($_) Description Here}}"
        $ReplacementText = (Get-Help -Detailed $_).Synopsis
        $ModulePageFileContent = $ModulePageFileContent -replace $TextToReplace, $ReplacementText
    }

    $ModulePageFileContent | Out-File $ModulePage -Force -Encoding:utf8
    Write-Build Gray "`t...Markdown replacements complete."

    Write-Build Gray "`tVerifying GUID..."
    $MissingGUID = Select-String -Path "$script:ArtifactsPath\docs\*.md" -Pattern '(00000000-0000-0000-0000-000000000000)'
    if ($MissingGUID.Count -gt 0) {
        Write-Build Yellow "`tThe documentation that got generated resulted in a generic GUID. Check the GUID entry of your module manifest."
        throw 'Missing GUID. Please review and rebuild.'
    }

    Write-Build Gray "`tEvaluating if running 7.4.0 or higher..."
    # https://github.com/PowerShell/platyPS/issues/595
    if ($PSVersionTable.PSVersion -ge [version]'7.4.0') {
        Write-Build Gray "`tPerforming Markdown repair"
        # dot source markdown repair
        . $BuildRoot\MarkdownRepair.ps1
        $OutputDir | Get-ChildItem -File | ForEach-Object {
            Repair-PlatyPSMarkdown -Path $_.FullName
        }
    }

    Write-Build Gray "`tChecking for missing documentation in md files..."
    $MissingDocumentation = Select-String -Path "$script:ArtifactsPath\docs\*.md" -Pattern '({{.*}})'
    if ($MissingDocumentation.Count -gt 0) {
        Write-Build Yellow "`t`tThe documentation that got generated resulted in missing sections which should be filled out."
        Write-Build Yellow "`t`tPlease review the following sections in your comment based help, fill out missing information and rerun this build:"
        Write-Build Yellow "`t`t(Note: This can happen if the .EXTERNALHELP CBH is defined for a function before running this build.)"
        Write-Build Yellow "`t`tPath of files with issues: $script:ArtifactsPath\docs\"
        $MissingDocumentation | Select-Object FileName, LineNumber, Line | Format-Table -AutoSize
        throw 'Missing documentation. Please review and rebuild.'
    }

    Write-Build Gray "`tChecking for missing SYNOPSIS in md files..."
    $fSynopsisOutput = @()
    $synopsisEval = Select-String -Path "$script:ArtifactsPath\docs\*.md" -Pattern '^## SYNOPSIS$' -Context 0, 1
    $synopsisEval | ForEach-Object {
        $chAC = $_.Context.DisplayPostContext.ToCharArray()
        if ($null -eq $chAC) {
            $fSynopsisOutput += $_.FileName
        }
    }
    if ($fSynopsisOutput) {
        Write-Build Yellow "`tThe following files are missing SYNOPSIS:"
        $fSynopsisOutput
        throw 'SYNOPSIS information missing. Please review.'
    }

    Write-Build Gray "`t...Markdown generation complete."
} #CreateMarkdownHelp

task CopyDocs -After CreateMarkdownHelp {
    Write-Build Gray "`tCopying markdown files to en-US folder..."
    Copy-Item -Path "$BuildRoot\docs\*" -Destination "$script:ArtifactsPath\docs\" -Force
    Write-Build Gray "`t...Markdown files copied."
} #CopyDocs

# Synopsis: Build the external xml help file from markdown help files with PlatyPS
task CreateExternalHelp -After CreateMarkdownHelp {
    Write-Build Gray "`t`tCreating external xml help file..."
    $null = New-ExternalHelp "$script:ArtifactsPath\docs" -OutputPath "$script:ArtifactsPath\en-US\" -Force
    Write-Build Gray "`t`t...External xml help file created!"
} #CreateExternalHelp

task CreateHelpComplete -After CreateExternalHelp {
    Write-Build Green "`t...CreateHelp Complete!"
} #CreateHelpStart

# Synopsis: Replace comment based help (CBH) with external help in all public functions for this project
task UpdateCBH -After AssetCopy {
    $ExternalHelp = @"
<#
.EXTERNALHELP $($ModuleName)-help.xml
#>
"@

    $CBHPattern = '(?ms)(\<#.*\.SYNOPSIS.*?#>)'
    Get-ChildItem -Path "$script:ArtifactsPath\Public\*.ps1" -File | ForEach-Object {
        $FormattedOutFile = $_.FullName
        Write-Output "`tReplacing CBH in file: $($FormattedOutFile)"
        $UpdatedFile = (Get-Content $FormattedOutFile -Raw) -replace $CBHPattern, $ExternalHelp
        $UpdatedFile | Out-File -FilePath $FormattedOutFile -Force -Encoding:utf8
    }
} #UpdateCBH

#endregion

#region Build
# Synopsis: Copies module assets to Artifacts folder
task AssetCopy -Before Build {
    Write-Build Gray "`tCopying assets to Artifacts..."
    Copy-Item -Path "$script:ModuleSrcPath\*" -Destination $script:ArtifactsPath -Exclude *.psd1, *.psm1 -Recurse -ErrorAction Stop

    Write-Build Gray "`tCopying generated markdown files to to src docs..."
    Copy-Item -Path "$script:ArtifactsPath\docs\*" -Destination "$BuildRoot\docs\" -Force -Recurse -ErrorAction Stop
    Write-Build Gray "`t...Assets copy complete."
} #AssetCopy

task Build {
    Write-Build White "`tPerforming Module Build"

    Write-Build Gray "`t`tCopying manifest file to Artifacts..."
    Copy-Item -Path $script:ModuleManifest -Destination $script:ArtifactsPath -Recurse -ErrorAction Stop
    #Copy-Item -Path $script:ModuleSourcePath\bin -Destination $script:ArtifactsPath -Recurse -ErrorAction Stop
    Write-Build Gray "`t`t...manifest copy complete."

    Write-Build Gray "`t`tMerging Public and Private functions to one module file..."
    #$private = "$script:ModuleSourcePath\Private"
    $scriptContent = [System.Text.StringBuilder]::new()
    #$powerShellScripts = Get-ChildItem -Path $script:ModuleSourcePath -Filter '*.ps1' -Recurse
    $powerShellScripts = Get-ChildItem -Path $script:ArtifactsPath -Recurse | Where-Object { $_.Name -match '^*.ps1$' }
    foreach ($script in $powerShellScripts) {
        $null = $scriptContent.Append((Get-Content -Path $script.FullName -Raw))
        $null = $scriptContent.AppendLine('')
        $null = $scriptContent.AppendLine('')
    }
    $scriptContent.ToString() | Out-File -FilePath $script:BuildPSMFile -Encoding utf8 -Force
    Write-Build Gray "`t`t...Module creation complete."

    Write-Build Gray "`t`tCleaning up leftover artifacts..."
    #cleanup artifacts that are no longer required
    if (Test-Path "$script:ArtifactsPath\Public") {
        Remove-Item "$script:ArtifactsPath\Public" -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path "$script:ArtifactsPath\Private") {
        Remove-Item "$script:ArtifactsPath\Private" -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path "$script:ArtifactsPath\Classes") {
        Remove-Item "$script:ArtifactsPath\Classes" -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path "$script:ArtifactsPath\Imports.ps1") {
        Remove-Item "$script:ArtifactsPath\Imports.ps1" -Force -ErrorAction SilentlyContinue
    }

    # if (Test-Path "$script:ArtifactsPath\docs") {
    #     #here we update the parent level docs. If you would prefer not to update them, comment out this section.
    #     Write-Build Gray "`t`tOverwriting docs output..."
    #     if (-not (Test-Path '..\docs\')) {
    #         New-Item -Path '..\docs\' -ItemType Directory -Force | Out-Null
    #     }
    #     Move-Item "$script:ArtifactsPath\docs\*.md" -Destination '..\docs\' -Force
    #     Remove-Item "$script:ArtifactsPath\docs" -Recurse -Force -ErrorAction Stop
    #     Write-Build Gray "`t`t...Docs output completed."
    # }

    Write-Build Green "`t...Build Complete!"
} #Build

# Synopsis: Creates an archive of the built Module
task Archive {
    Write-Build White "`t  Performing Archive..."

    if (Test-Path -Path $script:ArchivePath) {
        $null = Remove-Item -Path $script:ArchivePath -Recurse -Force
    }

    $null = New-Item -Path $script:ArchivePath -ItemType Directory -Force

    $zipFileName = '{0}_{1}_{2}.{3}.zip' -f $script:ModuleName, $script:ModuleVersion, ([DateTime]::UtcNow.ToString('yyyyMMdd')), ([DateTime]::UtcNow.ToString('hhmmss'))

    Write-Build Gray "`t`tCreating archive file: $zipFileName"

    $zipFile = Join-Path -Path $script:ArchivePath -ChildPath $zipFileName

    if ($PSEdition -eq 'Desktop') {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($script:ArtifactsPath, $zipFile)

    Write-Build Green "`t`t...Archive Complete!"
} #Archive
#endregion