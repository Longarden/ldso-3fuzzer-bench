# ldso-3fuzzer-bench — Lfuzzer vs AFL++ vs G2FUZZ (ld.so, 6h)

glibc 동적 링커 `ld.so` 를 대상으로 **3 퍼저를 2인스턴스씩(6컨테이너)** 동일 조건에서 돌려 비교.

```
 Arm A  Lfuzzer(구조인식 4축+hetero, 블라인드)  cpu1,2  4GB  → 전량저장(모든 .so)      시드 500
 Arm B  stock AFL++ (-Q QEMU)                  cpu3,4  4GB  → AFL 본연(queue/crash)   같은 시드 500
 Arm C  G2FUZZ (-Q QEMU + LLM 자체생성)          cpu5,6  4GB  → AFL 본연 + gen_seeds    자체생성(500 안씀)
 SUT 전부 /lib64/ld-linux-x86-64.so.2 · 6h · 각자 마운트폴더 · 컨테이너 자동삭제 안 함
```

- A·B = **같은 500시드**(`seeds/`, s0000~s0499.elf). C = **자체생성**(LLM이 ELF 생성기 합성).
- AFL++·G2FUZZ 는 ld.so 계측 불가라 **QEMU모드(-Q)** 로 stock ld.so 타깃(커버리지도 -Q 통일측정).

## ★ OpenAI 키 기입 (Arm C 전용, 커밋 금지)
G2FUZZ 는 OpenAI(GPT) API로 ELF 생성기를 합성한다(유료). 키는 **이미지에 안 굽고 로컬 파일로**:
```bash
cp config/openai_key.txt.example config/openai_key.txt   # 예시 복사
# config/openai_key.txt 를 열어 'sk-...' 키 한 줄만 남긴다 (이 파일은 .gitignore 로 제외됨)
```
- 컨테이너엔 `run_all.sh` 가 `-v config/openai_key.txt:/secrets/openai_key.txt:ro` 로 마운트한다.
- 키 없으면 A·B만 뜬다(C 자동 건너뜀). 비용은 생성단계만(gpt-3.5 기준 몇 $). **하드 스펜딩 캡 권장.**

## 요구 자원
- **코어 6개 이상(cpuset 1~6) + RAM ~24~28GB(6컨테이너×4GB) + 디스크 수백 GB.**
- docker · (Arm C는 OpenAI 유료키). 첫 빌드 20~40분(qemu 소스빌드).

## 실행
```bash
# (권장) AFL 크래시 정확도용 — 호스트에서 한 번. core_pattern 이 '|'로 시작하면 AFL 이 abort:
echo core | sudo tee /proc/sys/kernel/core_pattern
#   안 해도 러너가 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 로 돌긴 함(정확도만 약간↓)

bash run_all.sh 60     # 60초 스모크 (빌드 + 6컨테이너)
bash run_all.sh        # 6시간 본run (인자 없으면 21600)
bash status.sh         # 6개 상태·CPU핀·경과·산출물수·로그 (watch -n5 bash status.sh)
docker logs -f bench_lfuzzer1   # 개별 로그
bash stop_all.sh       # 전체 중지(삭제 안 함)
```
> WSL이면 `~/`(ext4)에 클론(/mnt/c 느림). docker에 sudo 필요하면 모든 명령 앞에 `sudo`.

## 산출물 위치
```
 output/lfuzzer1·2/   000000001.so … (전량, +x)  · _crashes.csv
 output/afl1·2/       default/{queue,crashes,hangs}/  (AFL 본연)
 output/g2fuzz1·2/    afl/default/{queue,crashes}/  + ldso_output/default/gen_seeds/
```

## 재실행 시
```
 컨테이너 자동삭제 안 함 → 재실행 전 기존 것 직접 제거:
   docker rm bench_lfuzzer1 bench_lfuzzer2 bench_afl1 bench_afl2 bench_g2fuzz1 bench_g2fuzz2
 (데이터는 output/ 마운트라 컨테이너 지워도 안전)
```
