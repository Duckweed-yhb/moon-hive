# ============================================================
# MoonHive 每日项目投喂 - 数据管道脚本（参数化版）
# 职责：拉取 GitHub 项目 → (可选筛选) → digest 展示 → 输入编号收藏 → 保存 favorites.json → 可导出 Markdown
#
# 用法示例：
#   powershell -ExecutionPolicy Bypass -File daily.ps1                    # 默认：moonbit 最新更新 5 个
#   powershell -ExecutionPolicy Bypass -File daily.ps1 -Sort stars        # 按星数排序看
#   powershell -ExecutionPolicy Bypass -File daily.ps1 -Count 10          # 一次看 10 个
#   powershell -ExecutionPolicy Bypass -File daily.ps1 -Lang JS -Min 10   # 只看 JS 且 >=10 星
#   powershell -ExecutionPolicy Bypass -File daily.ps1 -Kw async -Export  # 关键词筛选 + 一键导出
#
# 参数说明：
#   -Query     GitHub 搜索条件（默认 language:moonbit）
#   -Count     推荐数量（默认 5）
#   -Sort      digest 排序：score(打分) / stars(星数) / updated(最新) / none(不排序)，默认 updated
#   -Lang      语言筛选（默认空 = 不过滤）
#   -Min       最低星数（默认 0 = 不限）
#   -Max       最高星数（默认 0 = 不限）
#   -Kw        关键词筛选，匹配名称或描述（默认空 = 不过滤）
#   -Export    一键导出 Markdown（加此开关跳过交互询问）
# ============================================================

param(
  [string]$Query = "language:moonbit",
  [int]$Count = 5,
  [ValidateSet("score", "stars", "updated", "none")]
  [string]$Sort = "updated",
  [string]$Lang = "",
  [int]$Min = 0,
  [int]$Max = 0,
  [string]$Kw = "",
  [switch]$Export
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# ---------- 文件 ----------
$FavFile = Join-Path $PSScriptRoot "favorites.json"   # 收藏数据
$MdFile  = Join-Path $PSScriptRoot "favorites.md"     # 导出的 Markdown

# ---------- 定位 moon 可执行文件 ----------
$moon = "moon"
if (-not (Get-Command moon -ErrorAction SilentlyContinue)) {
  $moon = Join-Path $env:USERPROFILE ".moon\bin\moon.exe"
}

# GitHub API 的 sort 只支持 stars/updated，score/none 时退回 updated
$apiSort = if ($Sort -in @("stars", "updated")) { $Sort } else { "updated" }

# 是否启用筛选
$hasFilter = [bool]($Lang -or $Min -gt 0 -or $Max -gt 0 -or $Kw)

Write-Host ""
Write-Host "================ MoonHive 每日项目投喂 ================" -ForegroundColor Cyan
$headline = "搜索: $Query | 数量: $Count | 排序: $Sort"
if ($hasFilter) { $headline += " | 筛选: $Lang $Min-$Max $Kw" }
Write-Host $headline
Write-Host "正在从 GitHub 拉取项目..." -ForegroundColor Yellow

# ---------- 1. 拉取 GitHub API ----------
$url = "https://api.github.com/search/repositories?q=$Query&sort=$apiSort&order=desc&per_page=$Count"
$resp = curl.exe -s -m 30 $url | Out-String
if (-not $resp -or $resp -match '"message"') {
  Write-Host "拉取失败：GitHub API 无响应或被限流（匿名限流 60 次/小时）" -ForegroundColor Red
  exit 1
}
$data = $resp | ConvertFrom-Json
if (-not $data.items -or $data.items.Count -eq 0) {
  Write-Host "没有找到符合条件的项目，试试改 -Query 参数" -ForegroundColor Red
  exit 1
}

# ---------- 2. 精简字段 ----------
$slim = $data.items | ForEach-Object {
  [PSCustomObject]@{
    name             = $_.name
    description      = $_.description
    html_url         = $_.html_url
    stargazers_count = $_.stargazers_count
    language         = $_.language
    updated_at       = $_.updated_at
  }
}

# ---------- 3. Base64 编码（规避命令行引号/空格问题） ----------
$json = $slim | ConvertTo-Json -Compress -Depth 3
$b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))

# ---------- 3.5 可选筛选透传（filter 子命令，--json 输出纯 JSON 供重新编码） ----------
if ($hasFilter) {
  $filterArgs = @("run", "cmd/main", "--", "daily", "filter", $b64, "--json")
  if ($Lang) { $filterArgs += @("--lang", $Lang) }
  if ($Min -gt 0) { $filterArgs += @("--min", "$Min") }
  if ($Max -gt 0) { $filterArgs += @("--max", "$Max") }
  if ($Kw) { $filterArgs += @("--kw", $Kw) }
  $filtered = (& $moon $filterArgs) -join "`n"
  try {
    $parsed = $filtered | ConvertFrom-Json
    $filteredJson = @($parsed)
  } catch {
    Write-Host "筛选输出解析失败：$filtered" -ForegroundColor Red
    exit 1
  }
  if ($filteredJson.Count -gt 0) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($filtered))
    Write-Host ("筛选后剩 {0} 个项目" -f $filteredJson.Count) -ForegroundColor Yellow
  } else {
    Write-Host "筛选后没有符合条件的结果" -ForegroundColor Red
    exit 1
  }
}

# ---------- 4. 展示推荐卡片（透传 --sort，score 是默认不打 --sort） ----------
Write-Host ""
$digestArgs = @("run", "cmd/main", "--", "daily", "digest", $b64)
if ($Sort -ne "score") { $digestArgs += @("--sort", $Sort) }
& $moon $digestArgs

# ---------- 5. 收藏：输入编号 ----------
Write-Host ""
$keepIds = Read-Host "要保留哪些项目？(输入编号如 1,3，回车跳过)"
if ($keepIds) {
  # 旧收藏（若存在）转 base64
  $oldB64 = ""
  if (Test-Path $FavFile) {
    $oldRaw = Get-Content $FavFile -Raw -Encoding UTF8
    if ($oldRaw) { $oldB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($oldRaw)) }
  }
  $result = (& $moon run cmd/main -- daily keep $b64 $keepIds $oldB64) -join "`n"
  if ($result.StartsWith("[")) {
    [System.IO.File]::WriteAllText($FavFile, $result, (New-Object System.Text.UTF8Encoding $true))
    $favCount = ($result | ConvertFrom-Json).Count
    Write-Host "已保存收藏：$favCount 个项目 → $FavFile" -ForegroundColor Green

    # 6. 可选导出 Markdown（-Export 开关跳过询问）
    $exportAns = "n"
    if ($Export) { $exportAns = "y" } else { $exportAns = Read-Host "导出 Markdown 清单？(y/n，默认 n)" }
    if ($exportAns -eq "y") {
      $md = (& $moon run cmd/main -- daily export $oldB64) -join "`n"
      # 若 export 收到的是最新收藏（含新增），用最新结果再导一次
      if (-not $md.StartsWith("#")) {
        $newB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($result))
        $md = (& $moon run cmd/main -- daily export $newB64) -join "`n"
      }
      [System.IO.File]::WriteAllText($MdFile, $md, (New-Object System.Text.UTF8Encoding $true))
      Write-Host "已导出 → $MdFile" -ForegroundColor Green
    }
  } else {
    Write-Host $result -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "完成。想看热门？daily.ps1 -Sort stars；想筛选？daily.ps1 -Lang JS -Min 10" -ForegroundColor DarkGray
