#!/bin/bash
# run_all.sh — 6컨테이너(2+2+2) 기동. compose 없이 plain docker run.
#   A Lfuzzer cpu1,2 · B AFL++ cpu3,4 · C G2FUZZ cpu5,6 · 각 4GB · 각자 마운트폴더.
#   OpenAI 키(config/openai_key.txt)가 있어야 C가 뜸. 없으면 A·B만.
# 사용: bash run_all.sh [seconds]     (기본 21600=6h; 스모크는 bash run_all.sh 60)
set -u
SECS=${1:-21600}
IMG=ldso-3fuzzer-bench
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/output"; SEEDS="$ROOT/seeds"; KEY="$ROOT/config/openai_key.txt"

echo "[run_all] 이미지 빌드..."
docker build -t "$IMG" "$ROOT" || { echo "빌드 실패"; exit 1; }

launch() {   # short_name cpu mode
  local sn=$1 cpu=$2 mode=$3 name="bench_$1" cmd
  mkdir -p "$OUT/$sn"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    echo "  건너뜀: $name 이미 존재(삭제 안 함). 재실행: docker rm $name"; return; fi
  case "$mode" in
    lfuzzer) cmd="python3 /kit/run_armA_lfuzzer.py /seeds /output $SECS" ;;
    afl)     cmd="bash /kit/run_armB_afl.sh /seeds /output $SECS" ;;
    g2fuzz)  cmd="bash /kit/run_armC_g2fuzz.sh /output $SECS" ;;
  esac
  local vols=(-v "$OUT/$sn:/output")
  if [ "$mode" = "g2fuzz" ]; then vols+=(-v "$KEY:/secrets/openai_key.txt:ro")
  else vols+=(-v "$SEEDS:/seeds:ro"); fi
  # ★ RAM: lfuzzer(네이티브·파일쓰기만)=4g면 충분. afl/g2fuzz(-Q QEMU)는 악성ELF가 ld.so 거대매핑→
  #   OOM으로 fork서버 사망하던 근본원인 대응 → 8g 넉넉히. (--memory-swap=--memory ⇒ swap 0)
  local mem=4g
  case "$mode" in afl|g2fuzz) mem=8g;; esac
  docker run -d --name "$name" --cpuset-cpus "$cpu" --memory "$mem" --memory-swap "$mem" \
    -e PYTHONPATH=/root/lfuzzer -e LFUZZER_HETERO=1 \
    "${vols[@]}" "$IMG" bash -lc "$cmd" >/dev/null \
    && echo "  기동: $name (cpu=$cpu · ${mem} · $mode) → output/$sn"
}

echo "[run_all] 기동 (${SECS}s)..."
launch lfuzzer1 1 lfuzzer
launch lfuzzer2 2 lfuzzer
launch afl1 3 afl
launch afl2 4 afl
if [ -s "$KEY" ]; then
  launch g2fuzz1 5 g2fuzz
  launch g2fuzz2 6 g2fuzz
else
  echo "  ⚠️ config/openai_key.txt 없음 → Arm C(G2FUZZ) 건너뜀. A·B만 기동."
  echo "     키 넣고 다시 실행하면 C도 뜸(A·B는 그대로 두거나 docker rm 후 재실행)."
fi

echo "[run_all] 상태:"
docker ps --filter "name=bench_" --format "  {{.Names}}\t{{.Status}}"
echo "출력=호스트 $OUT/<name>/ (컨테이너 밖 영속). 모니터: bash status.sh"
