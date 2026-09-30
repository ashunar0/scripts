# 環境構築スクリプト（Windows / Rails）
# 実行方法: PowerShell を「管理者として実行」で開いて、以下を貼り付ける
#   irm https://raw.githubusercontent.com/Ashunar0/scripts/main/geek-rails/setup.ps1 | iex

# PowerShell の既定値。CI では stop になっているので、受講生の環境にそろえる
$ErrorActionPreference = 'Continue'

# カリキュラムのバージョンが変わったら、ここだけ書き換える
$RubyVersion = '3.4.10'
$RubyWingetVersion = '3.4.10-1'
$RailsVersion = '8.1.3.1'

$TotalSteps = 7

function Step($n, $title) {
  Write-Host ''
  Write-Host "==> [$n/$TotalSteps] $title" -ForegroundColor Cyan
}

function Fail($command) {
  Write-Host ''
  Write-Host "失敗しました: $command" -ForegroundColor Red
  throw "失敗しました: $command"
}

# コマンドを表示してから実行し、失敗したらそこで止める
function Run {
  $exe = $args[0]
  $rest = @($args | Select-Object -Skip 1)
  Write-Host "`$ $args" -ForegroundColor DarkGray
  & $exe @rest
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
    Run winget install --id $id -e --accept-source-agreements --accept-package-agreements
  }
}

# 拡張のサーバーが一時的にエラーを返すことがあるので、3 回までやり直す
function Install-Extension($id) {
  for ($i = 1; $i -le 3; $i++) {
    Write-Host "`$ code --install-extension $id" -ForegroundColor DarkGray
    code --install-extension $id
    if ($LASTEXITCODE -eq 0) { return }
    if ($i -lt 3) {
      Write-Host "失敗したので 10 秒後にやり直します（${i}/3）" -ForegroundColor Yellow
      Start-Sleep -Seconds 10
    }
  }
  Fail "code --install-extension $id"
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
  IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'PowerShell を「管理者として実行」で開き直してから、もう一度実行してください。' -ForegroundColor Red
  return
}

Write-Host '環境構築を開始します'

# ------------------------------------------------------------
Step 1 'winget の確認'
# ------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host 'winget が見つかりません。Microsoft Store で「アプリ インストーラー」を更新してから、もう一度実行してください。' -ForegroundColor Red
  return
}
Run winget --version

# ------------------------------------------------------------
Step 2 'Git / GitHub CLI / VSCode'
# ------------------------------------------------------------
Install-WingetPackage 'Git.Git'
Install-WingetPackage 'GitHub.cli'
Install-WingetPackage 'Microsoft.VisualStudioCode'
Update-Path

Run git --version
Run gh --version
Run code --version

# ------------------------------------------------------------
Step 3 "Ruby $RubyVersion"
# ------------------------------------------------------------
$currentRuby = if (Get-Command ruby -ErrorAction SilentlyContinue) { ruby --version } else { '' }
if ($currentRuby -like "ruby $RubyVersion *") {
  Write-Host "Ruby $RubyVersion はインストール済みのためスキップします"
} else {
  # WithDevKit: gem のビルドに使う道具（MSYS2）が一緒に入る
  Run winget install --id RubyInstallerTeam.RubyWithDevKit.3.4 -e --version $RubyWingetVersion --accept-source-agreements --accept-package-agreements
  Update-Path
}
Run ruby --version

# gem をビルドするためのコンパイラが使えるか
ridk exec gcc --version *> $null
if ($LASTEXITCODE -eq 0) {
  Write-Host 'gem をビルドする道具は準備済みのためスキップします'
} else {
  Write-Host ''
  Write-Host 'gem をビルドする道具を準備します。5〜10 分かかります。'
  Write-Host '大量の文字が流れますが、ウィンドウを閉じずに待ってください。'
  # 1: MSYS2 本体 / 3: 開発ツール（Enter だけ押したときに選ばれる組み合わせ）
  Run ridk install 1 3
}

# ------------------------------------------------------------
Step 4 "Rails $RailsVersion"
# ------------------------------------------------------------
gem list rails --installed --exact --version $RailsVersion *> $null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Rails $RailsVersion はインストール済みのためスキップします"
} else {
  Write-Host 'Rails をインストールします。数分かかります。'
  Run gem install rails --version $RailsVersion --no-document
}
Run rails --version

# ------------------------------------------------------------
Step 5 'VSCode の拡張機能と設定'
# ------------------------------------------------------------
# .erb に色を付ける（VSCode は .rb にしか色を付けない）
Install-Extension vortizhe.simple-ruby-erb
Install-Extension PKief.material-icon-theme

$settingsDir = Join-Path $env:APPDATA 'Code\User'
$settings = Join-Path $settingsDir 'settings.json'
$newSettings = @'
{
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
Step 6 'GitHub との紐付け'
# ------------------------------------------------------------
Run git config --global core.editor 'code --wait'
Run git config --global init.defaultBranch main

# CI ではブラウザでのログインができないので飛ばす
if ($env:SETUP_SKIP_GITHUB) {
  Write-Host 'SETUP_SKIP_GITHUB が指定されているため、GitHub へのログインをスキップします'
} else {
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
Step 7 '確認'
# ------------------------------------------------------------
Run git --version
Run gh --version
Run code --version
Run ruby --version
Run rails --version

Write-Host ''
Write-Host '環境構築が完了しました。' -ForegroundColor Green
Write-Host 'PowerShell を一度閉じて、開き直してから使ってください。' -ForegroundColor Green
