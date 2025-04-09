function RedirectPath {
    [CmdletBinding()]
    param (
        [string]$DataPath,    # 修改变量名，更通用：既支持文件也支持目录
        [string]$PersistPath
    )

    if (Test-Path $DataPath) {
        $item = Get-Item $DataPath -Force
        if ($item.LinkType -and $item.Target -eq $PersistPath) {
            WriteLog """$DataPath"" is already linked to ""$PersistPath""." -Level 'Warning'
            return
        }

        if ($item.LinkType) {
            WriteLog """$DataPath"" is already a link. Exiting script." -Level 'Warning'
            exit
        }
    }

    EnsureDirectory (Split-Path $PersistPath -Parent) # ⚠️ 确保持久化路径的父目录存在

    $isFile = Test-Path $DataPath -PathType Leaf   # ✅ 判断是否是文件
    $isDirectory = Test-Path $DataPath -PathType Container

    if (!(Test-Path $DataPath)) {
        # ✅ 如果目标是不存在的，直接创建符号链接
        if ($PersistPath.EndsWith('\')) {
            # Treat as directory
            EnsureDirectory $PersistPath
            New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
            WriteLog "Junction created (new): $DataPath => $PersistPath." -Level 'Info'
        } else {
            # Treat as file
            New-Item -ItemType SymbolicLink -Path $DataPath -Target $PersistPath | Out-Null
            WriteLog "Symbolic link created (new): $DataPath => $PersistPath." -Level 'Info'
        }
        return
    }

    if ($isDirectory) {
        $dataEmpty = TestDirectoryEmpty $DataPath
        $persistEmpty = TestDirectoryEmpty $PersistPath

        if (!$dataEmpty -and $persistEmpty) {
            robocopy $DataPath $PersistPath /E /MOVE /NFL /NDL /NJH /NJS /NC /NS | Out-Null
            WriteLog "Moved contents from directory ""$DataPath"" to ""$PersistPath""." -Level 'Info'
        }
        elseif (!$dataEmpty -and !$persistEmpty) {
            $backupName = "{0}-backup-{1}" -f $DataPath, (Get-Date -Format "yyMMddHHmmss")
            Rename-Item -Path $DataPath -NewName $backupName
            WriteLog "Both directories contain data. ""$DataPath"" backed up to $backupName." -Level 'Warning'
        }

        if (Test-Path $DataPath) {
            Remove-Item $DataPath -Force -Recurse
        }

        New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
        WriteLog "Junction created: $DataPath => $PersistPath." -Level 'Info'
    }
    elseif ($isFile) {
        if (!(Test-Path $PersistPath)) {
            # ✅ 如果 persist 文件还不存在，先创建目录，再移动文件
            EnsureDirectory (Split-Path $PersistPath -Parent)
            Move-Item $DataPath $PersistPath
            WriteLog "Moved file from ""$DataPath"" to ""$PersistPath""." -Level 'Info'
        }
        else {
            $backupName = "{0}-backup-{1}{2}" -f $DataPath, (Get-Date -Format "yyMMddHHmmss"), (Split-Path $DataPath -Extension)
            Rename-Item -Path $DataPath -NewName $backupName
            WriteLog "File exists in both locations. Backed up ""$DataPath"" to $backupName." -Level 'Warning'
        }

        if (Test-Path $DataPath) {
            Remove-Item $DataPath -Force
        }

        New-Item -ItemType SymbolicLink -Path $DataPath -Target $PersistPath | Out-Null
        WriteLog "Symbolic link created: $DataPath => $PersistPath." -Level 'Info'
    }
    else {
        WriteLog "Unsupported path type: $DataPath" -Level 'Error'
    }
}
