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
    param (
        [string]$DataPath,         # 目标文件
        [string]$PersistPath       # 持久化文件位置
    )

    # 如果目标文件路径为空，返回
    if (-not $DataPath) {
        Write-Host "Invalid DataPath." -ForegroundColor Red
        return
    }

    # 如果持久化路径为空，返回
    if (-not $PersistPath) {
        Write-Host "Invalid PersistPath." -ForegroundColor Red
        return
    }

    # 检查目标文件是否已存在
    if (Test-Path $DataPath) {
        Write-Host "`"$DataPath`" already exists, skipping creation of hard link." -ForegroundColor Yellow
        return
    }

    # 如果目标文件不存在，创建新的硬链接
    if (!(Test-Path $PersistPath)) {
        Write-Host "`"$PersistPath`" does not exist. Exiting function." -ForegroundColor Red
        return
    }

    # 使用 try-catch 来捕获重命名和路径拆分可能的错误
    try {
        $filename = [System.IO.Path]::GetFileName($DataPath)
        $parentDir = Split-Path $DataPath -Parent

        # 如果父目录为空，抛出异常
        if (-not $parentDir) {
            throw "Failed to get parent directory for $DataPath"
        }

        $backupName = "$parentDir\$filename-backup"
        
        # 如果文件已存在，重命名备份
        if (Test-Path $DataPath) {
            Rename-Item $DataPath -NewName $backupName
            Write-Host "`"$DataPath`" backed up to `$backupName." -ForegroundColor Green
        }

        # 创建硬链接
        New-Item -ItemType HardLink -Path $DataPath -Target $PersistPath | Out-Null
        Write-Host "`"$DataPath`" successfully linked to `$PersistPath." -ForegroundColor Green
    }
    catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
    }
}

function RemoveJunction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path $Path)) {
        Write-Host "`"$Path`" does not exist. No action taken." -ForegroundColor Yellow
        return
    }

    $item = Get-Item $Path -Force

    # 判断符号链接或目录联结
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Remove-Item $Path -Force
        Write-Host "`"$Path`" symbolic/junction link removed successfully." -ForegroundColor Green
        return
    }

    # 使用 fsutil 检查是否为硬链接
    try {
        $hardlinks = & fsutil hardlink list $item.FullName 2>$null
        if ($hardlinks.Count -gt 1) {
            Remove-Item $Path -Force
            Write-Host "`"$Path`" hard link removed (1 of $($hardlinks.Count))." -ForegroundColor Green
            return
        }
    } catch {
        Write-Host "Failed to check hard link status using fsutil: $_" -ForegroundColor Yellow
    }

    Write-Host "`"$Path`" is not a link. No action taken." -ForegroundColor Yellow
}
