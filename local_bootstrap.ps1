#region BootstrapModuleDependencies


# https://docs.microsoft.com/powershell/module/packagemanagement/get-packageprovider
Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null

# https://docs.microsoft.com/powershell/module/powershellget/set-psrepository
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# List of PowerShell Modules required for the build
$modulesToInstall = New-Object System.Collections.Generic.List[object]
# https://github.com/pester/Pester
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'Pester'
            ModuleVersion = '5.6.1'
        }))
# https://github.com/nightroman/Invoke-Build
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'InvokeBuild'
            ModuleVersion = '5.11.3'
        }))
# https://github.com/PowerShell/PSScriptAnalyzer
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'PSScriptAnalyzer'
            ModuleVersion = '1.22.0'
        }))
# https://github.com/PowerShell/platyPS
# older version used due to: https://github.com/PowerShell/platyPS/issues/457
[void]$modulesToInstall.Add(([PSCustomObject]@{
            ModuleName    = 'platyPS'
            ModuleVersion = '0.12.0'
        }))


Write-Output 'Installing PowerShell Modules'
foreach ($module in $modulesToInstall) {
    $installSplat = @{
        Name               = $module.ModuleName
        RequiredVersion    = $module.ModuleVersion
        Repository         = 'PSGallery'
        SkipPublisherCheck = $true
        Force              = $true
        ErrorAction        = 'Stop'
    }
    try {
        if ($module.ModuleName -eq 'Pester' -and ($IsWindows -or $PSVersionTable.PSVersion -le [version]'5.1')) {
            # special case for Pester certificate mismatch with older Pester versions - https://github.com/pester/Pester/issues/2389
            # this only affects windows builds
            Install-Module @installSplat -SkipPublisherCheck
        }
        else {
            Install-Module @installSplat
        }
        Import-Module -Name $module.ModuleName -ErrorAction Stop
        '  - Successfully installed {0}' -f $module.ModuleName
    }
    catch {
        $message = 'Failed to install {0}' -f $module.ModuleName
        "  - $message"
        throw
    }
}
#endregion

#region BootstrapToolsDependencies
$toolsToInstall = New-Object System.Collections.Generic.List[object]
# https://git-scm.com/
[void]$toolsToInstall.Add(([PSCustomObject]@{
            ToolName   = 'git'
            CheckCmd   = 'git --version'
            InstallCmd = 'winget install git.git --accept-source-agreements --accept-package-agreements --force'
        }))
# https://www.python.org/
[void]$toolsToInstall.Add(([PSCustomObject]@{
            ToolName   = 'python'
            CheckCmd   = 'python --version'
            InstallCmd = 'winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements --force'
        }))
# https://pip.pypa.io/en/stable/
[void]$toolsToInstall.Add(([PSCustomObject]@{
            ToolName   = 'pip'
            CheckCmd   = 'Get-Command pip'
            InstallCmd = 'python get-pip.py'
            Depends    = 'python'
        }))
# https://www.mkdocs.org/
[void]$toolsToInstall.Add(([PSCustomObject]@{
            ToolName   = 'mkdocs'
            CheckCmd   = 'pip list | Select-String "^mkdocs\s+"'
            InstallCmd = 'pip install -r requirements.txt'
            Depends    = 'pip'
        }))

Write-Output 'Installing Tools'
foreach ($tool in $toolsToInstall) {
    try {
        if ($tool.CheckCmd) {
            $null = Invoke-Expression -Command $tool.CheckCmd
        }
        else {
            throw "CheckCmd not defined for $($tool.ToolName)"
        }
    }
    catch {
        Write-Output "  - Installing $($tool.ToolName)"
        Invoke-Expression -Command $tool.InstallCmd
    }
}
#endregion