"""Runs the addon's scenarios (tests/scenarios.lua) in Lua 5.1, WoW's Lua, against the game model in
tests/wow.lua. Each scenario gets a fresh Lua state. Needs lupa: pip install lupa"""

import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ["session", "migration", "badsettings", "noprofiler", "quietlogin", "problemlogin"]


def syntax_check(lua):
    bad = 0
    for path in sorted(ROOT.rglob("*.lua")):
        if "tests" in path.parts:
            continue
        source = path.read_text(encoding="utf-8")
        result = lua.eval("function(source, name) local _, err = loadstring(source, name) return err end")(source, path.name)
        if result:
            print(f"SYNTAX {path.relative_to(ROOT)}: {result}")
            bad += 1
    return bad


def run(name):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ROOT = str(ROOT).replace("\\", "/")
    g.SCENARIO = name
    lua.execute((ROOT / "tests" / "wow.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "tests" / "scenarios.lua").read_text(encoding="utf-8"))
    result = g.RESULT
    failures = [result.failures[i] for i in range(1, len(result.failures) + 1)]
    return result.checks, failures


def main():
    failed = syntax_check(lua51.LuaRuntime())
    total = 0
    for name in SCENARIOS:
        checks, failures = run(name)
        total += checks
        status = "ok" if not failures else f"{len(failures)} FAILED"
        print(f"{name}: {checks} checks, {status}")
        for failure in failures:
            print(f"    {failure}")
        failed += len(failures)
    print(f"{total} checks, {failed} failures")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
