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
export AFL_SKIP_CPUFREQ=1 AFL_NO_AFFINITY=1 AFL_SKIP_CRASHES=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
echo "[armC-g2fuzz] $(date) AFL++ -Q 퍼징 ${SECS}s → $OUT/afl"
timeout --signal=SIGINT "$SECS" \
  ./afl-fuzz -Q -i "$OUT/initial_seeds" -o "$OUT/afl" -m none -t 2000 -k "$G2" -- "$LD" @@ || true

echo "ARMC_DONE $(date)  결과: $OUT/afl/default/{queue,crashes} + $OUT/ldso_output/default/gen_seeds"
