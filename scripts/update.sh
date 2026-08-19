#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR=${APP_DIR:-}; PORT=${SUB2API_PORT:-}
fail(){ echo "ERROR: $*" >&2; exit 1; }
find_rows(){
  local d p v
  for deploy in /opt/*/deploy /root/*/deploy; do
    [[ -f "$deploy/docker-compose.local.yml" && -f "$deploy/.env" ]] || continue
    grep -q 'sub2api' "$deploy/docker-compose.local.yml" || continue
    d=${deploy%/deploy}; p=$(awk -F= '$1=="SERVER_PORT"{print $2;exit}' "$deploy/.env" 2>/dev/null || true); v=$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo unknown); printf 'sub2api\t%s\t%s\t%s\n' "${p:-unknown}" "$v" "$d"
  done
}
if [[ -z "$APP_DIR" ]]; then
  [[ -t 0 ]] || fail '非交互模式请设置APP_DIR和SUB2API_PORT'
  mapfile -t rows < <(find_rows); ((${#rows[@]})) || fail '未发现Sub2API实例'
  echo '编号 项目名称 端口 当前版本 项目目录'
  printf '%s\n' "${rows[@]}" | awk -F '\t' '{printf "%d) %s %s %s %s\n",NR,$1,$2,$3,$4}'
  read -r -p '选择编号或端口: ' choice </dev/tty
  row=$(printf '%s\n' "${rows[@]}" | awk -F '\t' -v c="$choice" 'NR==c||$2==c{print;exit}'); [[ -n "$row" ]] || fail '未选择实例'; PORT=$(printf '%s' "$row"|cut -f2); APP_DIR=$(printf '%s' "$row"|cut -f4)
fi
[[ -d "$APP_DIR/.git" ]] || fail '目标不是Git仓库'; cd "$APP_DIR"; [[ -z "$(git status --porcelain)" ]] || fail '工作树有未提交修改'
deploy="$APP_DIR/deploy"; backup="$APP_DIR/backups/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$backup"; cp -a "$deploy/.env" "$backup/.env"; tar -C "$deploy" -czf "$backup/data.tar.gz" data postgres_data redis_data 2>/dev/null || true
git fetch origin main; git reset --hard origin/main; cd "$deploy"; docker compose -f docker-compose.local.yml --env-file .env up -d --pull always; PORT=${PORT:-$(awk -F= '$1=="SERVER_PORT"{print $2;exit}' .env)}
for _ in {1..90}; do curl -fsS "http://127.0.0.1:${PORT:-8080}/health" >/dev/null && exit 0; sleep 1; done
docker compose -f docker-compose.local.yml logs --tail=100; exit 1
