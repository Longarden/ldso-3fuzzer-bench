#!/bin/bash
# status.sh — 6컨테이너 상태 한 표: 상태·CPU핀·경과(/6h)·산출물수·최근로그.
#   산출물수 = 컨테이너 마운트경로 하위 전체 파일수(A=*.so 전량 / B·C=queue+crash 등).
#   docker에 sudo 필요한 환경이면: sudo bash status.sh
set -u
ROOT=$(cd "$(dirname "$0")" && pwd); OUT="$ROOT/output"
if ! docker ps >/dev/null 2>&1; then
  echo "⚠️ docker 접근 불가(권한/데몬). sudo bash status.sh 또는 sudo usermod -aG docker \$USER"; exit 1; fi
now=$(date +%s)
printf "%-15s %-9s %-6s %-10s %-9s %s\n" 컨테이너 상태 CPU핀 "경과(/6h)" 산출물 "최근로그"
printf "%-15s %-9s %-6s %-10s %-9s %s\n" --------- ---- ----- --------- ----- --------
for sn in lfuzzer1 lfuzzer2 afl1 afl2 g2fuzz1 g2fuzz2; do
  name="bench_$sn"
  st=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo none)
  cpu=$(docker inspect -f '{{.HostConfig.CpusetCpus}}' "$name" 2>/dev/null)
  started=$(docker inspect -f '{{.State.StartedAt}}' "$name" 2>/dev/null)
  if [ "$st" = "running" ] && [ -n "$started" ]; then
    se=$(date -d "$started" +%s 2>/dev/null || echo 0)
    [ "$se" != 0 ] && el=$(printf '%dh%02dm' $(((now-se)/3600)) $((((now-se)%3600)/60))) || el="?"
  else el="-"; fi
  src=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/output"}}{{.Source}}{{end}}{{end}}' "$name" 2>/dev/null)
  [ -z "$src" ] && src="$OUT/$sn"
  files=$(find "$src" -type f 2>/dev/null | wc -l)
  log=$(docker logs --tail 5 "$name" 2>&1 | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -1 | sed 's/^[[:space:]]*//' | tail -c 44)
  printf "%-15s %-9s %-6s %-10s %-9s %s\n" "$name" "${st:-none}" "${cpu:--}" "$el" "$files" "$log"
done
echo "--- CPU/RAM 순간 ---"
docker stats --no-stream --format '{{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}}' 2>/dev/null | grep bench_ || echo "(실행중 없음)"
