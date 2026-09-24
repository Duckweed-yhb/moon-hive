# ============================================================
# MoonHive 构建助手
#
# 为什么需要这个脚本：
#   本项目依赖 C FFI，走 native 后端。在 Windows 上，native 后端会调用
#   GNU assembler，而**汇编器无法处理含非 ASCII 字符的路径**。若仓库位于
#   中文目录下（例如 E:\future\yhb\03-竞赛\moon-hive），直接 `moon build`
#   会失败：
#       Fatal error: can't create E:\future\yhb\03-????\...: No such file or directory
#
#   本脚本把构建产物重定向到一个纯 ASCII 的目录，从而绕过该限制。
#   这不改变任何源码，只改产物落盘位置。
#
# 用法：
#   ./build.ps1                   构建（release + native）
#   ./build.ps1 -Test             构建后跑测试
#   ./build.ps1 -Run doctor       构建后运行 moonhive 子命令
#   ./build.ps1 -Clean            先清理构建目录
#   ./build.ps1 -TargetDir D:\mb  指定产物目录（必须是纯 ASCII 路径）
# ============================================================

param(
  [switch]$Test,
  [switch]$Clean,
  [string]$TargetDir = "",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Run = @()
)

$ErrorActionPreference = "Stop"

# 定位仓库根（本脚本所在目录）
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

# 产物目录：默认放在系统临时目录下（保证纯 ASCII 且必定可写）
if (-not $TargetDir) {
  $TargetDir = Join-Path $env:TEMP "moonhive-build"
}

Write-Host "仓库根目录   : $root"
Write-Host "产物目录     : $TargetDir"
Write-Host ""

# 路径必须是纯 ASCII，否则汇编器仍会失败——这里提前给出明确提示
if ($TargetDir -match '[^\x00-\x7F]') {
  Write-Host "产物目录包含非 ASCII 字符，GNU assembler 无法处理。" -ForegroundColor Red
  Write-Host "请用 -TargetDir 指定一个纯 ASCII 路径。" -ForegroundColor Red
  exit 1
}

if ($Clean) {
  if (Test-Path $TargetDir) {
    Remove-Item -Recurse -Force $TargetDir
    Write-Host "已清理产物目录。" -ForegroundColor Yellow
  }
}

$moon = "moon"
if (-not (Get-Command moon -ErrorAction SilentlyContinue)) {
  $candidate = Join-Path $env:USERPROFILE ".moon\bin\moon.exe"
  if (Test-Path $candidate) {
    $moon = $candidate
  } else {
    Write-Host "找不到 moon 可执行文件，请先安装 MoonBit 工具链。" -ForegroundColor Red
    exit 1
  }
}

# 外部命令的非零退出不会自动触发 ErrorActionPreference，必须显式检查。
# 另外：MoonBit 工具链会把 GCC 的编译警告写到 stderr，若此时
# $ErrorActionPreference 为 Stop，PowerShell 会把这段 stderr 当成终止错误
# 从而中断脚本——因此这里临时切到 Continue，只用退出码判断成败。
function Invoke-Moon {
  param([string]$Label, [string[]]$MoonArgs)
  Write-Host "==> $Label" -ForegroundColor Cyan
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $moon @MoonArgs
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prev
  }
  if ($code -ne 0) {
    Write-Host "失败：$Label（退出码 $code）" -ForegroundColor Red
    exit $code
  }
}

Push-Location $root
try {
  Invoke-Moon "moon build --target native --release" @(
    "build", "--target", "native", "--release", "--target-dir", "$TargetDir"
  )

  if ($Test) {
    Write-Host ""
    Invoke-Moon "moon test --target native" @(
      "test", "--target", "native", "--target-dir", "$TargetDir"
    )
  }

  if ($Run.Count -gt 0) {
    Write-Host ""
    $runArgs = @("run", "cmd/moonhive", "--target", "native", "--target-dir", "$TargetDir", "--") + $Run
    Invoke-Moon "moonhive $($Run -join ' ')" $runArgs
  }

  Write-Host ""
  Write-Host "完成。" -ForegroundColor Green
  $exe = Join-Path $TargetDir "native\release\build\cmd\moonhive\moonhive.exe"
  if (Test-Path $exe) {
    Write-Host "可执行文件   : $exe"
  }
} finally {
  Pop-Location
}
