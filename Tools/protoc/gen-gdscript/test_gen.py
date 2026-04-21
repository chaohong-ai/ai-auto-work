#!/usr/bin/env python3
"""
Regression tests for protoc-gen-gdscript.

Verifies that the generator produces valid GDScript for the project's real
proto files and rejects unknown scalar types with a non-zero exit code.

Usage:
  # From repo root
  python3 Tools/protoc/gen-gdscript/test_gen.py
  # Or via pytest
  pytest Tools/protoc/gen-gdscript/test_gen.py
"""
import os
import re
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
)
SCRIPT = os.path.join(REPO_ROOT, "Tools", "protoc", "gen-gdscript", "protoc-gen-gdscript")
PROTO_DIR = os.path.join(REPO_ROOT, "GameServer", "proto")

# These patterns indicate the generator is treating a proto scalar/enum type
# as a GDScript class name, which is always wrong.
_ILLEGAL_PATTERNS = [
    r"\buint32\.from_bytes\(",
    r"\bint32\.from_bytes\(",
    r"\bsint32\.from_bytes\(",
    r"\buint64\.from_bytes\(",
    r"\bint64\.from_bytes\(",
    r"\bsint64\.from_bytes\(",
    r"\bbool\.from_bytes\(",
    r"\bstring\.from_bytes\(",
    r"\bfloat\.from_bytes\(",
    r"\bdouble\.from_bytes\(",
]


def _run_generator(proto_dir: str, out_dir: str) -> tuple:
    """Run the generator; return (returncode, stdout, stderr)."""
    result = subprocess.run(
        [sys.executable, SCRIPT,
         f"--proto_path={proto_dir}",
         f"--gdscript_out={out_dir}"],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout, result.stderr


def test_no_illegal_patterns():
    """Generated GDScript must not contain proto-type-name method calls."""
    with tempfile.TemporaryDirectory() as tmpdir:
        rc, _, stderr = _run_generator(PROTO_DIR, tmpdir)
        assert rc == 0, f"Generator failed (exit {rc}):\n{stderr}"

        failures = []
        for fname in os.listdir(tmpdir):
            if not fname.endswith(".gd"):
                continue
            content = open(os.path.join(tmpdir, fname), encoding="utf-8").read()
            for pat in _ILLEGAL_PATTERNS:
                if re.search(pat, content):
                    failures.append(f"{fname}: matched illegal pattern {pat!r}")

        assert not failures, "Illegal patterns found in generated output:\n" + "\n".join(failures)


def test_uint32_field_generates_as_int():
    """ResError.code (uint32) and RspEnterLobby.level (uint32) must generate as int."""
    with tempfile.TemporaryDirectory() as tmpdir:
        rc, _, _ = _run_generator(PROTO_DIR, tmpdir)
        assert rc == 0

        common = open(os.path.join(tmpdir, "common_pb.gd"), encoding="utf-8").read()
        # var code: int = 0  (not Variant = null)
        assert re.search(r"\bvar code: int = 0\b", common), \
            "ResError.code should be 'int = 0' not Variant"
        # uses varint encoding, not bytes
        assert "_encode_varint_f(_buf, 1, code)" in common, \
            "ResError.code should use _encode_varint_f, not _encode_bytes_f"

        lobby = open(os.path.join(tmpdir, "lobby_pb.gd"), encoding="utf-8").read()
        assert re.search(r"\bvar level: int = 0\b", lobby), \
            "RspEnterLobby.level should be 'int = 0' not Variant"
        assert "_encode_varint_f(_buf, 3, level)" in lobby, \
            "RspEnterLobby.level should use _encode_varint_f"


def test_unknown_scalar_type_exits_nonzero():
    """Generator must exit non-zero when a proto contains an unrecognised type."""
    bad_proto = (
        "syntax = \"proto3\";\n"
        "package test;\n"
        "message Broken {\n"
        "  fixed32 val = 1;  // not supported\n"
        "}\n"
    )
    with tempfile.TemporaryDirectory() as proto_dir, \
         tempfile.TemporaryDirectory() as out_dir:
        proto_path = os.path.join(proto_dir, "broken.proto")
        with open(proto_path, "w", encoding="utf-8") as fh:
            fh.write(bad_proto)
        rc, _, _ = _run_generator(proto_dir, out_dir)
        assert rc != 0, \
            "Generator should exit non-zero for proto with unsupported type 'fixed32'"


def test_enum_field_as_int():
    """A message field whose type is an enum defined in the same file generates as int."""
    proto_src = (
        "syntax = \"proto3\";\n"
        "package test;\n"
        "enum Status { UNKNOWN = 0; ACTIVE = 1; }\n"
        "message Item {\n"
        "  Status state = 1;\n"
        "  string name  = 2;\n"
        "}\n"
    )
    with tempfile.TemporaryDirectory() as proto_dir, \
         tempfile.TemporaryDirectory() as out_dir:
        proto_path = os.path.join(proto_dir, "item.proto")
        with open(proto_path, "w", encoding="utf-8") as fh:
            fh.write(proto_src)
        rc, _, stderr = _run_generator(proto_dir, out_dir)
        assert rc == 0, f"Generator failed (exit {rc}):\n{stderr}"

        content = open(os.path.join(out_dir, "item_pb.gd"), encoding="utf-8").read()
        # Enum field should be declared as int, not Variant
        assert re.search(r"\bvar state: int = 0\b", content), \
            "Enum field 'state' should generate as 'int = 0', not Variant"
        # Enum field should use varint encoding, not bytes
        assert "_encode_varint_f(_buf, 1, state)" in content, \
            "Enum field 'state' should use _encode_varint_f"
        # Must NOT generate .to_bytes() call on enum field
        assert "state.to_bytes()" not in content, \
            "Enum field 'state' must not call .to_bytes()"


def _run_all():
    tests = [
        test_no_illegal_patterns,
        test_uint32_field_generates_as_int,
        test_unknown_scalar_type_exits_nonzero,
        test_enum_field_as_int,
    ]
    passed = 0
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS  {t.__name__}")
            passed += 1
        except AssertionError as exc:
            print(f"  FAIL  {t.__name__}: {exc}")
            failed += 1
        except Exception as exc:
            print(f"  ERROR {t.__name__}: {exc}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(_run_all())
