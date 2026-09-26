import importlib.machinery
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

BUNDLE = Path(__file__).resolve().parents[1] / "bin/bundle"
if not BUNDLE.is_file():
    BUNDLE = Path("/usr/local/bin/bundle")
# bin/ に __pycache__ を作らない
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("bundle", str(BUNDLE))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
bundle_cpp = module.bundle_cpp
bundle_python = module.bundle_python
bundle_rust = module.bundle_rust


def check_blank_lines(output: str) -> None:
    assert "\n\n\n" not in output
    assert not output.startswith("\n")
    assert output.endswith("\n") and not output.endswith("\n\n")
    assert not any(not first.strip() and not second.strip()
                   for first, second in zip(output.splitlines(), output.splitlines()[1:]))


def write(root: Path, name: str, source: str) -> None:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source)


def run(source: str, suffix: str, directory: Path) -> None:
    tool = {".cpp": "g++", ".py": "python3", ".rs": "rustc"}[suffix]
    executable = shutil.which(tool)
    if executable is None:
        print(f"SKIP {suffix} compile/run: {tool} missing")
        return
    path = directory / ("main" + suffix)
    path.write_text(source)
    binary = directory / "main"
    if suffix == ".cpp":
        subprocess.run([executable, "-std=gnu++23", str(path), "-o", str(binary)],
                       check=True, cwd=directory)
    elif suffix == ".rs":
        subprocess.run([executable, "--edition", "2024", str(path), "-o", str(binary)],
                       check=True, cwd=directory)
    env = dict(os.environ, PYTHONPATH="")
    command = [executable, str(path)] if suffix == ".py" else [str(binary)]
    result = subprocess.run(command, check=True, capture_output=True, text=True,
                            cwd=directory, env=env)
    assert result.stdout == "-4 -3\n", result.stdout
    print(f"PASS {suffix} compile/run")


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary) / "library"
        work = Path(temporary) / "run"
        work.mkdir()
        write(root, "cpp/cplib/used.hpp", """#pragma once

inline int used_marker() { return -4; }
""")
        write(root, "cpp/cplib/div.hpp", """#pragma once

#include "cplib/used.hpp"
inline int div_marker() { return used_marker(); }
""")
        write(root, "cpp/cplib/unused.hpp", "int unused_marker;\n")
        cpp = """#include <iostream>
#include <cplib/div.hpp>
#include "cplib/used.hpp"
int main() { std::cout << div_marker() << " -3\\n"; }
"""
        write(root, "python/cplib/__init__.py", "package_marker = True\n")
        write(root, "python/cplib/used.py", "def used_marker(): return -4\n")
        write(root, "python/cplib/div.py", """from cplib import used
def div_marker(): return used.used_marker()
""")
        write(root, "python/cplib/unused.py", "unused_marker = True\n")
        python = """import cplib.div
from cplib.div import div_marker
print(div_marker(), -3)
"""
        write(root, "rust/src/lib.rs", "pub mod div;\npub mod used;\npub mod unused;\n")
        write(root, "rust/src/div.rs", """

mod nested;
pub fn div_marker() -> i32 { nested::value() }
""")
        write(root, "rust/src/div/nested.rs",
              "pub fn value() -> i32 { crate::used::used_marker() }\n")
        write(root, "rust/src/used/mod.rs", "pub fn used_marker() -> i32 { -4 }\n")
        write(root, "rust/src/unused.rs", "pub fn unused_marker() {}\n")
        rust = 'fn main() { println!("{} -3", cplib::div::div_marker()); }\n'
        fixtures = [(".cpp", bundle_cpp, cpp), (".py", bundle_python, python),
                    (".rs", bundle_rust, rust)]
        for suffix, bundler, source in fixtures:
            output = bundler("\n \n\n" + source + "\n \n\n", root)
            check_blank_lines(output)
            assert "div_marker" in output and "used_marker" in output
            assert "unused_marker" not in output
            if suffix == ".cpp":
                assert "#pragma once" not in output
                assert output.count("inline int used_marker") == 1
                assert "#include <iostream>" in output
            if suffix == ".py":
                assert "package_marker" in output
            if suffix == ".rs":
                assert "mod unused" not in output
                assert "{\n\n" not in output and "\n\n}" not in output
            print(f"PASS {suffix} dependency closure")
            run(output, suffix, work)

        for reference in ["use cplib::{div, used::used_marker};",
                          "use cplib::{div::{div_marker}, used};",
                          "use cplib::*;"]:
            output = bundle_rust(reference, root)
            assert "div_marker" in output and "used_marker" in output
            assert ("unused_marker" in output) == ("cplib::*" in reference)
        assert "crate::cplib::used::" in bundle_rust(rust, root)
        assert "unused_marker" not in bundle_rust("fn main() {}", root)
        write(root, "python/cplib/nested/__init__.py", "nested_marker = True\n")
        write(root, "python/cplib/nested/value.py", "from cplib.div import div_marker\n")
        nested = bundle_python("from cplib.nested import value\n"
                               "print(value.div_marker(), -3)\n", root)
        assert "nested_marker" in nested and "unused_marker" not in nested
        run(nested, ".py", work)

        literal = 'text = """first\n\n\nlast"""\nassert text == "first\\n\\n\\nlast"\n'
        exec(bundle_python(literal, root), {})
        print("PASS Python multiline string preservation")

        env = dict(os.environ, CPLIB=str(root))
        for suffix, bundler, source in fixtures:
            directory = work / suffix[1:]
            directory.mkdir()
            path = directory / ("main" + suffix)
            path.write_text(source)
            result = subprocess.run([sys.executable, str(BUNDLE), str(path)],
                                    check=True, capture_output=True, text=True,
                                    cwd=directory, env=env)
            check_blank_lines(result.stdout)
            assert result.stdout == bundler(source, root)
            output = result.stdout
            result = subprocess.run([sys.executable, str(BUNDLE)],
                                    check=True, capture_output=True, text=True,
                                    cwd=directory, env=env)
            assert result.stdout == "submit" + suffix + "\n"
            submitted = (directory / ("submit" + suffix)).read_text()
            check_blank_lines(submitted)
            assert submitted == output
            print(f"PASS {suffix} file and no-argument CLI")
            run(output, suffix, directory)
            run(submitted, suffix, directory)

        result = subprocess.run([sys.executable, str(BUNDLE), "bad.txt"],
                                capture_output=True, text=True, cwd=work, env=env)
        assert result.returncode != 0 and "extension" in result.stderr
        assert not result.stdout
        print("PASS unsupported extension")
        for value in (None, ""):
            missing_env = dict(env)
            if value is None:
                missing_env.pop("CPLIB")
            else:
                missing_env["CPLIB"] = value
            result = subprocess.run([sys.executable, str(BUNDLE)],
                                    capture_output=True, text=True, cwd=work, env=missing_env)
            assert result.returncode != 0 and "CPLIB" in result.stderr
            assert not result.stdout
        print("PASS missing/empty CPLIB")
        empty = work / "empty"
        empty.mkdir()
        result = subprocess.run([sys.executable, str(BUNDLE)],
                                capture_output=True, text=True, cwd=empty, env=env)
        assert result.returncode != 0
        assert "main.cpp / main.py / main.rs が見つからない" in result.stderr
        assert not result.stdout
        print("PASS missing main")


if __name__ == "__main__":
    main()
