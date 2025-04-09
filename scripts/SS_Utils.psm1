#Forked from wordpure/scoop-air,Thanks to him. https://github.com/wordpure/scoop-air/blob/main/scripts/AirUtils.psm1
function WriteLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $formattedMessage = "[$timestamp] $Message"

    switch ($Level) {
        'Info' {
            Write-Information -MessageData $formattedMessage -InformationAction Continue
        }
        'Success' {
            Write-Host $formattedMessage -ForegroundColor Green
        }
        'Warning' {
            Write-Warning -Message $formattedMessage
        }
        'Error' {
            Write-Error -Message $formattedMessage -ErrorAction Continue
        }
    }
}

function TestDirectoryEmpty {
    [CmdletBinding()]
    param ([string]$Path)

    $item = Get-Item $Path -Force
    return [string]::IsNullOrEmpty($item.GetFiles("*", [System.IO.SearchOption]::AllDirectories)) -and
    [string]::IsNullOrEmpty($item.GetDirectories("*", [System.IO.SearchOption]::AllDirectories))
}

function EnsureFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    process {
        foreach ($path in $Paths) {
            if (!(Test-Path -Path $path -PathType Leaf)) {
                New-Item -ItemType File -Path $path -Force | Out-Null
            }
        }
    }
}

function EnsureDirectory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    process {
        foreach ($path in $Paths) {
            if (!(Test-Path -Path $path -PathType Container)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }
}

function EnsureSetContent {
    [CmdletBinding()]
    param (
        [string]$FilePath,
        [string]$Content,
        [string]$Encoding = 'UTF8'
    )

    $directory = Split-Path -Path $FilePath -Parent
    EnsureDirectory $directory
    Set-Content -Path $FilePath -Value $Content -Encoding $Encoding -Force
}

function EnsureHardLink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Link,

        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (!(Test-Path $Target -PathType Leaf)) {
        WriteLog "Target is not a file or does not exist: $Target" -Level 'Error'
        return
    }

    $parentDir = Split-Path -Parent $Link
    if (!(Test-Path $parentDir)) {
        EnsureDirectory $parentDir
    }

    if (Test-Path $Link) {
        Remove-Item -Path $Link -Force
    }

    $result = New-Item -ItemType HardLink -Path $Link -Target $Target -Force -ErrorAction Stop

    if ($result) {
        WriteLog "Hard link created: $Link => $Target" -Level 'Info'
    }
}

function RemoveHardLink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        $fileInfo = Get-Item -Path $Path

        if ($fileInfo.LinkType -eq "HardLink") {
            Remove-Item -Path $Path -Force
        }
    }
}

function EnsureJunction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Link,

        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (!(Test-Path $Target -PathType Container)) {
        WriteLog "Target is not a directory or does not exist: $Target" -Level 'Error'
        return
    }

    $parentDir = Split-Path -Parent $Link
    if (!(Test-Path $parentDir)) {
        EnsureDirectory $parentDir
    }

    if (Test-Path $Link) {
        Remove-Item $Link -Recurse -Force
    }

    $result = New-Item -ItemType Junction -Path $Link -Target $Target -Force -ErrorAction Stop

    if ($result) {
        WriteLog "Junction created: $Link => $Target" -Level 'Info'
    }
}

function RedirectDirectory {
    [CmdletBinding()]
    param (
        [string]$DataPath,
        [string]$PersistPath
    )

    # 检查 DataPath 的类型
    if (Test-Path $DataPath) {
        $item = Get-Item $DataPath -Force

        # 如果已经是链接并且目标一致，则退出
        if ($item.LinkType -and $item.Target -eq $PersistPath) {
            WriteLog """$DataPath"" is already linked to ""$PersistPath""." -Level 'Warning'
            return
        }

        # 如果是一个链接，但不是到目标的链接，退出
        if ($item.LinkType) {
            WriteLog """$DataPath"" is already a link. Exiting script." -Level 'Warning'
            exit
        }
    }

    # 确保持久化路径的父级目录存在
    $persistParentDir = Split-Path -Path $PersistPath -Parent
    EnsureDirectory $persistParentDir

    # 判断 DataPath 的类型
    $dataPathType = if (Test-Path $DataPath -PathType Leaf) {
        "File"
    } elseif (Test-Path $DataPath -PathType Container) {
        "Directory"
    } else {
        "NotExist"
    }

    # 根据路径类型处理
    switch ($dataPathType) {
        "File" {
            # 如果是文件，移动文件并创建硬链接
            if (!(Test-Path $PersistPath)) {
                Move-Item -Path $DataPath -Destination $PersistPath -Force
                WriteLog "Moved file from ""$DataPath"" to ""$PersistPath""." -Level 'Info'
            }

            # 删除原始路径并创建硬链接
            if (Test-Path $DataPath) {
                Remove-Item -Path $DataPath -Force
            }

            New-Item -ItemType HardLink -Path $DataPath -Target $PersistPath | Out-Null
            WriteLog "Hard link created: $DataPath => $PersistPath." -Level 'Info'
        }
        "Directory" {
            # 如果是目录，移动目录并创建符号链接
            if (!(Test-Path $PersistPath)) {
                EnsureDirectory $PersistPath

                $dataEmpty = TestDirectoryEmpty $DataPath
                $persistEmpty = TestDirectoryEmpty $PersistPath

                if (!$dataEmpty -and $persistEmpty) {
                    robocopy $DataPath $PersistPath /E /MOVE /NFL /NDL /NJH /NJS /NC /NS | Out-Null
                    WriteLog "Moved contents from ""$DataPath"" to ""$PersistPath""." -Level 'Info'
                }
                elseif (!$dataEmpty -and !$persistEmpty) {
                    $backupName = "{0}-backup-{1}" -f $DataPath, (Get-Date -Format "yyMMddHHmmss")
                    Rename-Item -Path $DataPath -NewName $backupName
                    WriteLog "Both paths contain data. ""$DataPath"" backed up to $backupName." -Level 'Warning'
                }
            }

            # 删除原始路径并创建符号链接
            if (Test-Path $DataPath) {
                Remove-Item -Path $DataPath -Force -Recurse
            }

            New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
            WriteLog "Junction created: $DataPath => $PersistPath." -Level 'Info'
        }
        "NotExist" {
            # 如果路径不存在，直接创建链接
            if (!(Test-Path $PersistPath)) {
                WriteLog "Persist path does not exist: $PersistPath. Creating it." -Level 'Info'
                EnsureDirectory (Split-Path -Path $PersistPath -Parent)
            }

            if (Test-Path $PersistPath -PathType Leaf) {
                New-Item -ItemType HardLink -Path $DataPath -Target $PersistPath | Out-Null
                WriteLog "Hard link created: $DataPath => $PersistPath." -Level 'Info'
            }
            elseif (Test-Path $PersistPath -PathType Container) {
                New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
                WriteLog "Junction created: $DataPath => $PersistPath." -Level 'Info'
            }
        }
        default {
            WriteLog "The specified path type is not recognized: $DataPath" -Level 'Error'
            return
        }
    }
}

function RemoveJunction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        $item = Get-Item -Path $Path -Force

        # 如果是文件的硬链接
        if ($item.PSIsContainer -eq $false -and $item.LinkType -eq "HardLink") {
            Remove-Item -Path $Path -Force
            WriteLog "Removed hard link: $Path." -Level 'Info'
        }
        # 如果是文件夹的符号链接
        elseif ($item.PSIsContainer -eq $true -and $item.LinkType -eq "Junction") {
            Remove-Item -Path $Path -Recurse -Force
            WriteLog "Removed junction: $Path." -Level 'Info'
        }
        # 如果不是链接
        else {
            WriteLog """$Path"" is not a link. No action taken." -Level 'Warning'
        }
    }
    else {
        WriteLog """$Path"" does not exist. No action taken." -Level 'Warning'
    }
}
