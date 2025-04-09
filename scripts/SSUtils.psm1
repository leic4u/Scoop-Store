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

function persist_file($source_path, $persist_dir) {
    # 检查 $source_path 是否存在
    if (!(Test-Path $source_path)) {
        Write-Host "Source path '$source_path' does not exist. Creating it..."

        if ($source_path.EndsWith('\') -or (Test-Path $source_path -PathType Container)) {
            # 如果路径是目录或以 '\' 结尾，则创建目录
            New-Item -ItemType Directory -Path $source_path | Out-Null
        } else {
            # 如果路径是文件，则创建父目录并创建空文件
            $parent_dir = Split-Path -Parent $source_path
            if (!(Test-Path $parent_dir)) {
                New-Item -ItemType Directory -Path $parent_dir | Out-Null
            }
            New-Item -ItemType File -Path $source_path | Out-Null
        }

        Write-Host "Source path '$source_path' has been created."
    }

    # 检查 $persist_dir 是否指定了具体文件或文件夹名称
    $is_specific_target = Test-Path -Path (Split-Path -Parent $persist_dir)

    # 如果未指定具体文件或文件夹名称，则使用源路径名称作为目标名称
    if (!$is_specific_target) {
        $persist_dir = Join-Path $persist_dir (Split-Path -Leaf $source_path)
    }

    # 如果目标路径已经存在，检查类型是否冲突
    if (Test-Path $persist_dir) {
        if ((Get-Item $persist_dir).PSIsContainer -ne (Get-Item $source_path).PSIsContainer) {
            throw "Error: Target path '$persist_dir' conflicts with a different type (file vs directory)."
        }
    } else {
        # 如果目标路径不存在，则创建目标路径的父目录
        $parent_dir = Split-Path -Parent $persist_dir
        if (!(Test-Path $parent_dir)) {
            New-Item -ItemType Directory -Path $parent_dir | Out-Null
        }
    }

    # 检查源路径类型并创建链接
    if ((Get-Item $source_path).PSIsContainer) {
        # 处理目录持久化
        if (!(Test-Path $persist_dir)) {
            Write-Host "Creating directory junction for '$source_path' to '$persist_dir'."
            New-DirectoryJunction $persist_dir $source_path | Out-Null
        }
    } else {
        # 处理文件持久化
        if (!(Test-Path $persist_dir)) {
            Write-Host "Creating hard link for '$source_path' to '$persist_dir'."
            New-HardLink -Path $persist_dir -Target $source_path | Out-Null
        } else {
            Write-Host "Target file '$persist_dir' already exists. Skipped."
        }
    }

    Write-Host "Persisted '$source_path' to '$persist_dir'."
}

function RedirectDirectory {
function RedirectPath {
    [CmdletBinding()]
    param (
        [string]$DataPath,
        [string]$PersistPath
    )

    if (Test-Path $DataPath) {
        $item = Get-Item $DataPath -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            WriteLog "`"$DataPath`" is already linked to `"$PersistPath`"." -Level 'Warning'
            return
        }
    }

    $isFile = Test-Path $DataPath -PathType Leaf
    $isDirectory = Test-Path $DataPath -PathType Container

    # 🧱 确保 PersistPath 的父目录存在
    EnsureDirectory (Split-Path $PersistPath -Parent)

    if (!(Test-Path $DataPath)) {
        if ($PersistPath.EndsWith('\')) {
            EnsureDirectory $PersistPath
            New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
            WriteLog "Junction created (new): $DataPath => $PersistPath." -Level 'Info'
        } else {
            # ✅ 创建硬链接（无需管理员权限，适用于文件）
            cmd /c mklink /H "$DataPath" "$PersistPath" | Out-Null
            WriteLog "Hard link created (new): $DataPath => $PersistPath." -Level 'Info'
        }
        return
    }

    if ($isDirectory) {
        $dataEmpty = TestDirectoryEmpty $DataPath
        $persistEmpty = TestDirectoryEmpty $PersistPath

        if (!$dataEmpty -and $persistEmpty) {
            robocopy $DataPath $PersistPath /E /MOVE /NFL /NDL /NJH /NJS /NC /NS | Out-Null
            WriteLog "Moved contents from directory `"$DataPath`" to `"$PersistPath`"." -Level 'Info'
        }
        elseif (!$dataEmpty -and !$persistEmpty) {
            $backupName = "{0}-backup-{1}" -f $DataPath, (Get-Date -Format "yyMMddHHmmss")
            Rename-Item -Path $DataPath -NewName $backupName
            WriteLog "Both directories contain data. `"$DataPath`" backed up to $backupName." -Level 'Warning'
        }

        if (Test-Path $DataPath) {
            Remove-Item $DataPath -Force -Recurse
        }

        New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
        WriteLog "Junction created: $DataPath => $PersistPath." -Level 'Info'
    }
    elseif ($isFile) {
        if (!(Test-Path $PersistPath)) {
            EnsureDirectory (Split-Path $PersistPath -Parent)
            Move-Item $DataPath $PersistPath
            WriteLog "Moved file from `"$DataPath`" to `"$PersistPath`"." -Level 'Info'
        }
        else {
            $backupName = "{0}-backup-{1}{2}" -f $DataPath, (Get-Date -Format "yyMMddHHmmss"), (Split-Path $DataPath -Extension)
            Rename-Item -Path $DataPath -NewName $backupName
            WriteLog "File exists in both locations. Backed up `"$DataPath`" to $backupName." -Level 'Warning'
        }

        if (Test-Path $DataPath) {
            Remove-Item $DataPath -Force
        }

        # ✅ 创建硬链接
        cmd /c mklink /H "$DataPath" "$PersistPath" | Out-Null
        WriteLog "Hard link created: $DataPath => $PersistPath." -Level 'Info'
    }
    else {
        WriteLog "Unsupported path type: $DataPath" -Level 'Error'
    }
}

function RemoveJunction {
    [CmdletBinding()]
    param (
        [string]$DataPath,
        [string]$PersistPath
    )

    if (Test-Path $DataPath) {
        $item = Get-Item $DataPath -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            WriteLog "`"$DataPath`" is already linked to `"$PersistPath`"." -Level 'Warning'
            return
        }
    }

    $isFile = Test-Path $DataPath -PathType Leaf
    $isDirectory = Test-Path $DataPath -PathType Container

    # 🧱 确保 PersistPath 的父目录存在
    EnsureDirectory (Split-Path $PersistPath -Parent)

    if (!(Test-Path $DataPath)) {
        if ($PersistPath.EndsWith('\')) {
            EnsureDirectory $PersistPath
            New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
            WriteLog "Junction created (new): $DataPath => $PersistPath." -Level 'Info'
        } else {
            # ✅ 创建硬链接（无需管理员权限，适用于文件）
            cmd /c mklink /H "$DataPath" "$PersistPath" | Out-Null
            WriteLog "Hard link created (new): $DataPath => $PersistPath." -Level 'Info'
        }
        return
    }

    if ($isDirectory) {
        $dataEmpty = TestDirectoryEmpty $DataPath
        $persistEmpty = TestDirectoryEmpty $PersistPath

        if (!$dataEmpty -and $persistEmpty) {
            robocopy $DataPath $PersistPath /E /MOVE /NFL /NDL /NJH /NJS /NC /NS | Out-Null
            WriteLog "Moved contents from directory `"$DataPath`" to `"$PersistPath`"." -Level 'Info'
        }
        elseif (!$dataEmpty -and !$persistEmpty) {
            $backupName = "{0}-backup-{1}" -f $DataPath, (Get-Date -Format "yyMMddHHmmss")
            Rename-Item -Path $DataPath -NewName $backupName
            WriteLog "Both directories contain data. `"$DataPath`" backed up to $backupName." -Level 'Warning'
        }

        if (Test-Path $DataPath) {
            Remove-Item $DataPath -Force -Recurse
        }

        New-Item -ItemType Junction -Path $DataPath -Target $PersistPath | Out-Null
        WriteLog "Junction created: $DataPath => $PersistPath." -Level 'Info'
    }
    elseif ($isFile) {
        if (!(Test-Path $PersistPath)) {
            EnsureDirectory (Split-Path $PersistPath -Parent)
            Move-Item $DataPath $PersistPath
            WriteLog "Moved file from `"$DataPath`" to `"$PersistPath`"." -Level 'Info'
        }
        else {
            $backupName = "{0}-backup-{1}{2}" -f $DataPath, (Get-Date -Format "yyMMddHHmmss"), (Split-Path $DataPath -Extension)
            Rename-Item -Path $DataPath -NewName $backupName
            WriteLog "File exists in both locations. Backed up `"$DataPath`" to $backupName." -Level 'Warning'
        }

        if (Test-Path $DataPath) {
            Remove-Item $DataPath -Force
        }

        # ✅ 创建硬链接
        cmd /c mklink /H "$DataPath" "$PersistPath" | Out-Null
        WriteLog "Hard link created: $DataPath => $PersistPath." -Level 'Info'
    }
    else {
        WriteLog "Unsupported path type: $DataPath" -Level 'Error'
    }
}
