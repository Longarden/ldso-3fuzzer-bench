#!/bin/bash
# Arm B — stock AFL++ (QEMU 모드) · 500시드 · ld.so 타깃 · AFL 본연저장(queue/crash/hang)을 마운트로.
#   ld.so는 계측 불가 → -Q(QEMU)로 stock ld.so 직접 타깃. -o 를 마운트폴더로 → queue/crash 호스트 저장.
# 사용: bash run_armB_afl.sh <seeds_dir(500)> <out_dir> [seconds]
set -u
SEEDS=${1:?seeds dir}
OUT=${2:?out dir}
SECS=${3:-21600}
LD=${LDSO:-/lib64/ld-linux-x86-64.so.2}
AFL=${AFL_BIN:-afl-fuzz}

mkdir -p "$OUT"
export AFL_SKIP_CPUFREQ=1 AFL_NO_AFFINITY=1 AFL_AUTORESUME=1
# 크래시나는 시드를 dry-run 서 건너뛰게(AFL_SKIP_CRASHES=1 = 진짜 변수).
export AFL_SKIP_CRASHES=1
# 호스트 core_pattern 이 '|'(코어덤프핸들러)로 시작하면 AFL 이 abort → 실행 가능하게 fallback.
#   ★ 크래시 정확도 최상 원하면 호스트에서 한 번: echo core | sudo tee /proc/sys/kernel/core_pattern
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1

echo "[armB-afl] $(date) AFL++ -Q · seeds=$SEEDS · out=$OUT · ${SECS}s · SUT=$LD"
# -Q QEMU · -i 500시드 · -o 마운트 · -m none(QEMU 메모리제한 없음) · -t 2000ms · @@=변이파일
timeout --signal=SIGINT "$SECS" \
  "$AFL" -Q -i "$SEEDS" -o "$OUT" -m none -t 2000 -- "$LD" @@ || true

echo "ARMB_DONE $(date)  결과: $OUT/default/{queue,crashes,hangs}"
