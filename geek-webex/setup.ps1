# 環境構築スクリプト（Windows）
# 実行方法: PowerShell を「管理者として実行」で開いて、以下を貼り付ける
#   irm https://raw.githubusercontent.com/Ashunar0/scripts/main/geek-webex/setup.ps1 | iex

# 標準エラーに出た警告をエラーとして扱わないように（PowerShell の既定値。CI では stop になっているので戻す）
$ErrorActionPreference = 'Continue'

# 外部コマンドの UTF-8 出力が文字化けしないように
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Log = Join-Path $HOME 'setup-log.txt'
$TotalSteps = 5

function Step($n, $title) {
  Write-Host ''
  Write-Host "==> [$n/$TotalSteps] $title" -ForegroundColor Cyan
}

function Fail($command) {
  Write-Host ''
  Write-Host "失敗しました（終了コード: ${LASTEXITCODE}）" -ForegroundColor Red
  Write-Host "${Log} をメンターに送ってください。" -ForegroundColor Red
  Stop-Transcript | Out-Null
  throw "失敗したコマンド: $command"
}

# コマンドを表示してから実行し、失敗したらそこで止める。
# 2>&1 で標準エラーもまとめて流し、ログ（Start-Transcript）に残す
function Run {
  $exe = $args[0]
  $rest = @($args | Select-Object -Skip 1)
  Write-Host "`$ $args" -ForegroundColor DarkGray
  & $exe @rest 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) { Fail "$args" }
}

# インストール直後のコマンドを、このウィンドウでもすぐ使えるようにする
function Update-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-WingetPackage($id) {
  winget list --id $id -e --accept-source-agreements *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "$id はインストール済みのためスキップします"
  } else {
    # 進捗表示が崩れるので、winget だけはパイプを通さずに直接実行する
    Write-Host "`$ winget install --id $id" -ForegroundColor DarkGray
    winget install --id $id -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { Fail "winget install --id $id" }
  }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
  IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'PowerShell を「管理者として実行」で開き直してから、もう一度実行してください。' -ForegroundColor Red
  return
}

Start-Transcript -Path $Log | Out-Null
Write-Host "環境構築を開始します（ログ: ${Log}）"

# ------------------------------------------------------------
Step 1 'winget の確認'
# ------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host 'winget が見つかりません。Microsoft Store で「アプリ インストーラー」を更新してから、もう一度実行してください。' -ForegroundColor Red
  Stop-Transcript | Out-Null
  return
}
Run winget --version

# npm などの .ps1 形式のコマンドが PowerShell で動くように
try {
  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
} catch {
  Write-Host "実行ポリシーを変更できませんでした（続行します）: $_" -ForegroundColor Yellow
}

# ------------------------------------------------------------
Step 2 'Git / Node.js / GitHub CLI / VSCode'
# ------------------------------------------------------------
Install-WingetPackage 'Git.Git'
Install-WingetPackage 'OpenJS.NodeJS.LTS'
Install-WingetPackage 'GitHub.cli'
Install-WingetPackage 'Microsoft.VisualStudioCode'
Update-Path

Run git --version
Run node --version
Run gh --version
Run code --version

# ------------------------------------------------------------
Step 3 'VSCode の拡張機能と設定'
# ------------------------------------------------------------
Run code --install-extension esbenp.prettier-vscode
Run code --install-extension PKief.material-icon-theme

$settingsDir = Join-Path $env:APPDATA 'Code\User'
$settings = Join-Path $settingsDir 'settings.json'
$newSettings = @'
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "workbench.iconTheme": "material-icon-theme",
  "files.eol": "\n",
  "files.insertFinalNewline": true,
  "files.trimTrailingWhitespace": true,
  "editor.renderWhitespace": "boundary",
  "explorer.compactFolders": false
}
'@

New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
if ((Test-Path $settings) -and ([IO.File]::ReadAllText($settings) -eq $newSettings)) {
  Write-Host '設定は反映済みのためスキップします'
} else {
  # 既存の設定は消さずに退避しておく
  if (Test-Path $settings) {
    $backup = "$settings.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $settings $backup
    Write-Host "既存の設定を退避しました: $backup"
  }
  # BOM なしの UTF-8 で書き込む
  [IO.File]::WriteAllText($settings, $newSettings)
}
Get-Content $settings

# ------------------------------------------------------------
Step 4 'GitHub との紐付け'
# ------------------------------------------------------------
Run git config --global core.editor 'code --wait'
Run git config --global init.defaultBranch main

# CI ではブラウザでのログインができないので飛ばす
if ($env:SETUP_SKIP_GITHUB) {
  Write-Host 'SETUP_SKIP_GITHUB が指定されているため、GitHub へのログインをスキップします'
} else {
  # ログインは対話が必要なので Run を通さずに直接実行する
  gh auth status --hostname github.com *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'GitHub にはログイン済みです'
  } else {
    Write-Host 'ブラウザで GitHub にログインします。'
    Write-Host '画面に出る 8 桁のコードを控えて、Enter を押してください。'
    gh auth login --hostname github.com --git-protocol https --web --scopes user:email
  }

  # メールアドレスを読む権限が無いログインだった場合は、権限を追加する
  gh api user/emails *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'メールアドレスを読み取る権限を追加します。もう一度ブラウザで承認してください。'
    gh auth refresh --hostname github.com --scopes user:email
  }

  Run gh auth setup-git

  $githubUser = gh api user --jq .login
  $githubEmail = gh api user/emails --jq '.[] | select(.primary) | .email'

  Run git config --global user.name $githubUser
  Run git config --global user.email $githubEmail
}

# ------------------------------------------------------------
Step 5 '確認'
# ------------------------------------------------------------
Run git --version
Run node --version
Run npm --version
Run code --version
Run gh --version

Write-Host ''
Write-Host '環境構築が完了しました。' -ForegroundColor Green
Write-Host "うまくいかなかった場合は、$Log をメンターに送ってください。"
Stop-Transcript | Out-Null
