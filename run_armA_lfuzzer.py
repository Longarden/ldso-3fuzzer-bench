#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arm A — Lfuzzer 블라인드(구조인식 4축+hetero) · 500시드 코퍼스 · 전량 직접저장.
  시드 500개에서 매번 무작위로 하나 골라 변이 → OUT/NNNNNNNNN.so 로 '모든' 변이 저장(압축 없음).
  ld.so 로 실행해 크래시 판정(파일은 어차피 전량 보존). 무조건 자체난수.
사용: python3 run_armA_lfuzzer.py <seeds_dir(500)> <out_dir> <seconds>
환경: PYTHONPATH=<lfuzzer repo>, LFUZZER_HETERO=1, LDSO, LFUZZER_TIMEOUT
"""
from __future__ import annotations
import os, sys, time, glob, subprocess
from lfuzzer.mutators import structure_aware as SA

SEEDS_DIR = os.path.expanduser(sys.argv[1])
OUT       = os.path.expanduser(sys.argv[2])
SECS      = float(sys.argv[3])
LOADER    = os.environ.get("LDSO", "/lib64/ld-linux-x86-64.so.2")
TIMEOUT   = float(os.environ.get("LFUZZER_TIMEOUT", "3"))
RSEED     = int.from_bytes(os.urandom(8), "little")   # 무조건 자체난수(인스턴스 발산)


def is_crash(rc): return rc < 0 or rc == 124


def run_loader(p):
    try:
        return subprocess.run([LOADER, p], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        return 124
    except Exception:
        return None


def main():
    seeds = []
    for p in sorted(glob.glob(os.path.join(SEEDS_DIR, "*"))):
        if os.path.isfile(p):
            with open(p, "rb") as f:
                seeds.append(bytearray(f.read()))
    if not seeds:
        sys.exit("시드 없음(500 기대): %s" % SEEDS_DIR)
    os.makedirs(OUT, exist_ok=True)
    crash_log = open(os.path.join(OUT, "_crashes.csv"), "a", buffering=1)
    mut = SA.StructureAwareMutator(seed=RSEED)
    rng = mut.rng
    n = 0; crashes = 0; t0 = time.time(); deadline = t0 + SECS
    print("[armA-lfuzzer] seeds=%d out=%s secs=%.0f rng=%d(self-random) hetero=%s → 전량저장"
          % (len(seeds), OUT, SECS, RSEED, os.environ.get("LFUZZER_HETERO", "1")), flush=True)
    while time.time() < deadline:
        base = seeds[rng.randrange(len(seeds))]        # 500개 중 무작위 시드
        mutant = mut.fuzz(bytes(base), None, max(len(base) * 2, 4096))
        n += 1
        path = os.path.join(OUT, "%09d.so" % n)
        with open(path, "wb") as f:
            f.write(bytes(mutant))
        os.chmod(path, 0o755)
        rc = run_loader(path)
        if rc is not None and is_crash(rc):
            crashes += 1
            crash_log.write("%09d,%d\n" % (n, rc))
        if n % 500 == 0:
            el = time.time() - t0
            print("  execs=%d crash=%d rate=%.1f/s elapsed=%.0fs"
                  % (n, crashes, n / max(el, 1e-9), el), flush=True)
    crash_log.close()
    print("[armA-lfuzzer] done execs=%d crash=%d elapsed=%.0fs → %s"
          % (n, crashes, time.time() - t0, OUT), flush=True)
    print("ARMA_DONE", flush=True)


if __name__ == "__main__":
    main()
