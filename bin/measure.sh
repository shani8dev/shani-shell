#!/bin/bash
# Measure quickshell RSS / threads / idle CPU over 10 s.
pid=$(pgrep -f 'qs -c shani' | head -1)
if [ -z "$pid" ]; then echo "quickshell not running"; exit 1; fi

rss_kb=$(awk '/VmRSS/{print $2}' "/proc/$pid/status")
threads=$(awk '/Threads/{print $2}' "/proc/$pid/status")
fds=$(ls "/proc/$pid/fd" | wc -l)
children=$(pgrep -P "$pid" | wc -l)

read -r u1 s1 < <(awk '{print $14, $15}' "/proc/$pid/stat")
sleep 10
read -r u2 s2 < <(awk '{print $14, $15}' "/proc/$pid/stat")

hz=$(getconf CLK_TCK)
cpu=$(awk -v a="$u1" -v b="$s1" -v c="$u2" -v d="$s2" -v hz="$hz" \
    'BEGIN{printf "%.2f", ((c+d)-(a+b))/hz/10*100}')

echo "pid=$pid rss_mib=$(awk -v k="$rss_kb" 'BEGIN{printf "%.1f", k/1024}') threads=$threads fds=$fds child_procs=$children idle_cpu_pct=$cpu"
