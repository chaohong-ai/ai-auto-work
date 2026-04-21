#!/usr/bin/env python3
"""
Regression tests for protoc-gen-gdscript.

Tests are based on the real GameServer proto files and assert:
  - uint32 fields generate as `int`, not `Variant`
  - Enum fields generate as `int` (varint), not nested-message calls
  - Generated output contains no `.from_bytes()` calls on type names
  - Generated output contains no `Variant = null` for scalar/enum fields

Run with:
    python3 test_protoc_gen_gdscript.py
"""

import os
import re
import sys
import tempfile
import textwrap
import types
import unittest

# ---------------------------------------------------------------------------
# Load the generator module from a hyphenated filename
# ---------------------------------------------------------------------------
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.normpath(os.path.join(_SCRIPT_DIR, "..", "..", ".."))
_PROTO_DIR = os.path.join(_REPO_ROOT, "GameServer", "proto")
_GENERATOR = os.path.join(_SCRIPT_DIR, "protoc-gen-gdscript")

_gen_mod = types.ModuleType("protoc_gen_gdscript")
_gen_mod.__file__ = _GENERATOR
with open(_GENERATOR, encoding="utf-8") as _fh:
    exec(compile(_fh.read(), _GENERATOR, "exec"), _gen_mod.__dict__)  # noqa: S102

parse_proto_file = _gen_mod.parse_proto_file
render_gdscript = _gen_mod.render_gdscript


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _gen(proto_path: str) -> str:
    """Parse a .proto file and return the rendered GDScript string."""
    return render_gdscript(parse_proto_file(proto_path))


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestUint32Field(unittest.TestCase):
    """C-1 regression: uint32 must generate as int, not Variant."""

    def test_common_proto_resError_code_is_int(self):
        """ResError.code (uint32) must be `var code: int = 0`."""
        out = _gen(os.path.join(_PROTO_DIR, "common.proto"))
        self.assertIn("var code: int = 0", out,
                      "uint32 field 'code' must generate as int, not Variant")

    def test_lobby_proto_RspEnterLobby_level_is_int(self):
        """RspEnterLobby.level (uint32) must be `var level: int = 0`."""
        out = _gen(os.path.join(_PROTO_DIR, "lobby.proto"))
        self.assertIn("var level: int = 0", out,
                      "uint32 field 'level' must generate as int, not Variant")

    def test_gate_inner_success_fail_count_is_int(self):
        """RspBroadcast.success_count / fail_count (uint32) must generate as int."""
        out = _gen(os.path.join(_PROTO_DIR, "gate_inner.proto"))
        self.assertIn("var success_count: int = 0", out)
        self.assertIn("var fail_count: int = 0", out)

    def test_no_variant_null_in_key_protos(self):
        """No uint32 field should produce 'Variant = null'."""
        for proto_file in ["common.proto", "lobby.proto", "gate_inner.proto"]:
            with self.subTest(proto=proto_file):
                out = _gen(os.path.join(_PROTO_DIR, proto_file))
                self.assertNotIn("Variant = null", out,
                                 f"{proto_file}: 'Variant = null' found")

    def test_no_uint32_from_bytes_call(self):
        """No generated file should call from_bytes() on the type name 'uint32'."""
        for proto_file in ["common.proto", "lobby.proto", "gate_inner.proto", "account.proto"]:
            with self.subTest(proto=proto_file):
                out = _gen(os.path.join(_PROTO_DIR, proto_file))
                self.assertNotIn("uint32.from_bytes(", out,
                                 f"{proto_file}: illegal `uint32.from_bytes()` call found")

    def test_uint32_uses_encode_varint_f(self):
        """uint32 field to_bytes must use _encode_varint_f, not _encode_bytes_f."""
        out = _gen(os.path.join(_PROTO_DIR, "common.proto"))
        # code field is the only field; ensure varint path is taken
        self.assertIn("_encode_varint_f(_buf, 1, code)", out)


class TestEnumFieldAsVarint(unittest.TestCase):
    """C-1 regression: enum fields must generate as int (varint), not nested-message."""

    def setUp(self):
        self._tmp = tempfile.mkdtemp()

    def _gen_inline(self, proto_src: str) -> str:
        path = os.path.join(self._tmp, "inline.proto")
        with open(path, "w", encoding="utf-8") as f:
            f.write(proto_src)
        return _gen(path)

    def test_enum_field_generates_as_int(self):
        out = self._gen_inline(textwrap.dedent("""\
            syntax = "proto3";
            enum Status {
              STATUS_DEFAULT = 0;
              STATUS_OK = 1;
            }
            message Msg {
              Status status = 1;
            }
        """))
        self.assertIn("var status: int = 0", out,
                      "Enum field must generate as int, not Variant")
        self.assertNotIn("Status.from_bytes(", out,
                         "Enum field must not call from_bytes() on the enum type")
        self.assertIn("_encode_varint_f", out,
                      "Enum field to_bytes must use varint encoding")

    def test_enum_field_decode_uses_varint(self):
        out = self._gen_inline(textwrap.dedent("""\
            syntax = "proto3";
            enum Color { COLOR_DEFAULT = 0; COLOR_RED = 1; }
            message Palette { Color primary = 1; }
        """))
        self.assertIn("_decode_varint", out,
                      "Enum field from_bytes must use _decode_varint")

    def test_repeated_enum_field_generates_array(self):
        out = self._gen_inline(textwrap.dedent("""\
            syntax = "proto3";
            enum Dir { DIR_DEFAULT = 0; DIR_NORTH = 1; }
            message Move { repeated Dir dirs = 1; }
        """))
        self.assertIn("var dirs: Array = []", out)

    def test_enum_field_no_nested_message_decode(self):
        """Enum field must NOT call TypeName.from_bytes() (the nested-message path)."""
        out = self._gen_inline(textwrap.dedent("""\
            syntax = "proto3";
            enum Kind { KIND_DEFAULT = 0; KIND_A = 1; }
            message Thing { Kind kind = 1; }
        """))
        # Must not generate: Kind.from_bytes(_r[0])
        self.assertNotIn("Kind.from_bytes(", out,
                         "Enum field must not generate nested-message decode call")


class TestWhitelistValidation(unittest.TestCase):
    """C-1 regression: unsupported types must raise ValueError (non-zero exit)."""

    def setUp(self):
        self._tmp = tempfile.mkdtemp()

    def _proto(self, content: str) -> str:
        path = os.path.join(self._tmp, "bad.proto")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return path

    def test_fixed32_field_raises_ValueError(self):
        path = self._proto(textwrap.dedent("""\
            syntax = "proto3";
            message Foo { fixed32 val = 1; }
        """))
        with self.assertRaises(ValueError) as ctx:
            parse_proto_file(path)
        self.assertIn("fixed32", str(ctx.exception))

    def test_cross_file_message_ref_raises_ValueError(self):
        """A field referencing a message not defined in this file must raise ValueError."""
        path = self._proto(textwrap.dedent("""\
            syntax = "proto3";
            message Foo { OtherMessage nested = 1; }
        """))
        with self.assertRaises(ValueError) as ctx:
            parse_proto_file(path)
        self.assertIn("OtherMessage", str(ctx.exception))

    def test_local_message_field_is_allowed(self):
        """A field referencing a message in the same file must NOT raise."""
        path = self._proto(textwrap.dedent("""\
            syntax = "proto3";
            message Inner { int32 x = 1; }
            message Outer { Inner nested = 1; }
        """))
        try:
            parse_proto_file(path)
        except ValueError as e:
            self.fail(f"Local message reference raised ValueError: {e}")


class TestAllRealProtoFiles(unittest.TestCase):
    """Smoke: all real GameServer proto files must generate without error."""

    def test_all_proto_files_generate_clean(self):
        proto_files = [
            "account.proto", "common.proto", "gate_inner.proto",
            "lobby.proto", "match.proto", "room.proto", "team.proto",
        ]
        for fname in proto_files:
            with self.subTest(proto=fname):
                path = os.path.join(_PROTO_DIR, fname)
                try:
                    out = _gen(path)
                except ValueError as e:
                    self.fail(f"{fname} raised ValueError: {e}")
                self.assertNotIn("Variant = null", out,
                                 f"{fname}: 'Variant = null' found — unknown type leaked")
                self.assertGreater(len(out), 50, f"{fname}: suspiciously small output")


if __name__ == "__main__":
    unittest.main(verbosity=2)
