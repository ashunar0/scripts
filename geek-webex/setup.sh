#!/bin/bash
# 環境構築スクリプト（Mac）
# 実行方法:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Ashunar0/scripts/main/geek-webex/setup.sh)"
set -euo pipefail

LOG="$HOME/setup-log.txt"
TOTAL_STEPS=5

step() {
  printf '\n==> [%s/%s] %s\n' "$1" "$TOTAL_STEPS" "$2" | tee -a "$LOG"
}

# 出力をそのまま画面に流しつつ、ログにも残す
run() {
  echo "\$ $*" | tee -a "$LOG"
  "$@" 2>&1 | tee -a "$LOG"
}

echo "環境構築を開始します（ログ: $LOG）" | tee "$LOG"

# ------------------------------------------------------------
step 1 "Homebrew"
# ------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
  echo "インストール済みのためスキップします" | tee -a "$LOG"
else
  echo "Mac のログインパスワードを入力してください（入力中の文字は表示されません）"
  sudo -v
  run env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Apple Silicon は /opt/homebrew、Intel は /usr/local
if [ -x /opt/homebrew/bin/brew ]; then
  BREW=/opt/homebrew/bin/brew
else
  BREW=/usr/local/bin/brew
fi
eval "$("$BREW" shellenv)"

# 次回以降のターミナルでも brew が使えるように
if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
  echo "eval \"\$($BREW shellenv)\"" >> "$HOME/.zprofile"
fi

run brew --version

# ------------------------------------------------------------
step 2 "Node.js / GitHub CLI / VSCode"
# ------------------------------------------------------------
# brew install は入っていれば何もせず終わるので、スキップ判定は不要
run brew install node@24 gh
# node@24 は keg-only（PATH に出てこない）なので、明示的にリンクする
run brew link --overwrite --force node@24

# --adopt: 手動で入れた VSCode が既にあれば、それを brew の管理下に引き取る
run brew install --cask --adopt visual-studio-code

run node --version
run gh --version
run code --version

# ------------------------------------------------------------
step 3 "VSCode の拡張機能と設定"
# ------------------------------------------------------------
run code --install-extension esbenp.prettier-vscode
run code --install-extension PKief.material-icon-theme

SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
SETTINGS="$SETTINGS_DIR/settings.json"
NEW_SETTINGS="$(mktemp)"
cat > "$NEW_SETTINGS" <<'EOF'
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
EOF

mkdir -p "$SETTINGS_DIR"
if [ -f "$SETTINGS" ] && cmp -s "$NEW_SETTINGS" "$SETTINGS"; then
  echo "設定は反映済みのためスキップします" | tee -a "$LOG"
else
  # 既存の設定は消さずに退避しておく
  if [ -f "$SETTINGS" ]; then
    BACKUP="$SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"
    run cp "$SETTINGS" "$BACKUP"
  fi
  run cp "$NEW_SETTINGS" "$SETTINGS"
fi
rm -f "$NEW_SETTINGS"
run cat "$SETTINGS"

# ------------------------------------------------------------
step 4 "GitHub との紐付け"
# ------------------------------------------------------------
run git config --global core.editor "code --wait"
run git config --global init.defaultBranch main

# CI ではブラウザでのログインができないので飛ばす
if [ -n "${SETUP_SKIP_GITHUB:-}" ]; then
  echo "SETUP_SKIP_GITHUB が指定されているため、GitHub へのログインをスキップします" | tee -a "$LOG"
else
  # ログインは対話が必要なので run（tee）を通さずに直接実行する
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    echo "GitHub にはログイン済みです" | tee -a "$LOG"
  else
    echo "ブラウザで GitHub にログインします。"
    echo "画面に出る 8 桁のコードを控えて、Enter を押してください。"
    gh auth login --hostname github.com --git-protocol https --web --scopes user:email
  fi

  # メールアドレスを読む権限が無いログインだった場合は、権限を追加する
  if ! gh api user/emails >/dev/null 2>&1; then
    echo "メールアドレスを読み取る権限を追加します。もう一度ブラウザで承認してください。"
    gh auth refresh --hostname github.com --scopes user:email
  fi

  run gh auth setup-git

  GITHUB_USER="$(gh api user --jq .login)"
  GITHUB_EMAIL="$(gh api user/emails --jq '.[] | select(.primary) | .email')"

  run git config --global user.name "$GITHUB_USER"
  run git config --global user.email "$GITHUB_EMAIL"
fi

# ------------------------------------------------------------
step 5 "確認"
# ------------------------------------------------------------
run git --version
run node --version
run npm --version
run code --version
run gh --version

printf '\n環境構築が完了しました。\n' | tee -a "$LOG"
echo "うまくいかなかった場合は、$LOG をメンターに送ってください。" | tee -a "$LOG"
