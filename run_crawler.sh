#!/usr/bin/env zsh
[[ -f ~/.zshrc ]] && source ~/.zshrc

PROJECT_DIR="/home/KO300/ELIXIR/canvas_crawler"
LOG_FILE="$PROJECT_DIR/crawler.log"

cd "$PROJECT_DIR" || exit 1

echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Starting CanvasCrawler OTP service..." >> "$LOG_FILE"

while true; do
  mix run --no-halt >> "$LOG_FILE" 2>&1
  EXIT_CODE=$?
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Service exited with code $EXIT_CODE. Restarting in 5s..." >> "$LOG_FILE"
  sleep 5
done
