#!/bin/bash
# stop_all.sh — 6컨테이너 '중지'만(삭제 안 함). 출력은 마운트라 어차피 남음.
set -u
for n in bench_lfuzzer1 bench_lfuzzer2 bench_afl1 bench_afl2 bench_g2fuzz1 bench_g2fuzz2; do
  docker stop "$n" >/dev/null 2>&1 && echo "중지(삭제 안함): $n" || true
done
echo "컨테이너·출력 모두 유지. 정말 지우려면 직접: docker rm bench_lfuzzer1 ..."
