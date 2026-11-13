"""Runs every tests/*_test.lua under Lua 5.1, the language version the game uses."""
import pathlib
import sys

from lupa import lua51

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"


def run_suite(path: pathlib.Path) -> tuple[int, int]:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ADDON_ROOT = ROOT.as_posix()
    lua.execute((TESTS / "harness.lua").read_text(encoding="utf-8"))
    print(path.name, flush=True)
    try:
        lua.execute(path.read_text(encoding="utf-8"))
    except Exception as exc:  # a suite that cannot even load counts as a failure
        print(f"  FAIL  suite did not load: {exc}", flush=True)
        return 1, 1
    return int(lua.eval("harness.ran")), int(lua.eval("harness.failed"))


def main() -> int:
    wanted = sys.argv[1:]
    suites = sorted(TESTS.glob("*_test.lua"))
    if wanted:
        suites = [s for s in suites if s.stem in wanted or s.name in wanted]
    total = failed = 0
    for suite in suites:
        ran, bad = run_suite(suite)
        total += ran
        failed += bad
    print(f"\n{total} tests, {failed} failed", flush=True)
    return 1 if failed or total == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
