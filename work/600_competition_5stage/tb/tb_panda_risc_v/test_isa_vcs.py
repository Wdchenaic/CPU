import argparse
import shutil
import subprocess
from pathlib import Path

PASS_MARK = "TEST_PASS"


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir-name", default="inst_test")
    parser.add_argument("--pattern", default="rv32ui-p-*.txt")
    parser.add_argument("--build-dir", default="/tmp/competition_vcs_rv32ui")
    parser.add_argument("--simv-name", default="simv_rv32ui")
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--max-tests", type=int, default=0)
    parser.add_argument("--list-only", action="store_true")
    parser.add_argument("--timeout-s", type=int, default=20)
    return parser.parse_args()


def run_cmd(cmd, cwd=None, timeout=None):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout)


def main():
    args = parse_args()
    tb_dir = Path(__file__).resolve().parent
    root = tb_dir.parent.parent
    image_dir = tb_dir / args.dir_name
    current_image = image_dir / "rv32ui-current.txt"
    tests = sorted(p for p in image_dir.glob(args.pattern) if p.name != current_image.name)

    if args.max_tests > 0:
        tests = tests[:args.max_tests]

    if args.list_only:
        for test in tests:
            print(test)
        return 0

    if not tests:
        print("No tests found")
        return 1

    build_dir = Path(args.build_dir)
    build_dir.mkdir(parents=True, exist_ok=True)
    simv = build_dir / args.simv_name
    filelist = root / "doc/competition_5stage_vcs.f"
    compile_log = root / "doc/vcs_out/rv32ui_vcs_compile.log"
    result_log = root / "doc/vcs_out/rv32ui_vcs_regression.log"

    if args.rebuild or (not simv.exists()):
        compile_cmd = [
            "vcs", "-full64", "-sverilog",
            "-f", str(filelist),
            "-top", "tb_panda_risc_v",
            "-l", str(compile_log),
            "-o", str(simv),
        ]
        print("[compile]", " ".join(compile_cmd))
        compile_res = run_cmd(compile_cmd, cwd=build_dir)
        if compile_res.returncode != 0:
            print(compile_res.stdout)
            print(compile_res.stderr)
            return compile_res.returncode

    pass_count = 0
    fail_count = 0
    lines = []

    original_image = current_image.read_text() if current_image.exists() else None
    try:
        for test in tests:
            shutil.copyfile(test, current_image)
            try:
                sim_res = run_cmd([str(simv)], cwd=build_dir, timeout=args.timeout_s)
                sim_stdout = sim_res.stdout
                sim_stderr = sim_res.stderr
                passed = PASS_MARK in sim_stdout
                status = "PASS" if passed else "FAIL"
            except subprocess.TimeoutExpired as exc:
                sim_stdout = exc.stdout or ""
                sim_stderr = exc.stderr or ""
                if isinstance(sim_stdout, (bytes, bytearray)):
                    sim_stdout = sim_stdout.decode(errors="replace")
                if isinstance(sim_stderr, (bytes, bytearray)):
                    sim_stderr = sim_stderr.decode(errors="replace")
                passed = False
                status = "TIMEOUT"

            print(f"[{status}] {test.name}", flush=True)
            lines.append(f"[{status}] {test}\n")
            result_log.write_text("".join(lines))
            if passed:
                pass_count += 1
            else:
                fail_count += 1
                lines.append(sim_stdout + "\n")
                if sim_stderr:
                    lines.append(sim_stderr + "\n")
                result_log.write_text("".join(lines))
    finally:
        if original_image is not None:
            current_image.write_text(original_image)

    summary = f"Summary: {pass_count} passed, {fail_count} failed, total {len(tests)}\n"
    print(summary, end="", flush=True)
    lines.append(summary)
    result_log.write_text("".join(lines))

    return 0 if fail_count == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
