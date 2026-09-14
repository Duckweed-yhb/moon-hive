# ============================================================
# MoonHive 每日项目投喂 - 数据管道脚本
# 职责：拉取 GitHub 项目 → digest 展示 → 输入编号收藏 → 保存 favorites.json → 可导出 Markdown
# 用法：双击运行，或: powershell -ExecutionPolicy Bypass -File daily.ps1
# ============================================================

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# ---------- 配置区（可按需修改） ----------
$Query = "language:moonbit"   # GitHub 搜索条件（默认只看 MoonBit 项目）
$Count = 5                    # 每天推荐几个项目
$Sort  = "updated"            # 排序方式: updated(最新更新) / stars(最多星)

# ---------- 文件 ----------
$FavFile = Join-Path $PSScriptRoot "favorites.json"   # 收藏数据
$MdFile  = Join-Path $PSScriptRoot "favorites.md"     # 导出的 Markdown

# ---------- 定位 moon 可执行文件 ----------
$moon = "moon"
if (-not (Get-Command moon -ErrorAction SilentlyContinue)) {
  $moon = Join-Path $env:USERPROFILE ".moon\bin\moon.exe"
}

Write-Host ""
Write-Host "================ MoonHive 每日项目投喂 ================" -ForegroundColor Cyan
Write-Host "搜索条件: $Query | 数量: $Count | 排序: $Sort"
Write-Host "正在从 GitHub 拉取项目..." -ForegroundColor Yellow

# ---------- 1. 拉取 GitHub API ----------
$url = "https://api.github.com/search/repositories?q=$Query&sort=$Sort&order=desc&per_page=$Count"
$resp = curl.exe -s -m 30 $url | Out-String
if (-not $resp -or $resp -match '"message"') {
  Write-Host "拉取失败：GitHub API 无响应或被限流（匿名限流 60 次/小时）" -ForegroundColor Red
  exit 1
}
$data = $resp | ConvertFrom-Json
if (-not $data.items -or $data.items.Count -eq 0) {
  Write-Host "没有找到符合条件的项目，试试修改配置区的 Query" -ForegroundColor Red
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

# ---------- 4. 展示推荐卡片 ----------
Write-Host ""
& $moon run cmd/main -- daily digest $b64

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

    # 6. 可选导出 Markdown
    $exportAns = Read-Host "导出 Markdown 清单？(y/n，默认 n)"
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
Write-Host "完成。想看更多？改配置区 Sort = stars 重新运行即可" -ForegroundColor DarkGray
