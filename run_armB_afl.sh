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
# ★ 런타임 복원력: 퍼징 도중 fork서버가 죽는 경우(악성 ELF가 4GB OOM 유발 또는 ld.so abort가
#   fork서버 동반사망) afl는 그냥 abort하고 끝난다 → 그 arm 조기종료. AUTORESUME으로 남은 예산까지
#   자동 재개해 6시간을 채운다(저장된 queue/crashes에서 이어감).
#   가드: '독성입력'이 재개 직후 또 죽이면 무한루프 → 15초내 연속 5회 급사시 재개중단.
END=$(( $(date +%s) + SECS )); fails=0; attempt=0; MAXATT=100
while :; do
  REMAIN=$(( END - $(date +%s) ))
  [ "$REMAIN" -le 10 ] && { echo "[armB-afl] 시간예산 소진 → 종료"; break; }
  if [ "$attempt" -ge "$MAXATT" ]; then
    echo "[armB-afl] ★★재개 ${MAXATT}회 도달 — 느린 반복사망(독성입력/RAM) 의심, 재개 중단"; break
  fi
  attempt=$((attempt+1))
  [ "$attempt" -gt 1 ] && echo "[armB-afl] $(date) afl 재개 #$attempt (AUTORESUME · 남은 ${REMAIN}s)"
  start=$(date +%s); rc=0
  timeout --signal=SIGINT "$REMAIN" \
    "$AFL" -Q -i "$SEEDS" -o "$OUT" -m none -t 5000+ -- "$LD" @@ || rc=$?
  if [ "$rc" = 0 ] || [ "$rc" = 124 ]; then
    echo "[armB-afl] 정상 종료 (rc=$rc; 124=시간예산 도달)"; break
  fi
  dur=$(( $(date +%s) - start ))
  echo "[armB-afl] ★afl 중단 rc=$rc (${dur}s 만에) — fork서버 사망/OOM 의심, 재개 시도"
  if [ "$dur" -lt 15 ]; then fails=$((fails+1)); else fails=0; fi
  if [ "$fails" -ge 5 ]; then
    echo "[armB-afl] ★★연속 급속중단 5회 — 독성입력/RAM부족 의심. 재개 중단(crashes·로그 확인)"; break
  fi
  sleep 2
done

echo "ARMB_DONE $(date)  결과: $OUT/default/{queue,crashes,hangs}"
