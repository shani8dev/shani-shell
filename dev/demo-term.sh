#!/bin/sh
# What the demo window shows: the session this shell is running in, plus a
# block of high-frequency colour so a blur pass has something to smear.
ESC=$(printf '\033')
RESET="${ESC}[0m"
DIM="${ESC}[2m"
OK="${ESC}[32m"
KEY="${ESC}[36m"
WARN="${ESC}[33m"
ACC="${ESC}[38;5;79m"

# Background through the terminal itself, not `foot -o`: this foot build
# rejects a `[colors]` section in an override, and the error line was the first
# thing the demo window showed. OSC 11 is the portable way to set it.
printf '\033]11;#111318\033\\'

printf '\n'
printf "  ${ACC}shani${RESET} ${DIM}· session${RESET}\n\n"

row() { printf "  %-22s %s\n" "$1" "$2"; }

row "compositor"          "${OK}niri 26.04${RESET} ${DIM}(wayland, nested)${RESET}"
row "shell"               "${OK}quickshell 0.3.2${RESET} ${DIM}· qml${RESET}"
row "blur"                "${OK}ext-background-effect-v1${RESET}"
row "workspaces"          "${OK}ext-workspace-v1${RESET}"
row "chronoa"             "${OK}connected${RESET} ${DIM}· local · llama.cpp${RESET}"
printf '%s' "$DIM"
printf "  ────────────────────────────────────────────────\n"
printf '%s' "$RESET"
row "org.shani.Chronoa.Mascot"  "${DIM}shell owns${RESET}"
row "org.shani.Chronoa.Windows" "${DIM}shell owns${RESET}"
row "dev.shani.chronoa.Agent"   "${OK}turn stream${RESET} ${DIM}· Turn / Approve / Event${RESET}"
row "dev.shani.chronoa.Gateways" "${OK}exists today${RESET}"

printf '\n'
printf "  ${KEY}turn${RESET}  tidy my desktop\n"
printf "  ${KEY}tool${RESET}  scan ~/Desktop ${DIM}→ 14 files${RESET}\n"
printf "  ${KEY}ask${RESET}   ${WARN}may I move them?${RESET}  ${DIM}[allow once] [this session] [deny]${RESET}\n"
printf "  ${KEY}done${RESET}  ${OK}moved 14 files${RESET} ${DIM}· undo in one step${RESET}\n"

printf '\n  '
i=0
while [ "$i" -lt 12 ]; do
    c=$((31 + i % 6))
    printf "\033[%d;1m████\033[0m " "$c"
    i=$((i + 1))
done
printf '\n\n'

sleep 3600
