# ldso-3fuzzer-bench — 3퍼저(Lfuzzer / AFL++ / G2FUZZ) ld.so 벤치 재현환경
#   Ubuntu 24.04 = glibc 2.39. AFL++·G2FUZZ 는 QEMU모드로 stock ld.so 타깃.
#   ★ OpenAI 키는 이미지에 굽지 않는다. 런타임에 -v 로 /secrets/openai_key.txt 마운트.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc git python3 python3-pip python-is-python3 binutils ca-certificates curl wget \
        ninja-build meson cmake pkg-config libglib2.0-dev automake libtool bison flex \
        python3-setuptools python3-pip \
    && rm -rf /var/lib/apt/lists/*
# ↑ python-is-python3: G2FUZZ(func.py validate_status_process)가 생성기를 'python xxx.py'로
#   실행해 검증한다. Ubuntu24.04엔 python3만 있고 'python'이 없어 FileNotFoundError→gen_seeds 0
#   ("LLM 생성실패"로 오진)되므로 python→python3 심링크 필수.

WORKDIR /root

# 1) Arm A: Lfuzzer 뮤테이터 (구조인식 4축+hetero 개선본)
RUN git clone --depth 1 -b feat/coverage-guided-upgrade \
        https://github.com/Longarden/lfuzzer.git /root/lfuzzer
ENV LFUZZER=/root/lfuzzer

# 2) Arm B 도 G2FUZZ(=AFL++ 포크)의 afl-fuzz + qemu_mode 를 공용으로 쓴다(아래 step3에서 빌드).
#    (apt afl++ 엔 afl-qemu-trace 가 없음 → 별도 빌드 필요. G2FUZZ 빌드 한 번으로 B·C 둘 다 해결.)

# 3) Arm C: G2FUZZ (AFL++ 포크 + LLM). ★ frida/nyx/coresight 모드 제거(빌드시 인터넷 다운로드로
#    멈추는 원인) → 코어 afl-fuzz 만 빌드. qemu_mode(afl-qemu-trace) 는 별도 빌드.
RUN pip3 install --no-cache-dir --break-system-packages openai==1.63.2
RUN git clone --depth 1 https://github.com/G2FUZZ/G2FUZZ.git /root/G2FUZZ \
    && cd /root/G2FUZZ \
    && rm -rf frida_mode nyx_mode coresight_mode unicorn_mode \
    && make afl-fuzz afl-showmap \
    && cd qemu_mode \
    && git clone https://github.com/AFLplusplus/qemuafl \
    && CPU_TARGET=x86_64 ./build_qemu_support.sh
    # ↑ qemuafl 은 full clone(--depth 1 제거) — build_qemu_support.sh 가 QEMUAFL_VERSION(ef1cd9a8cb)
    #   커밋을 checkout 해야 G2FUZZ import 헤더와 맞음(shallow면 그 커밋 없어 tip→심볼 미정의 컴파일에러).
    #   G2FUZZ엔 .gitmodules 없어 자동 submodule 실패 → qemuafl 을 직접 clone 해서 우회.
    #   make afl-fuzz = afl-cc(소스계측) 안 만듦(LLVM/gcc-plugin 불필요). QEMU(-Q)만 씀.
ENV G2FUZZ_DIR=/root/G2FUZZ AFL_PATH=/root/G2FUZZ AFL_BIN=/root/G2FUZZ/afl-fuzz

# 4) 이 키트 스크립트/설정
COPY run_armA_lfuzzer.py run_armB_afl.sh run_armC_g2fuzz.sh /kit/
COPY config /kit/config
ENV KIT=/kit
RUN chmod +x /kit/run_armB_afl.sh /kit/run_armC_g2fuzz.sh

# 5) 출력=마운트 /output, 키=마운트 /secrets/openai_key.txt (둘 다 이미지에 없음)
ENV OUTDIR=/output OPENAI_KEY_FILE=/secrets/openai_key.txt LDSO=/lib64/ld-linux-x86-64.so.2
RUN mkdir -p /output /secrets

CMD ["/bin/bash"]
