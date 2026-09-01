#!/bin/bash
# Arm C — G2FUZZ · LLM(GPT)로 ELF 생성기 자체합성 → gen_seeds → AFL++ -Q 로 ld.so 퍼징.
#   시드 자체생성(우리 500 안 씀). ld.so는 -Q(QEMU). AFL 본연저장(queue/crash) + gen_seeds 마운트로.
#   ★ OpenAI 키는 이미지에 안 굽고 '마운트'로 받음(OPENAI_KEY_FILE).
# 사용: bash run_armC_g2fuzz.sh <out_dir> [seconds]
set -u
OUT=${1:?out dir}
SECS=${2:-21600}
G2=${G2FUZZ_DIR:-/root/G2FUZZ}
LD=${LDSO:-/lib64/ld-linux-x86-64.so.2}
KEY=${OPENAI_KEY_FILE:-/secrets/openai_key.txt}
KIT=${KIT:-/kit}

mkdir -p "$OUT"

# 0) 키·config 배선 (G2FUZZ는 자기 폴더에서 openai_key.txt·*.json 읽음). 키는 마운트파일에서 복사.
if [ ! -s "$KEY" ]; then echo "[armC] OpenAI 키 없음: $KEY (마운트 확인)"; exit 1; fi
cp "$KEY" "$G2/openai_key.txt"
cp "$KIT/config/program_to_format.json" "$G2/program_to_format.json"
cp "$KIT/config/model_setting.json"      "$G2/model_setting.json"

# 1) LLM 생성기 합성 → gen_seeds (자체생성, 인스턴스마다 독립)
echo "[armC-g2fuzz] $(date) LLM 생성기 합성(program_gen.py)..."
cd "$G2"
python3 program_gen.py --output "$OUT/ldso_output" --program ldso 2>&1 | tail -30

# 2) 자체생성 시드를 corpus 로
mkdir -p "$OUT/initial_seeds"
cp "$OUT"/ldso_output/default/gen_seeds/* "$OUT/initial_seeds/" 2>/dev/null || true
NGEN=$(ls "$OUT/initial_seeds"/ 2>/dev/null | wc -l)
echo "[armC-g2fuzz] gen_seeds=$NGEN 개"
if [ "$NGEN" -eq 0 ]; then echo "[armC] gen_seeds 0개 — LLM 생성 실패(모델/키 확인)"; exit 1; fi

# 3) AFL++ -Q 로 ld.so 퍼징 (cmplog -c 제거, -Q QEMU, -k G2FUZZ 통합)
export AFL_SKIP_CPUFREQ=1 AFL_NO_AFFINITY=1 AFL_AUTORESUME=1 AFL_SKIP_CRASHES=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
export AFL_FORKSRV_INIT_TMOUT=120000   # ★ 부하내성(Arm B와 동일): fork서버 초기화 대기 = 120s 고정
echo "[armC-g2fuzz] $(date) AFL++ -Q 퍼징 ${SECS}s → $OUT/afl"
# -t 5000+ : exec 타임아웃 auto-scale(ceiling=5s). 6컨테이너 동시부하로 QEMU startup 지연시에도 안정.
# ★ 런타임 복원력(Arm B와 동일): 퍼징 도중 fork서버 사망(OOM/ld.so abort)시 AUTORESUME으로
#   남은 예산까지 자동 재개. 15초내 연속 5회 급사시 재개중단(독성입력/RAM부족 가드).
END=$(( $(date +%s) + SECS )); fails=0; attempt=0; MAXATT=100
while :; do
  REMAIN=$(( END - $(date +%s) ))
  [ "$REMAIN" -le 10 ] && { echo "[armC-g2fuzz] 시간예산 소진 → 종료"; break; }
  if [ "$attempt" -ge "$MAXATT" ]; then
    echo "[armC-g2fuzz] ★★재개 ${MAXATT}회 도달 — 느린 반복사망(독성입력/RAM) 의심, 재개 중단"; break
  fi
  attempt=$((attempt+1))
  [ "$attempt" -gt 1 ] && echo "[armC-g2fuzz] $(date) afl 재개 #$attempt (AUTORESUME · 남은 ${REMAIN}s)"
  start=$(date +%s); rc=0
  timeout --signal=SIGINT "$REMAIN" \
    ./afl-fuzz -Q -i "$OUT/initial_seeds" -o "$OUT/afl" -m none -t 5000+ -k "$G2" -- "$LD" @@ || rc=$?
  if [ "$rc" = 0 ] || [ "$rc" = 124 ]; then
    echo "[armC-g2fuzz] 정상 종료 (rc=$rc; 124=시간예산 도달)"; break
  fi
  dur=$(( $(date +%s) - start ))
  echo "[armC-g2fuzz] ★afl 중단 rc=$rc (${dur}s 만에) — fork서버 사망/OOM 의심, 재개 시도"
  if [ "$dur" -lt 15 ]; then fails=$((fails+1)); else fails=0; fi
  if [ "$fails" -ge 5 ]; then
    echo "[armC-g2fuzz] ★★연속 급속중단 5회 — 독성입력/RAM부족 의심. 재개 중단(crashes·로그 확인)"; break
  fi
  sleep 2
done

echo "ARMC_DONE $(date)  결과: $OUT/afl/default/{queue,crashes} + $OUT/ldso_output/default/gen_seeds"
