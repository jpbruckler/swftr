---
external help file: swftr-help.xml
Module Name: swftr
online version:
schema: 2.0.0
---

# New-SwftrTaskInfo

## SYNOPSIS
Creates a new TaskInfo object from a task file or scriptblock.

## SYNTAX

### Path (Default)
```
New-SwftrTaskInfo [-Path] <FileInfo[]> [<CommonParameters>]
```

### Scriptblock
```
New-SwftrTaskInfo -TaskName <String> [-Scriptblock] <ScriptBlock[]>
 [<CommonParameters>]
```

## DESCRIPTION
Creates a new TaskInfo object from a task file or scriptblock.
The task file
should be a PowerShell script file that defines a task.
The scriptblock should
be a scriptblock that defines a task.

In order to determine the outputs of a task, the script/scriptblock must
use the .OUTPUTS directive in the comment-based help section.
For example:

#

## EXAMPLES

### EXAMPLE 1
```
New-SwftrTaskInfo -Path .\MyTask.task.ps1
```

Creates a new TaskInfo object from the task file "MyTask.task.ps1", returning
the TaskInfo object.

### EXAMPLE 2
```
Get-ChildItem -Filter *.task.ps1 | New-SwftrTaskInfo
```

Creates a new TaskInfo object for each task file in the current directory.

### EXAMPLE 3
```
New-SwftrTaskInfo -Scriptblock {
    param(
        [string]$Name,
        [int]$Age
    )
    'Output1'
    'Output2'
}
```

Creates a new TaskInfo object from the scriptblock, returning the TaskInfo object.
Note that the TaskName parameter is required when using a scriptblock.

## PARAMETERS

### -Path
The path to a file containing a task definition (e.g.
"MyTask.task.ps1").

```yaml
Type: FileInfo[]
Parameter Sets: Path
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: False
```

### -TaskName
The name of the task.
This is required when using a scriptblock.
When using a
task file, the task name is determined from the file name and this parameter
is ignored.

```yaml
Type: String
Parameter Sets: Scriptblock
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Scriptblock
A scriptblock containing a task definition.

```yaml
Type: ScriptBlock[]
Parameter Sets: Scriptblock
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable, -Verbose, -WarningAction, -WarningVariable, and -ProgressAction.  For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### Name
### ProcessId
### #
### The above comment-based help section would indicate that the task outputs
### two values: Name and ProcessId.
## NOTES
File Name      : New-SwftrTaskInfo.ps1
Author         : John Bruckler
Prerequisite   : PowerShell V7
Dependencies   : TaskInfo class

## RELATED LINKS
