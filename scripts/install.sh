#!/usr/bin/env bash
set -Eeuo pipefail
REPO_URL=${REPO_URL:-https://github.com/qingan123/sub2api.git}
APP_DIR=${APP_DIR:-/opt/sub2api}
PORT=${SUB2API_PORT:-8080}
fail(){ echo "ERROR: $*" >&2; exit 1; }
read_tty(){ local v; IFS= read -r -p "$1" v </dev/tty || fail '需要交互终端'; printf '%s' "$v"; }
read_secret(){ local v; IFS= read -r -s -p "$1" v </dev/tty || fail '需要交互终端'; printf '\n' >/dev/tty; printf '%s' "$v"; }
[[ $EUID -eq 0 ]] || fail '请使用root/sudo'
command -v git >/dev/null || fail '缺少git'; command -v docker >/dev/null || fail '缺少docker'; docker compose version >/dev/null || fail '需要Docker Compose v2'
APP_DIR=$(read_tty "部署目录 [$APP_DIR]: "); APP_DIR=${APP_DIR:-/opt/sub2api}
PORT=$(read_tty "端口 [$PORT]: "); PORT=${PORT:-8080}
[[ $PORT =~ ^[0-9]+$ && $PORT -ge 1 && $PORT -le 65535 ]] || fail '端口无效'
if command -v ss >/dev/null && ss -ltn "sport = :$PORT" | grep -q LISTEN; then fail "端口 $PORT 已被占用"; fi
admin=$(read_tty '管理员邮箱: '); [[ -n "$admin" ]] || fail '管理员邮箱不能为空'
pass=$(read_secret '管理员密码: '); confirm=$(read_secret '确认管理员密码: '); [[ "$pass" == "$confirm" ]] || fail '密码不一致'; [[ ${#pass} -ge 6 ]] || fail '密码至少6位'
mkdir -p "$APP_DIR"; [[ -z "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail '目标目录非空'
git clone --depth 1 --branch main "$REPO_URL" "$APP_DIR"
cd "$APP_DIR/deploy"; cp .env.example .env; mkdir -p data postgres_data redis_data
python3 - "$PORT" "$admin" "$pass" <<'PY'
from pathlib import Path
import secrets,sys
p=Path('.env'); lines=p.read_text().splitlines(); vals={'SERVER_PORT':sys.argv[1],'BIND_HOST':'0.0.0.0','ADMIN_EMAIL':sys.argv[2],'ADMIN_PASSWORD':sys.argv[3],'POSTGRES_PASSWORD':secrets.token_hex(32),'JWT_SECRET':secrets.token_hex(32),'TOTP_ENCRYPTION_KEY':secrets.token_hex(32)}
out=[]; seen=set()
for line in lines:
 key=line.split('=',1)[0] if '=' in line and not line.lstrip().startswith('#') else None
 if key in vals: out.append(f'{key}={vals[key]}'); seen.add(key)
 else: out.append(line)
for key,val in vals.items():
 if key not in seen: out.append(f'{key}={val}')
p.write_text('\n'.join(out)+'\n')
PY
unset pass confirm; chmod 600 .env; chmod 700 data postgres_data redis_data
docker compose -f docker-compose.local.yml --env-file .env up -d --pull always
for _ in {1..90}; do curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null && break; sleep 1; done
curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null || { docker compose -f docker-compose.local.yml logs --tail=100; exit 1; }
public_ip="${PUBLIC_HOST:-$(curl -4fsS --max-time 5 https://api.ipify.org || true)}"
if [[ -n "$public_ip" ]]; then
  public_url="http://${public_ip}:${PORT}"
  api_url="${public_url}/v1"
else
  public_url='公网IP探测失败，请检查安全组/UFW'
  api_url='公网IP探测失败，暂无法生成公网 API Base URL'
fi
printf '\n部署完成。\n公网地址: %s\n本机地址: http://127.0.0.1:%s\nAPI Base URL: %s\n端口: %s（绑定 0.0.0.0）\n目录: %s\n请确认云安全组/UFW已放行该端口。\n' "$public_url" "$PORT" "$api_url" "$PORT" "$APP_DIR"
