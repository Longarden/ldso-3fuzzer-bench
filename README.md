# ldso-3fuzzer-bench — Lfuzzer vs AFL++ vs G2FUZZ (ld.so 로더 퍼징 벤치)

glibc 동적 링커 `ld.so`(`/lib64/ld-linux-x86-64.so.2`)를 대상으로 **퍼저 3종을 2인스턴스씩(총 6컨테이너)**
동일 조건에서 돌려 비교하는 재현 키트. 생성물은 각 컨테이너별 폴더에 저장된다.

```
━━ 3 Arm 구조 (6컨테이너 · CPU 1~6 · 각 4GB · 6시간) ━━━━━━━━━━━━━━━━━━━━━━━━
 Arm A  Lfuzzer (구조인식 4축+hetero, 블라인드)   cpu1,2  → 전량저장(생성된 모든 .so)   시드 500
 Arm B  stock AFL++ (커버리지 가이드, QEMU)        cpu3,4  → AFL 본연(queue/crash)      같은 시드 500
 Arm C  G2FUZZ (AFL++ + LLM으로 시드 자체생성)      cpu5,6  → AFL 본연 + gen_seeds        자체생성(500 안씀)
```
- **A·B는 같은 500시드**(`seeds/` 폴더, s0000~s0499.elf) → "같은 시드로 블라인드(A) vs 커버리지가이드(B)" 대조.
- **C(G2FUZZ)는 시드를 LLM이 스스로 생성**(우리 500 안 씀) → 논문 방식 그대로.
- AFL++·G2FUZZ는 ld.so 계측이 불가라 **QEMU모드(-Q)** 로 stock ld.so를 타깃한다.

---

## ⚡ 빠른 시작 (한눈에 · 이대로 복붙)

```bash
# ── STEP 0. 이전/스모크 컨테이너 정리 (재실행이면 필수 — 안 하면 run_all.sh가 skip함)
docker rm -f bench_lfuzzer1 bench_lfuzzer2 bench_afl1 bench_afl2 bench_g2fuzz1 bench_g2fuzz2
rm -rf output

# ── STEP 1. 레포 (처음이면 clone, 있으면 pull)
git clone https://github.com/Longarden/ldso-3fuzzer-bench.git   # 처음만
cd ldso-3fuzzer-bench && git pull

# ── STEP 2. OpenAI 키 (Arm C만 필요 / A·B는 없어도 됨)
echo 'sk-여기에-네-실제-키' > config/openai_key.txt              # C 안 쓰면 생략

# ── STEP 3. AFL 크래시 정확도 (1회)
echo core | sudo tee /proc/sys/kernel/core_pattern

# ── STEP 4. 60초 스모크 → 정상이면 6시간 본run
bash run_all.sh 60          # 첫 실행은 이미지 빌드 20~40분 후 60초 기동
docker ps                   # bench_ 6개 Up 이면 성공 (아래 주의 참고)
bash status.sh              # 대시보드
# 좋으면 본run:
docker rm -f bench_lfuzzer1 bench_lfuzzer2 bench_afl1 bench_afl2 bench_g2fuzz1 bench_g2fuzz2
rm -rf output
bash run_all.sh             # 인자 없음 = 21600초 = 6시간
```
> docker에 sudo 필요한 머신이면 위 모든 `docker`/`bash run_all.sh`/`bash status.sh` 앞에 **`sudo`**.

```
━━ ⚠️ docker ps 가 비어보여도 당황 말 것 (삭제된 게 아님) ━━━━━━━━━━━━━━━━━━
 · run_all.sh 는 먼저 이미지를 build 한다 → 빌드 중엔 아직 컨테이너가 없어서 docker ps 가 빈다(정상).
   빌드(20~40분)가 끝나야 docker run 이 돌아 6개가 뜬다.
 · docker ps        = "지금 실행중"만 표시.  다 끝났거나 죽으면 빈다.
 · docker ps -a     = 종료된 것까지 전부 표시.  ← 컨테이너 살았나 확인은 이걸로.
 · 이 레포 스크립트엔 --rm 이 없다 → 컨테이너는 자동삭제 안 됨. 죽어도 Exited 로 남는다.
   (docker ps 비었는데 ps -a 에 Exited 로 있으면 = 삭제된 게 아니라 crash → docker logs 로 원인)
```

---

## 0. 요구 사항 (먼저 확인)

```
 · 코어 6개 이상  (컨테이너를 cpu 1~6 에 핀. `nproc` 로 확인)
 · RAM ~24~28GB  (6컨테이너 × 4GB)
 · 디스크 수백 GB (전량저장은 시간당 수 GB)
 · docker 설치 + 실행권한  (없으면 `sudo docker` 로. 확인: `docker run --rm hello-world`)
 · (Arm C 만) OpenAI 유료 API 키  ← 아래 2번에서 넣는 법 설명
 · 첫 빌드 20~40분  (AFL++/G2FUZZ의 QEMU를 소스빌드하기 때문)
```
> **WSL 사용자:** 반드시 WSL 홈 `~/`(ext4)에 클론·실행하라. `/mnt/c`(윈도우 드라이브)는 10배 느림.

---

## 1. 클론

```bash
cd ~
git clone https://github.com/Longarden/ldso-3fuzzer-bench.git
cd ldso-3fuzzer-bench
```

## 2. ★ OpenAI API 키 기입 (Arm C 전용) — 단계별

G2FUZZ(Arm C)는 OpenAI(GPT)로 ELF 생성기를 만든다(유료). 키는 **레포에 커밋되지 않는 로컬 파일**로 넣는다.

**방법 (택1):**

**(A) 명령 한 줄 — 가장 쉬움**
```bash
echo 'sk-여기에-네-실제-키' > config/openai_key.txt
```
따옴표 안에 네 키(`sk-...`)를 그대로 붙여넣으면 된다. 끝.

**(B) 파일 편집**
```bash
cp config/openai_key.txt.example config/openai_key.txt
nano config/openai_key.txt      # 예시 텍스트 지우고 'sk-...' 키 한 줄만 남긴다
```

**확인:**
```bash
cat config/openai_key.txt       # sk- 로 시작하는 키 한 줄만 보여야 함
```

```
━━ 키 관련 중요 안내 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 · config/openai_key.txt 는 .gitignore 로 제외됨 → 절대 GitHub에 안 올라간다.
 · 컨테이너엔 이미지에 굽지 않고, run_all.sh 가 읽기전용 마운트로 전달한다.
 · 키를 안 넣으면 → Arm A·B만 돌고 C(G2FUZZ)는 자동 건너뜀. (A·B는 키 필요 없음)
 · OpenAI 계정에 하드 스펜딩 캡($5~10) 걸어두길 권장. 비용은 '생성 단계'만이라 gpt-3.5 기준 몇 $.
 · 키가 노출되면 즉시 platform.openai.com 에서 Revoke 후 재발급.
```

## 3. (권장) AFL 크래시 정확도 설정 — 호스트에서 한 번

AFL은 실행 전 `/proc/sys/kernel/core_pattern` 을 검사한다. 그게 `|`(코어덤프 핸들러)로 시작하면
크래시가 timeout으로 오인될 수 있어 AFL이 멈춘다. 한 번만 바꿔주면 된다:
```bash
echo core | sudo tee /proc/sys/kernel/core_pattern
```
> 안 해도 러너가 `AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1` 로 돌긴 한다(크래시 정확도만 약간↓).

## 4. 실행

**먼저 60초 스모크(빌드 확인 + 파일 쌓이나):**
```bash
bash run_all.sh 60
#   첫 실행은 이미지 빌드(20~40분) 후 6컨테이너 60초 기동.
```
**진짜 도는지 확인 (제일 중요):**
```bash
docker ps                       # bench_* 6개가 'Up' 이어야 실행중
bash status.sh                  # 6개 상태·CPU핀·경과·산출물수·최근로그 한 표
```
좋으면 **본run 6시간:**
```bash
# 스모크 컨테이너 정리 후(자동삭제 안 하므로 직접):
docker rm bench_lfuzzer1 bench_lfuzzer2 bench_afl1 bench_afl2 bench_g2fuzz1 bench_g2fuzz2
rm -rf output
bash run_all.sh                 # 인자 없이 = 21600초 = 6시간
docker ps                       # 다시 6개 Up 확인
```
> docker에 sudo가 필요한 환경이면 **모든 docker/스크립트 명령 앞에 `sudo`** 를 붙여라
> (예: `sudo bash run_all.sh 60`, `sudo docker ps`, `sudo bash status.sh`). 안 그러면 상태가 none/0으로 뜬다.

## ✅ 4.5 정상 작동 검증 (본run 전 60초 헬스체크 — 꼭)

6시간 본run 전에 **60초 스모크로 아래 표를 하나씩 확인**하라. "정상 기대값"이 맞으면 OK.
```bash
bash run_all.sh 60      # (docker에 sudo 필요하면 sudo bash run_all.sh 60)
```

| # | 확인 항목 | 명령 | 정상 기대값 |
|---|---|---|---|
| 1 | **6컨테이너 기동** | `docker ps --filter name=bench_` | bench_lfuzzer1·2 / bench_afl1·2 / bench_g2fuzz1·2 가 Up (키 없으면 g2fuzz 2개 제외 4개) |
| 2 | **CPU 핀 + 4GB** | `docker inspect -f '{{.HostConfig.CpusetCpus}} {{.HostConfig.Memory}}' bench_afl1` | `3 4294967296` (=코어3·4GiB). lfuzzer1=1 … g2fuzz2=6 |
| 3 | **실시간 CPU/RAM** | `docker stats --no-stream` | 각 컨테이너 MEM `../4GiB`, CPU 활성 |
| 4 | **Arm A 전량저장** | `ls output/lfuzzer1/*.so \| wc -l` | 60초에 수천 개(>0). 초당 ~200개 |
| 5 | **Arm A 연번·실행권한** | `ls -la output/lfuzzer1/000000001.so` | `-rwxr-xr-x` (+x), 파일명 000000001.so 부터 연번 |
| 6 | **Arm B AFL 시작** | `docker logs bench_afl1 \| grep -i "ready to roll"` | `[+] All set and ready to roll!` (AFL -Q 정상 시작) |
| 7 | **Arm B ld.so 계측** | `cat output/afl1/default/fuzzer_stats \| grep edges_found` | `edges_found : 2000~3000` (QEMU가 ld.so 커버리지 잡음) |
| 8 | **Arm B 큐 채움** | `ls output/afl1/default/queue \| wc -l` | 시간 지나며 증가(초반 0이어도 정상 — QEMU 캘리브레이션 중) |
| 9 | **Arm C LLM 생성** | `docker logs bench_g2fuzz1 \| grep gen_seeds` | `gen_seeds=N개` (N>0 = LLM이 ELF 생성기 만듦). 키 있어야 함 |
| 10 | **A·B 동일시드 확인** | `docker exec bench_lfuzzer1 ls /seeds \| wc -l; docker exec bench_afl1 ls /seeds \| wc -l` | 둘 다 500 (같은 500시드). g2fuzz엔 /seeds 없음(자체생성) |

**60초 뒤 컨테이너는 스스로 종료(Exited)된다 — 정상이다. 파일은 남는다:**
```bash
docker ps -a --filter name=bench_        # 전부 "Exited (0)" 이면 정상 완주
ls output/lfuzzer1/*.so | wc -l           # 종료 후에도 파일 남음(마운트 영속)
```

**하나라도 어긋나면 (빠른 진단):**
```
 · 1이 비었다        → docker ps -a 로 Exited 코드 확인. 빌드 실패면 docker build 로그.
 · 4가 0이다         → (WSL) /mnt/c 에서 돌렸을 가능성 → ~/(ext4)에서 다시. 또는 lfuzzer 빌드 문제.
 · 6에 "ready" 없다   → docker logs bench_afl1 전체 보기. core_pattern abort면 3번 실행.
 · 7 edges_found 0    → -Q(QEMU) 트레이서 문제. 빌드 로그 확인.
 · 9 gen_seeds=0/없음  → 키 미기입(2번) 또는 LLM이 유효 ELF 생성 실패(모델 확인).
 · 10 개수 다름/에러   → docker 접근에 sudo 필요할 수 있음(sudo docker exec ...).
```

정상이면 → 7번(본run) 진행.

## 5. 모니터링 — 정상 작동 확인

```bash
bash status.sh                  # 스냅샷 1회
watch -n5 bash status.sh        # 5초마다 갱신(산출물수 늘어나는지 실시간)
docker logs -f bench_lfuzzer1   # 개별 진행 로그 (bench_lfuzzer1·2 / bench_afl1·2 / bench_g2fuzz1·2)
```

**정상 기대값 (60초 스모크 기준):**
```
 컨테이너         상태     CPU핀  산출물   최근로그
 bench_lfuzzer1  running  1      수천     execs=... crash=... rate=~200/s   ← 전량 .so 쌓임
 bench_afl1      running  3      수십     [+] All set and ready to roll     ← AFL -Q 로 ld.so 계측중
 bench_g2fuzz1   running  5      가변     LLM 생성기 합성 → gen_seeds ...     ← 키 있을 때만
```
- Arm A는 초당 ~200개(전량저장)라 산출물이 빠르게 는다.
- Arm B/C(AFL)는 QEMU라 느리고, 초반엔 시드 캘리브레이션 → queue가 차차 쌓인다(즉시 0이어도 정상).
- Arm C는 처음에 LLM으로 gen_seeds를 만드느라 몇 분 걸린 뒤 afl 퍼징 시작.

## 6. 산출물 위치 (컨테이너 밖 = 호스트에 영속)

```
 output/lfuzzer1·2/   000000001.so 000000002.so …  (전량, 실행권한 +x)  + _crashes.csv
 output/afl1·2/       default/{queue,crashes,hangs}/                   (AFL 본연)
 output/g2fuzz1·2/    afl/default/{queue,crashes}/  + ldso_output/default/gen_seeds/
```
```bash
ls output/lfuzzer1/*.so | wc -l                 # A 생성 개수
ls output/afl1/default/queue | wc -l            # B 큐(커버리지 올린 입력)
cat output/lfuzzer1/_crashes.csv                # A 크래시난 연번,rc
```

## 7. 중지 / 재실행 / 정리

```bash
bash stop_all.sh                # 6개 '중지'만 (컨테이너·출력 모두 유지)
```
```
 ★ 컨테이너는 자동 삭제하지 않는다(데이터 보호). 재실행하려면 기존 것 직접 제거:
   docker rm -f bench_lfuzzer1 bench_lfuzzer2 bench_afl1 bench_afl2 bench_g2fuzz1 bench_g2fuzz2
   (-f = 실행중이어도 강제 제거. output/ 은 마운트라 컨테이너 지워도 파일 안전)
```

## 8. 문제 해결 (Troubleshooting)

```
 · status.sh 가 전부 none/0     → docker에 sudo 필요. `sudo bash status.sh` 로.
 · docker ps 가 permission denied → `sudo usermod -aG docker $USER` 후 재로그인, 또는 sudo 사용.
 · run_all.sh 가 "건너뜀"만 뜸    → 같은 이름 컨테이너가 이미 있음. 위 docker rm 후 다시.
 · Arm C(g2fuzz)가 안 뜸         → config/openai_key.txt 없음/빈 파일. 2번대로 키 넣기.
 · Arm B/C 산출물 0             → 잠깐 더 기다려라(QEMU 캘리브레이션). 계속 0이면 core_pattern(3번) 확인.
 · 첫 빌드가 오래/멈춤           → qemu 소스빌드는 원래 20~40분. 네트워크 필요(github clone).
 · '진짜 도는지'는 항상 docker ps 에 6개 Up 으로 판정 (파일 존재 ≠ 실행중).
```

## 9. 결과 해석 (비교)

- **커버리지 비교**는 셋 다 같은 QEMU 계측으로 통일측정하면 공정하다
  (예: 각 코퍼스를 `afl-showmap -Q -- /lib64/ld-linux-x86-64.so.2 <입력>` 으로 엣지 재측정).
- Arm A(블라인드) vs B(AFL 커버리지가이드): **같은 500시드**라 순수 "전략 차이"를 본다.
- Arm C(G2FUZZ): LLM 생성 시드 기반 → 문법인식 생성의 효과를 본다.
- 의미있는 크래시는 **이름있는 로더함수**(`_dl_relocate_object`·`do_lookup_x`·`_dl_check_map_versions` 등) 착지.

---
> 방어적 보안 연구용. 링커/로더의 견고성 버그를 찾고 퍼저 간 성능을 비교하기 위한 것.
