# 确保目录存在
function EnsureDirectory {
    param (
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# 写日志函数
function WriteLog {
    param (
        [string]$Message,
        [string]$Level = 'Info'
    )

    $logMessage = "[{0}] {1} - {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $logMessage
}

# 测试目录是否为空
function TestDirectoryEmpty {
    param (
        [string]$Path
    )

    $files = Get-ChildItem -Path $Path
    return $files.Count -eq 0
}

function RedirectDirectory {
    [CmdletBinding()]
    param (
        [string]$DataPath,
        [string]$PersistPath
    )

    # 检查目标路径是否存在
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

    # 确保持久化路径的目录存在
    $persistParentDir = Split-Path -Path $PersistPath -Parent
    EnsureDirectory $persistParentDir

    # 如果是文件
    if (-not (Test-Path $PersistPath) -and (Test-Path $DataPath -PathType Leaf)) {
        # 如果目标文件夹为空，移动文件
        Move-Item -Path $DataPath -Destination $PersistPath -Force
        WriteLog "Moved file from ""$DataPath"" to ""$PersistPath""." -Level 'Info'
    }
    # 如果是目录
    elseif (-not (Test-Path $PersistPath) -and (Test-Path $DataPath -PathType Container)) {
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

    # 删除原始路径
    if (Test-Path $DataPath) {
        Remove-Item $DataPath -Force -Recurse
    }

    # 创建链接
    if (Test-Path $PersistPath -PathType Leaf) {
        New-Item -ItemType HardLink -Path $DataPath -Target $PersistPath | Out-Null
        WriteLog "Hard link created: $DataPath => $PersistPath." -Level 'Info'
    }
    elseif (Test-Path $PersistPath -PathType Container) {
        New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
        WriteLog "Junction created: $DataPath => $PersistPath." -Level 'Info'
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
