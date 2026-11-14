# CIMG

基于 FFmpeg 的 Windows 批量图片压缩工具。支持递归目录、CPU 多核并行、多个输入目录、UNC 网络路径及安全覆盖原图。

- 默认不修改原图，结果写入 `_compressed`
- 默认最长边 1920px、质量 80
- 小于 400KB 的图片不重新编码
- 默认并行处理 4 张图片
- 支持 JPG、JPEG、PNG、WebP、BMP、TIF、TIFF

## 安装

### 一键安装（推荐）

在 PowerShell 中复制运行一条命令。GitHub 可达时用：

```powershell
irm https://raw.githubusercontent.com/zhjhaibin/CIMG/main/install.ps1 | iex
```

国内访问 GitHub 不稳定时，用 jsDelivr 入口（效果完全相同）：

```powershell
irm https://cdn.jsdelivr.net/gh/zhjhaibin/CIMG@main/install.ps1 | iex
```

脚本会自动下载最新版本、解压到 `%LOCALAPPDATA%\CIMG` 并写入当前用户 PATH。**重新打开终端**后即可在任意目录使用 `cimg`（已打开的窗口无法被自动刷新，Windows 机制限制；脚本结束时会把一行可立即生效的命令打印出来，复制运行即可）。

安装器下载时默认先直连 GitHub，失败后自动改用内置镜像（ghfast.top、gh-proxy.com）重试，无需手动配置；也可固定镜像：

```powershell
& ([scriptblock]::Create((irm https://cdn.jsdelivr.net/gh/zhjhaibin/CIMG@main/install.ps1))) -DownloadMirror "https://ghfast.top"
```

自定义安装目录：

```powershell
& ([scriptblock]::Create((irm https://cdn.jsdelivr.net/gh/zhjhaibin/CIMG@main/install.ps1))) -InstallDir "D:\Tools\CIMG"
```

重复运行即覆盖升级。卸载时运行安装目录中的 `uninstall.ps1`：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CIMG\uninstall.ps1"
```

### 手动安装

从 [GitHub Releases](https://github.com/zhjhaibin/CIMG/releases/latest) 下载最新版 Windows 压缩包，解压到一个固定目录，例如 `C:\Tools\CIMG`。

前往 [FFmpeg 官方下载页面](https://ffmpeg.org/download.html) 获取 Windows 版本。安装完成后，在 PowerShell 中检查：

```powershell
ffmpeg -version
```

能够显示版本信息即表示安装成功。也可以不配置 FFmpeg 的 PATH，直接把 `ffmpeg.exe` 放到 CIMG 目录。

然后将 CIMG 目录添加到当前用户 PATH。在 CIMG 解压目录中打开 PowerShell，复制运行：

```powershell
$cimgDirectory = (Get-Location).Path
$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($pathEntries -notcontains $cimgDirectory) {
    $newUserPath = (($pathEntries + $cimgDirectory) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
}
```

添加后便可在任意目录直接输入 `cimg`。也可以手动设置：打开“系统属性 → 高级 → 环境变量”，编辑当前用户的 `Path`，新增 CIMG 所在目录。

设置完成后，完全关闭并重新打开终端，然后检查：

```powershell
Get-Command cimg
```

## 推荐用法：在照片目录右键打开终端

1. 在文件资源管理器中进入需要压缩的照片目录。
2. 在目录空白处右键，选择“在终端中打开”；Windows 10 可使用 Shift + 右键选择“在此处打开 PowerShell 窗口”。
3. 运行：

```powershell
cimg
```

压缩结果会写入当前目录下的 `_compressed`，并保持原有子目录结构。

## 其他用法

处理指定的一个或多个目录：

```powershell
cimg "D:\照片1" "E:\照片2"
```

本地 SSD 可尝试提高并行数：

```powershell
cimg -Parallel 8
```

确认原图已有备份后，可用压缩结果覆盖原图：

```powershell
cimg -Cover
```

覆盖模式会先生成并验证临时文件，再替换原图；小于 400KB 或压缩后没有变小的图片保持不变。覆盖不可撤销，请谨慎使用。

如果不想配置 PATH，也可以选中一个或多个照片文件夹，拖到 `Compress Photos.cmd` 上；直接双击该文件则可选择一个目录。

## UNC 网络路径是什么

UNC（Universal Naming Convention，通用命名约定）是 Windows 访问网络共享目录的标准路径格式，不需要先映射成盘符：

```text
\\服务器名称\共享目录\子目录
\\192.168.0.7\共享目录\照片
```

CIMG 的启动器支持直接在此类网络目录中运行。网络存储容易受局域网和 NAS 性能限制，建议保持默认的 4 路并行；如果速度不稳定，可降低为：

```powershell
cimg -Parallel 2
```

## 默认行为

- 递归处理当前目录及其子目录。
- 小于 400KB 的图片不重新编码，原样复制到输出目录。
- 最长边超过 1920px 时才缩小，不放大小图。
- JPG/WebP 使用约 80 的质量设置；PNG/TIFF 使用无损压缩。
- 默认并行处理 4 张图片，利用 CPU 多核。
- 不修改原图，也不覆盖已经存在的输出文件。
- 重新编码后反而更大时，直接复制原文件。
- 尽量保留元数据和原修改时间；FFmpeg 不保证完整保留所有厂商私有 EXIF 字段。

## 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-MaxLongEdge` | `1920` | 最大长边；设为 `0` 表示保持分辨率 |
| `-Quality` | `80` | JPG/WebP 质量，范围 1～100 |
| `-MinSizeKB` | `400` | 小于此大小时原样复制；设为 `0` 表示全部压缩 |
| `-Parallel` | `4` | 并行任务数；网络目录建议 2～4，本地 SSD 可尝试 8 |
| `-OutputFormat` | `same` | 保持原格式；也可设为 `jpg` 或 `webp` |
| `-OutputFolderName` | `_compressed` | 输出目录名称 |
| `-Cover` | 关闭 | 用压缩结果覆盖原图，不生成 `_compressed`；仅支持保持原格式 |
| `-Overwrite` | 关闭 | 覆盖已经存在的输出照片 |

首次使用建议保留默认设置，随机检查几张输出照片后再决定是否删除原图。不要直接覆盖唯一一份原始照片。
