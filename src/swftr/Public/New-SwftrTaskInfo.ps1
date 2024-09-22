<#
.SYNOPSIS
    Creates a new TaskInfo object from a task file or scriptblock.

.DESCRIPTION
    Creates a new TaskInfo object from a task file or scriptblock. The task file
    should be a PowerShell script file that defines a task. The scriptblock should
    be a scriptblock that defines a task.

    In order to determine the outputs of a task, the script/scriptblock must
    use the .OUTPUTS directive in the comment-based help section. For example:

    #
    .OUTPUTS
        Name
        ProcessId
    #

    The above comment-based help section would indicate that the task outputs
    two values: Name and ProcessId.

.PARAMETER Path
    The path to a file containing a task definition (e.g. "MyTask.task.ps1").

.PARAMETER TaskName
    The name of the task. This is required when using a scriptblock. When using a
    task file, the task name is determined from the file name and this parameter
    is ignored.

.PARAMETER Scriptblock
    A scriptblock containing a task definition.

.EXAMPLE
    New-SwftrTaskInfo -Path .\MyTask.task.ps1

    Creates a new TaskInfo object from the task file "MyTask.task.ps1", returning
    the TaskInfo object.

.EXAMPLE
    Get-ChildItem -Filter *.task.ps1 | New-SwftrTaskInfo

    Creates a new TaskInfo object for each task file in the current directory.

.EXAMPLE
    New-SwftrTaskInfo -Scriptblock {
        param(
            [string]$Name,
            [int]$Age
        )
        'Output1'
        'Output2'
    }

    Creates a new TaskInfo object from the scriptblock, returning the TaskInfo object.
    Note that the TaskName parameter is required when using a scriptblock.

.NOTES
    File Name      : New-SwftrTaskInfo.ps1
    Author         : John Bruckler
    Prerequisite   : PowerShell V7
    Dependencies   : TaskInfo class
#>
function New-SwftrTaskInfo {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Scope = 'Function',
        Justification = 'This function does not change state of the system, it just instantiates an object.'
    )]
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter( Mandatory,
            ParameterSetName = 'Path',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0)]
        [System.IO.FileInfo[]] $Path,

        [Parameter( Mandatory,
            ParameterSetName = 'Scriptblock')]
        [string] $TaskName,

        [Parameter( Mandatory,
            ParameterSetName = 'Scriptblock',
            ValueFromPipeline,
            Position = 0)]
        [scriptblock[]] $Scriptblock
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Path | ForEach-Object {
                $taskInfo = [TaskInfo]::ParseFile($_)
                Write-Output $taskInfo
            }
        }
        else {
            $Scriptblock | ForEach-Object {
                $taskInfo = [TaskInfo]::ParseScriptblock($TaskName, $_)
                Write-Output $taskInfo
            }
        }
    }
}