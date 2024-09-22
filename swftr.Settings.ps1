# specify the minimum required major PowerShell version that the build script should validate
[version]$script:requiredPSVersion = '5.1.0'

function Test-ManifestBool ($Path) {
    Get-ChildItem $Path | Test-ModuleManifest -ErrorAction SilentlyContinue | Out-Null; $?
}

function Format-BoxedMessage {
    param(
        [string[]]$Messages
    )

    # Initialize StringBuilder
    $sb = New-Object System.Text.StringBuilder

    $lineWidth = 80  # Total line width
    $indent = '     '  # 5 spaces
    $maxTextWidth = $lineWidth - 2 - $indent.Length - 5  # Adjusted for borders and margins

    # Build the top border line
    $topLine = '╔' + ('═' * ($lineWidth - 2)) + '╗'
    $null = $sb.AppendLine($topLine)

    # Function to wrap text
    function WrapText {
        param(
            [string]$Text,
            [int]$MaxWidth
        )
        $lines = @()
        $currentLine = ''
        foreach ($word in $Text -split '\s+') {
            if (($currentLine.Length + $word.Length + 1) -le $MaxWidth) {
                if ($currentLine.Length -gt 0) {
                    $currentLine += ' '
                }
                $currentLine += $word
            }
            else {
                if ($currentLine.Length -gt 0) {
                    $lines += $currentLine
                }
                $currentLine = $word
            }
        }
        if ($currentLine.Length -gt 0) {
            $lines += $currentLine
        }
        return $lines
    }

    # Process each message
    foreach ($message in $Messages) {
        # Wrap the message text
        $wrappedLines = WrapText -Text $message -MaxWidth $maxTextWidth

        foreach ($line in $wrappedLines) {
            # Build the content line with indentation
            $content = $indent + $line
            # Pad the content to fit within the box
            $content = $content.PadRight($lineWidth - 2)
            $null = $sb.AppendLine("║$content║")
        }
    }

    # Build the bottom border line
    $bottomLine = '╚' + ('═' * ($lineWidth - 2)) + '╝'
    $null = $sb.AppendLine($bottomLine)

    # Output the constructed box
    return $sb.ToString()
}
