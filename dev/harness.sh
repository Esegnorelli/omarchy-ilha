#!/bin/bash
# Harness de desenvolvimento da Ilha 2.0: uma instância à parte do Quickshell
# que carrega ui/Ilha.qml sem host (shell = null). Nunca toca no shell do
# usuário: não reinicia, não chama omarchy-shell, não mexe em
# ~/.config/omarchy/plugins.
#
# Uso (rode da raiz do repo; ILHA_HARNESS escolhe o nome da instância,
# padrão "main" — cada agente usa o seu):
#   dev/harness.sh start            sobe a instância (janelas escondidas)
#   dev/harness.sh call <alvo> <função> [args…]    ex.: call ilha open control
#   dev/harness.sh state            ilha state, formatado
#   dev/harness.sh wait <ms>        espera (para animações)
#   dev/harness.sh shot <saida.png> [L A]   foto: L x A centrada (padrão 1200 x 600)
#   dev/harness.sh locked <comando…>        roda o comando com a trava e as janelas visíveis
#   dev/harness.sh log [n]          últimas n linhas do log (padrão 80)
#   dev/harness.sh errors           só avisos e erros de QML do log
#   dev/harness.sh smoke            teste de carga do Phase 0 (start, open control, close, stop)
#   dev/harness.sh stop             para a instância (SEMPRE ao terminar)
#   dev/harness.sh list             instâncias vivas
#
# Variáveis: ILHA_HARNESS (nome), ILHA_HARNESS_LANG (idioma só desta
# instância, ex.: ar para RTL), ILHA_DEV_TOP (deslocamento), ILHA_DEV_BARCONFIG
# (JSON de barConfig, ex.: '{"ilha":{"focusedOnly":true}}').
#
# Regras:
# - Sessões curtas; sempre `stop` no fim.
# - Fotos passam pela trava $XDG_RUNTIME_DIR/ilha-harness.lock (flock): só uma
#   instância fica visível por vez. Fora da trava as janelas ficam escondidas.
# - A ilha do harness aparece ILHA_DEV_TOP px abaixo do topo (padrão 200),
#   para não se misturar com a barra real; a geometria é a mesma.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="${ILHA_HARNESS:-main}"
base="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ilha-harness"
dir="$base/$name"
lock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ilha-harness.lock"
top="${ILHA_DEV_TOP:-200}"
omarchy="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"

die() { echo "harness: $*" >&2; exit 1; }

is_ours() {
  # O pid é desta instância do harness (nunca o shell do usuário).
  local pid="$1"
  [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q -- "-p $dir"
}

running() {
  [ -f "$dir/pid" ] && is_ours "$(cat "$dir/pid")"
}

ipc() {
  qs -p "$dir" ipc call "$@"
}

cmd_start() {
  running && { echo "harness: '$name' já está rodando (pid $(cat "$dir/pid"))"; return 0; }
  [ -d "$omarchy/shell/Commons" ] || die "não achei $omarchy/shell/Commons (OMARCHY_PATH)"
  mkdir -p "$dir"
  cp "$repo/dev/harness.qml" "$dir/shell.qml"
  ln -sfn "$omarchy/shell/Commons" "$dir/Commons"
  : > "$dir/harness.log"
  # ILHA_HARNESS_LANG=ar fixa o idioma só desta instância (OMARCHY_LANGUAGE_FILE,
  # o mesmo desvio que o omarchy-i18n usa em testes); o idioma do usuário não muda.
  local langfile=""
  if [ -n "${ILHA_HARNESS_LANG:-}" ]; then
    langfile="$dir/language"
    printf '%s\n' "$ILHA_HARNESS_LANG" > "$langfile"
  fi
  env ILHA_DEV=1 ILHA_REPO="$repo" ILHA_DEV_TOP="$top" OMARCHY_PATH="$omarchy" \
    ${langfile:+"OMARCHY_LANGUAGE_FILE=$langfile"} \
    setsid qs -p "$dir" >> "$dir/harness.log" 2>&1 < /dev/null &
  echo $! > "$dir/pid"
  for _ in $(seq 1 60); do
    if ipc ilha state 2> /dev/null | grep -q '"esegnorelli.ilha"'; then
      echo "harness: '$name' pronto (pid $(cat "$dir/pid"), log $dir/harness.log)"
      return 0
    fi
    running || { tail -n 40 "$dir/harness.log"; die "a instância saiu durante a carga"; }
    sleep 0.25
  done
  tail -n 40 "$dir/harness.log"
  die "sem resposta ao IPC em 15 s"
}

cmd_stop() {
  if running; then
    local pid
    pid="$(cat "$dir/pid")"
    kill "$pid" 2>/dev/null
    for _ in $(seq 1 20); do is_ours "$pid" || break; sleep 0.1; done
    is_ours "$pid" && kill -9 "$pid" 2>/dev/null
    echo "harness: '$name' parado"
  else
    echo "harness: '$name' não estava rodando"
  fi
  rm -f "$dir/pid"
}

cmd_state() {
  running || die "'$name' não está rodando (dev/harness.sh start)"
  local out
  out="$(ipc ilha state)" || die "ilha state falhou"
  if command -v jq > /dev/null; then echo "$out" | jq .; else echo "$out"; fi
}

with_lock() {
  running || die "'$name' não está rodando (dev/harness.sh start)"
  exec 9> "$lock"
  flock -w 180 9 || die "trava ocupada por mais de 180 s"
  ipc ilha-dev reveal 1 > /dev/null
  sleep 0.35
  "$@"
  local rc=$?
  ipc ilha-dev reveal 0 > /dev/null
  flock -u 9
  return $rc
}

shot_now() {
  local out="$1" w="${2:-1200}" h="${3:-600}"
  local sw
  sw="$(hyprctl monitors -j 2> /dev/null | jq -r '[.[] | select(.focused)][0].width // 1920')"
  local x=$(( (sw - w) / 2 ))
  grim -g "$x,$top ${w}x${h}" "$out" && echo "harness: foto $out"
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  call) shift; running || die "'$name' não está rodando"; ipc "$@" ;;
  state) cmd_state ;;
  wait) sleep "$(awk "BEGIN { print ${2:-300} / 1000 }")" ;;
  shot) shift; [ -n "${1:-}" ] || die "uso: shot <saida.png> [L A]"; with_lock shot_now "$@" ;;
  locked) shift; [ -n "${1:-}" ] || die "uso: locked <comando…>"; with_lock "$@" ;;
  log) tail -n "${2:-80}" "$dir/harness.log" ;;
  errors) grep -E "WARN|ERROR|qml:.*(Error|TypeError|ReferenceError|Unable|Cannot)|\.qml:[0-9]+" "$dir/harness.log" | grep -v "qt.qpa.services" || echo "harness: sem avisos" ;;
  list) for d in "$base"/*/; do n="$(basename "$d")"; ILHA_HARNESS="$n" "$0" status-one; done 2> /dev/null ;;
  status-one) running && echo "$name: rodando (pid $(cat "$dir/pid"))" || echo "$name: parado" ;;
  smoke)
    cmd_start || exit 1
    echo "--- repouso"; ipc ilha state | jq -c '.windows[] | {face, morph}'
    echo "--- open control: $(ipc ilha open control)"; sleep 0.9
    ipc ilha state | jq -c '.windows[] | {face, morph, target}'
    echo "--- close: $(ipc ilha close)"; sleep 0.9
    ipc ilha state | jq -c '.windows[] | {face, morph}'
    "$0" errors
    cmd_stop
    ;;
  *) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 1 ;;
esac
