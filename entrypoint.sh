#!/usr/bin/env bash
# Xray (VLESS + VMess + Trojan روی WebSocket، همه روی یک پورت) با به‌روزرسانی خودکار
set -u

XRAY_DIR="${XRAY_DIR:-/opt/xray}"
WWW_DIR="${WWW_DIR:-/www}"
CONF="${CONF:-/tmp/xray-config.json}"
GITHUB_BASE="${GITHUB_BASE:-https://github.com}"
XRAY_VERSION="${XRAY_VERSION:-latest}"             # latest یا یک نسخه‌ی مشخص مثل v25.1.1
UPDATE_INTERVAL_HOURS="${UPDATE_INTERVAL_HOURS:-24}"
LISTEN_PORT="${PORT:-8080}"
PORT_VL=18001; PORT_VM=18002; PORT_TR=18003; PORT_WEB=18080
PORT_VLH=18004; PORT_VMH=18005; PORT_TRH=18006; PORT_SS=18007

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ---------- نصب و به‌روزرسانی Xray ----------
resolve_tag() {
  if [[ "$XRAY_VERSION" != "latest" ]]; then echo "$XRAY_VERSION"; return; fi
  curl -fsSIL -o /dev/null -w '%{url_effective}' "$GITHUB_BASE/XTLS/Xray-core/releases/latest" | sed 's#.*/tag/##'
}
asset_name() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "Xray-linux-64.zip" ;;
    aarch64|arm64) echo "Xray-linux-arm64-v8a.zip" ;;
    *) echo "Xray-linux-64.zip" ;;
  esac
}
installed_tag() { cat "$XRAY_DIR/VERSION" 2>/dev/null || echo none; }

install_xray() {   # install_xray <tag>
  local tag="$1" asset url tmp want got
  asset="$(asset_name)"
  url="$GITHUB_BASE/XTLS/Xray-core/releases/download/$tag/$asset"
  tmp="$(mktemp -d)"
  log "دانلود Xray $tag ..."
  curl -fsSL --retry 3 "$url" -o "$tmp/x.zip" || { log "دانلود ناموفق"; rm -rf "$tmp"; return 1; }
  if [[ "${SKIP_VERIFY:-0}" != "1" ]]; then
    curl -fsSL --retry 3 "$url.dgst" -o "$tmp/x.dgst" || { log "فایل hash دانلود نشد"; rm -rf "$tmp"; return 1; }
    want="$(grep -i '256' "$tmp/x.dgst" | grep -oE '[0-9a-fA-F]{64}' | head -1 | tr 'A-F' 'a-f')"
    got="$(sha256sum "$tmp/x.zip" | cut -d' ' -f1)"
    if [[ -z "$want" || "$want" != "$got" ]]; then log "بررسی hash ناموفق؛ نصب لغو شد"; rm -rf "$tmp"; return 1; fi
  fi
  unzip -qo "$tmp/x.zip" -d "$tmp/out" || { rm -rf "$tmp"; return 1; }
  chmod +x "$tmp/out/xray"
  "$tmp/out/xray" version >/dev/null 2>&1 || { log "فایل xray اجرا نشد"; rm -rf "$tmp"; return 1; }
  if [[ -f "$CONF" ]]; then
    XRAY_LOCATION_ASSET="$tmp/out" "$tmp/out/xray" run -test -c "$CONF" >/dev/null 2>&1 \
      || { log "نسخه‌ی جدید با کانفیگ فعلی سازگار نیست؛ نصب لغو شد"; rm -rf "$tmp"; return 1; }
  fi
  mkdir -p "$XRAY_DIR"
  cp -f "$tmp/out/xray" "$XRAY_DIR/xray.new" && mv -f "$XRAY_DIR/xray.new" "$XRAY_DIR/xray"
  for f in geoip.dat geosite.dat; do [[ -f "$tmp/out/$f" ]] && cp -f "$tmp/out/$f" "$XRAY_DIR/$f"; done
  echo "$tag" > "$XRAY_DIR/VERSION"
  rm -rf "$tmp"
  log "Xray $tag نصب شد"
}

# ---------- ساخت کانفیگ ----------
sha_slice() { printf %s "$1" | sha256sum | cut -c"$2"; }

# gen_config full|basic  (basic = فقط سه کانفیگ WS)
gen_config() {
  MODE="${1:-full}"
  P="${PATH_PREFIX:-$(sha_slice "$UUID" 1-12)}"
  PATH_VL="/$P/vl"; PATH_VM="/$P/vm"; PATH_TR="/$P/tr"
  PATH_VLH="/$P/vlh"; PATH_VMH="/$P/vmh"; PATH_TRH="/$P/trh"; PATH_SS="/$P/ss"
  SS_METHOD="chacha20-ietf-poly1305"; SS_PASS="${SS_PASSWORD:-$UUID}"
  # لاگ دسترسی (آی‌پی کاربر و مقصدها) به‌صورت پیش‌فرض خاموش است؛ برای عیب‌یابی ACCESS_LOG=1 بگذارید
  local logacc='"access": "none", '
  [[ "${ACCESS_LOG:-0}" == "1" ]] && logacc=''
  local extra_fb="" extra_in=""
  if [[ "$MODE" == "full" ]]; then
    read -r -d '' extra_fb <<EOF2
          { "path": "$PATH_VLH", "dest": "127.0.0.1:$PORT_VLH" },
          { "path": "$PATH_VMH", "dest": "127.0.0.1:$PORT_VMH" },
          { "path": "$PATH_TRH", "dest": "127.0.0.1:$PORT_TRH" },
          { "path": "$PATH_SS", "dest": "127.0.0.1:$PORT_SS" },
EOF2
    read -r -d '' extra_in <<EOF2
,
    {
      "tag": "vless-hu", "listen": "127.0.0.1", "port": $PORT_VLH, "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID" } ], "decryption": "none" },
      "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "$PATH_VLH" } }
    },
    {
      "tag": "vmess-hu", "listen": "127.0.0.1", "port": $PORT_VMH, "protocol": "vmess",
      "settings": { "clients": [ { "id": "$UUID" } ] },
      "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "$PATH_VMH" } }
    },
    {
      "tag": "trojan-hu", "listen": "127.0.0.1", "port": $PORT_TRH, "protocol": "trojan",
      "settings": { "clients": [ { "password": "${TROJAN_PASSWORD:-$UUID}" } ] },
      "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "$PATH_TRH" } }
    },
    {
      "tag": "ss-ws", "listen": "127.0.0.1", "port": $PORT_SS, "protocol": "shadowsocks",
      "settings": { "method": "$SS_METHOD", "password": "$SS_PASS", "network": "tcp,udp" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_SS" } }
    }
EOF2
  fi
  DUMMY="$(sha_slice "dummy-$UUID" 1-32 | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-\3-\4-\5/')"
  cat > "$CONF" <<JSON
{
  "log": { ${logacc}"loglevel": "warning" },
  "inbounds": [
    {
      "tag": "entry", "listen": "0.0.0.0", "port": $LISTEN_PORT, "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$DUMMY" } ],
        "decryption": "none",
        "fallbacks": [
          { "path": "$PATH_VL", "dest": "127.0.0.1:$PORT_VL" },
          { "path": "$PATH_VM", "dest": "127.0.0.1:$PORT_VM" },
          { "path": "$PATH_TR", "dest": "127.0.0.1:$PORT_TR" },
$extra_fb
          { "dest": "127.0.0.1:$PORT_WEB" }
        ]
      },
      "streamSettings": { "network": "tcp", "security": "none" }
    },
    {
      "tag": "vless-ws", "listen": "127.0.0.1", "port": $PORT_VL, "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID" } ], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_VL" } }
    },
    {
      "tag": "vmess-ws", "listen": "127.0.0.1", "port": $PORT_VM, "protocol": "vmess",
      "settings": { "clients": [ { "id": "$UUID" } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_VM" } }
    },
    {
      "tag": "trojan-ws", "listen": "127.0.0.1", "port": $PORT_TR, "protocol": "trojan",
      "settings": { "clients": [ { "password": "${TROJAN_PASSWORD:-$UUID}" } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_TR" } }
    }$extra_in
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "rules": [ { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" } ]
  }
}
JSON
}

# ---------- کانفیگ از راه دور (اختیاری) ----------
# CONFIG_URL: آدرس یک فایل JSON کامل Xray. جانگهدارهای __PORT__ و __UUID__ جایگزین می‌شوند.
fetch_remote_config() {
  [[ -z "${CONFIG_URL:-}" ]] && return 1
  local tmp; tmp="$(mktemp)"
  curl -fsSL --retry 2 "$CONFIG_URL" -o "$tmp" || { rm -f "$tmp"; return 1; }
  sed -i "s/__PORT__/$LISTEN_PORT/g; s/__UUID__/$UUID/g" "$tmp"
  if ! XRAY_LOCATION_ASSET="$XRAY_DIR" "$XRAY_DIR/xray" run -test -c "$tmp" >/dev/null 2>&1; then
    log "کانفیگ دریافتی معتبر نیست؛ نادیده گرفته شد"; rm -f "$tmp"; return 1
  fi
  if [[ -f "$CONF" ]] && cmp -s "$tmp" "$CONF"; then rm -f "$tmp"; return 1; fi
  mv -f "$tmp" "$CONF"; log "کانفیگ جدید از CONFIG_URL اعمال شد"; return 0
}

# ---------- لینک‌های اشتراک ----------
b64() { base64 | tr -d '\n'; }
gen_links() {
  HOST="${PUBLIC_HOST:-${RENDER_EXTERNAL_HOSTNAME:-${RAILWAY_PUBLIC_DOMAIN:-${KOYEB_PUBLIC_DOMAIN:-}}}}"
  NAME="${NODE_NAME:-xray}"
  [[ -z "$HOST" ]] && { log "PUBLIC_HOST تنظیم نشده؛ لینک اشتراک ساخته نشد"; return; }
  local q="security=tls&sni=$HOST&alpn=http%2F1.1&fp=chrome&type=ws&host=$HOST"
  local vl="vless://$UUID@$HOST:443?encryption=none&$q&path=$(printf %s "$PATH_VL" | sed 's#/#%2F#g')#$NAME-vless"
  local tr="trojan://${TROJAN_PASSWORD:-$UUID}@$HOST:443?$q&path=$(printf %s "$PATH_TR" | sed 's#/#%2F#g')#$NAME-trojan"
  local vmj
  vmj="{\"v\":\"2\",\"ps\":\"$NAME-vmess\",\"add\":\"$HOST\",\"port\":\"443\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$HOST\",\"path\":\"$PATH_VM\",\"tls\":\"tls\",\"sni\":\"$HOST\",\"alpn\":\"http/1.1\",\"fp\":\"chrome\"}"
  local vm="vmess://$(printf %s "$vmj" | b64)"
  local all="$vl"$'\n'"$vm"$'\n'"$tr"
  if [[ "${MODE:-full}" == "full" ]]; then
    local qh="security=tls&sni=$HOST&alpn=http%2F1.1&fp=chrome&type=httpupgrade&host=$HOST"
    local enc; enc() { printf %s "$1" | sed 's#/#%2F#g'; }
    local vlh="vless://$UUID@$HOST:443?encryption=none&$qh&path=$(enc "$PATH_VLH")#$NAME-vless-httpupgrade"
    local trh="trojan://${TROJAN_PASSWORD:-$UUID}@$HOST:443?$qh&path=$(enc "$PATH_TRH")#$NAME-trojan-httpupgrade"
    local vmhj="{\"v\":\"2\",\"ps\":\"$NAME-vmess-httpupgrade\",\"add\":\"$HOST\",\"port\":\"443\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"$HOST\",\"path\":\"$PATH_VMH\",\"tls\":\"tls\",\"sni\":\"$HOST\",\"alpn\":\"http/1.1\",\"fp\":\"chrome\"}"
    local vmh="vmess://$(printf %s "$vmhj" | b64)"
    local ssu; ssu="$(printf %s "$SS_METHOD:$SS_PASS" | base64 | tr -d '=\n')"
    local ss="ss://$ssu@$HOST:443?type=ws&$q&path=$(enc "$PATH_SS")#$NAME-shadowsocks-ws"
    all="$all"$'\n'"$vlh"$'\n'"$vmh"$'\n'"$trh"$'\n'"$ss"
  fi
  SUB_TOKEN="${SUB_TOKEN:-$(sha_slice "sub-$UUID" 1-16)}"
  mkdir -p "$WWW_DIR"
  printf '%s\n' "$all" | b64 > "$WWW_DIR/$SUB_TOKEN"
  log "لینک اشتراک: https://$HOST/$SUB_TOKEN"
}

# ---------- حلقه‌ی به‌روزرسانی ----------
updater_loop() {
  while true; do
    sleep "$((UPDATE_INTERVAL_HOURS * 3600))"
    local changed=0 tag
    tag="$(resolve_tag)" || tag=""
    if [[ -n "$tag" && "$tag" != "$(installed_tag)" ]]; then
      install_xray "$tag" && changed=1
    fi
    fetch_remote_config && changed=1
    if [[ $changed == 1 && -f /tmp/xray.pid ]]; then kill "$(cat /tmp/xray.pid)" 2>/dev/null; fi
  done
}

main() {
  if [[ -z "${UUID:-}" ]]; then
    UUID="$(cat /proc/sys/kernel/random/uuid)"
    log "هشدار: متغیر UUID تنظیم نشده بود. یک مقدار موقت ساخته شد: $UUID (بعد از ری‌استارت عوض می‌شود؛ حتماً UUID را ثابت تنظیم کنید)"
  fi
  mkdir -p "$XRAY_DIR" "$WWW_DIR"

  tag="$(resolve_tag)" || tag=""
  if [[ -x "$XRAY_DIR/xray" && ( -z "$tag" || "$tag" == "$(installed_tag)" ) ]]; then :; else
    [[ -n "$tag" ]] && install_xray "$tag"
  fi
  [[ -x "$XRAY_DIR/xray" ]] || { log "Xray نصب نشد؛ خروج"; exit 1; }

  gen_config full
  if ! XRAY_LOCATION_ASSET="$XRAY_DIR" "$XRAY_DIR/xray" run -test -c "$CONF" >/dev/null 2>&1; then
    log "کانفیگ کامل معتبر نبود؛ حالت پایه (فقط سه کانفیگ WS) فعال شد"
    gen_config basic
  fi
  fetch_remote_config || true
  gen_links
  echo '<html><body><h1>It works!</h1></body></html>' > "$WWW_DIR/index.html"
  if command -v busybox-extras >/dev/null 2>&1; then
    busybox-extras httpd -f -p "127.0.0.1:$PORT_WEB" -h "$WWW_DIR" &
  else
    log "هشدار: busybox-extras نصب نیست؛ صفحه‌ی پیش‌فرض اجرا نمی‌شود"
  fi

  updater_loop &
  trap 'kill 0' TERM INT
  export XRAY_LOCATION_ASSET="$XRAY_DIR"
  log "اجرای Xray $(installed_tag) روی پورت $LISTEN_PORT"
  while true; do
    "$XRAY_DIR/xray" run -c "$CONF" &
    echo $! > /tmp/xray.pid
    wait $!
    log "Xray متوقف شد؛ اجرای دوباره..."
    sleep 2
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main; fi
