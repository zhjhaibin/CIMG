# CIMG

基于 FFmpeg 的 Windows 批量图片压缩工具。支持递归目录、多个输入目录、UNC 网络路径及安全覆盖原图。

## 安装

1. 下载本仓库，确保系统已安装 FFmpeg；也可以把 `ffmpeg.exe` 放到项目目录。
2. 将项目目录添加到当前用户的 `PATH` 环境变量。
3. 重新打开 PowerShell，运行 `cimg`。

也可以不配置 PATH，直接双击 `Compress Photos.cmd` 使用。

## 最简单的用法

1. 在照片目录右键打开 PowerShell。
2. 运行 `cimg`。
3. 压缩结果会写入当前目录下的 `_compressed` 文件夹。

直接双击 `Compress Photos.cmd`，也可以选择一个目录。

如果已经把本目录添加到 PATH，可以在照片目录右键打开 PowerShell 终端，然后运行：

```powershell
cimg
```

命令使用独立启动器，会在调用 PowerShell 前解析当前目录，因此也支持 `\\服务器\共享目录` 形式的网络路径。

确认不再需要保留原图时，可以直接覆盖：

```powershell
cimg -cover
```

覆盖模式会先生成并验证临时文件，再替换原图；小于 400KB 或压缩后没有变小的图片保持不变。覆盖不可撤销，请确保原图已有备份。

命令带路径时，也可以处理其他一个或多个目录：

```powershell
cimg "D:\照片1" "E:\照片2"
```

默认行为：

- 只处理 JPG、JPEG、PNG、WebP、BMP、TIF、TIFF。
- 小于 400KB 的图片不重新编码，原样复制到输出目录。
- 最长边超过 1920 像素时才缩小，不放大小图。
- JPG/WebP 使用约 80 的质量设置；PNG/TIFF 使用无损压缩。
- 默认并行处理 4 张图片，利用 CPU 多核。
- 不修改原图，也不覆盖已经存在的输出文件。
- 如果保持原格式重新编码后反而更大，会直接复制原文件。
- 尽量保留元数据和原修改时间；FFmpeg 不保证完整保留所有厂商私有 EXIF 字段。

## 可选参数

在 PowerShell 中运行：

```powershell
.\Compress-Photos.ps1 "D:\照片1" "E:\照片2"
```

常用参数：

| 参数 | 说明 |
| --- | --- |
| `-MaxLongEdge 1920` | 最大长边；设为 `0` 表示保持分辨率 |
| `-Quality 80` | JPG/WebP 质量，范围 1～100 |
| `-MinSizeKB 400` | 小于此大小时原样复制；设为 `0` 表示全部压缩 |
| `-Parallel 4` | 并行任务数；网络目录建议 4，本地 SSD 可尝试 8 |
| `-OutputFormat same` | 保持格式；也可设为 `jpg` 或 `webp` |
| `-OutputFolderName _compressed` | 输出目录名称 |
| `-Cover` | 用压缩结果覆盖原图，不生成 `_compressed`；仅支持保持原格式 |
| `-Overwrite` | 覆盖已经存在的输出照片 |

建议首次先用默认设置，随机检查几张照片后，再考虑删除原图。不要把唯一一份原图直接覆盖掉。
