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
# ★ 부하내성: 6컨테이너 동시기동시 QEMU startup이 느려 fork서버 초기화가 기본대기(-t×약10=구설정 20s)를
#   넘겨 간헐적 abort → "Exited(0)"로 보이던 것 방지. 아래 env는 초기화 대기를 120s 상수로 덮어씀.
export AFL_FORKSRV_INIT_TMOUT=120000   # fork서버 초기화 대기 = 120000ms(120s) 고정(곱셈 아님)

echo "[armB-afl] $(date) AFL++ -Q · seeds=$SEEDS · out=$OUT · ${SECS}s · SUT=$LD"
# -Q QEMU · -i 500시드 · -o 마운트 · -m none · @@=변이
# -t 5000+ : exec 타임아웃을 초기엔 낮게 잡고 '느린 코드 발견시 5000ms까지 자동상향'(auto-scale, ceiling=5s).
#   ('+'=auto-scale이지 abort회피가 아님. 타임아웃 시드 skip은 -t 값 유무와 무관하게 원래 동작.)
rc=0
timeout --signal=SIGINT "$SECS" \
  "$AFL" -Q -i "$SEEDS" -o "$OUT" -m none -t 5000+ -- "$LD" @@ || rc=$?
# timeout이 SECS 경과로 종료시키면 rc=124(정상완주). 그 외 비정상 rc는 진짜 abort → 크게 표시(||true로 감추지 않음).
if [ "$rc" = 0 ] || [ "$rc" = 124 ]; then
  echo "[armB-afl] 정상 종료 (rc=$rc; 124=6시간 timeout 도달)"
else
  echo "[armB-afl] ★ABORT rc=$rc — afl 비정상 종료. 위 로그(PROGRAM ABORT 등) 확인하라."
fi

echo "ARMB_DONE $(date)  결과: $OUT/default/{queue,crashes,hangs}"
