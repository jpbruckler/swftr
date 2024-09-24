<#
    .SYNOPSIS
        TaskInfo class definition.

    .DESCRIPTION
        TaskInfo class definition. Used to store information about a task, such as its name,
        parameters, outputs, and path.

        Constructor:
            - TaskInfo: Initializes a new instance of the TaskInfo class.
            - TaskInfo<TaskName>: Initializes a new instance of the TaskInfo class with a TaskName.
            - TaskInfo<ScriptFile>: Initializes a new instance of the TaskInfo class with a ScriptFile.

        Static methods:
            - ParseScriptblock: Parses a scriptblock and returns a TaskInfo object.
            - ParseFile: Parses a task file and returns a TaskInfo object.

    .PARAMETER TaskName
        The name of the task. This maps back to a task file name. For example, a task file named
        "MyTask.task.ps1" would have a TaskName of "MyTask".

    .PARAMETER Parameters
        An array of TaskParameterInfo objects that represent the parameters of the task.

    .PARAMETER Outputs
        An array of strings that represent the outputs documented by a task.

    .PARAMETER Path
        The full path to the task file.

    .EXAMPLE
        $ti = [TaskInfo]::ParseFile($taskFile)

        $ti.TaskName
        $ti.Path
        $ti.Parameters
        $ti.Outputs

    .EXAMPLE
        $ti = [TaskInfo]::ParseScriptblock('MyTask', {
            param(
                [string]$Name,
                [int]$Age
            )
            'Output1'
            'Output2'
        })

        $ti.TaskName
        $ti.Parameters
        $ti.Outputs

    .NOTES
        File Name      : TaskInfo.class.ps1
        Author         : John Bruckler
        Prerequisite   : PowerShell V7
        Dependencies   : TaskParameterInfo.class.ps1
#>
class TaskInfo {
    [string] $TaskName
    [TaskParameterInfo[]] $Parameters = @()
    [string[]] $Outputs = @()
    [System.IO.FileInfo] $Path

    hidden TaskInfo() {
        $this.TaskName      = $null
        $this.Path          = $null
    }

    [void] hidden AddParameters([scriptblock] $ScriptBlock) {
        $ParamList      = [System.Collections.Generic.List[TaskParameterInfo]]::New()
        $FoundParams    = $ScriptBlock.Ast.FindAll(
            {
                param($item)
                return $item -is [System.Management.Automation.Language.ParameterAst]
            },
            $true
        )

        foreach ($param in $FoundParams) {
            $ParamList.Add([TaskParameterInfo]::New($param))
        }

        $this.Parameters = $ParamList
    }

    [void] hidden AddOutputs([scriptblock]$ScriptBlock) {
        $helpinfo = $ScriptBlock.Ast.GetHelpContent()
        if (-not ([string]::IsNullOrWhiteSpace($helpinfo.Outputs))) {
            $this.Outputs = $helpinfo.Outputs.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { -not([string]::IsNullOrWhiteSpace($_)) }
        }
    }

    static [TaskInfo] ParseScriptblock([string] $TaskName, [scriptblock] $ScriptBlock) {
        $ti = [TaskInfo]::New()
        $ti.TaskName = $TaskName

        # Set outputs
        $ti.AddOutputs($ScriptBlock)

        # Set parameters
        $ti.AddParameters($ScriptBlock)

        return $ti
    }

    static [TaskInfo] ParseFile([System.IO.FileInfo]$ScriptFile) {
        if (-not (Test-Path $ScriptFile.FullName)) {
            throw "File not found: $($ScriptFile.FullName)"
        }

        $ti = [TaskInfo]::New()
        $ti.TaskName = $ScriptFile.BaseName -replace '\.task',''
        $ti.Path = $ScriptFile.FullName

        try {
            $ScriptBlock = [scriptblock]::Create((Get-Content -Path $ScriptFile.FullName -Raw))
        }
        catch {
            throw "Failed to parse script file: $($ScriptFile.FullName). Error: $_"
        }

        # Set outputs
        $ti.AddOutputs($ScriptBlock)

        # Set parameters
        $ti.AddParameters($ScriptBlock)

        # Cleanup
        $ScriptBlock = $null

        return $ti
    }
}

<#
    .SYNOPSIS
        TaskParameterInfo class definition.
    .DESCRIPTION
        TaskParameterInfo class definition. Used to store information about a task parameter,
        such as its name, type, and whether it is a mandatory parameter.

        This is intended to be used as a nested class within the TaskInfo class.

        Constructor:
            - TaskParameterInfo: Parses a ParameterAst object and returns a TaskParameterInfo object.
    .PARAMETER Parameter
        The parameter to parse. This should be a ParameterAst object.
    .NOTES
        File Name      : TaskParameterInfo.class.ps1
        Author         : John Bruckler
        Prerequisite   : PowerShell V7
        Dependencies   : None
#>
class TaskParameterInfo {
    [string]$ParameterName
    [string]$Type
    [bool]$IsMandatory

    TaskParameterInfo([System.Management.Automation.Language.Ast] $Parameter) {

        $this.ParameterName = $Parameter.Name.VariablePath.UserPath

        $this.Type = if ($Parameter.StaticType) {
            $Parameter.StaticType.Name
        }
        else {
            'Object'
        }

        $this.IsMandatory = $Parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' } |
            ForEach-Object -MemberName NamedArguments |
            Where-Object { $_.ArgumentName -eq 'Mandatory' -AND $_.Extent -notmatch '\$false' }
    }
}