#!/usr/bin/env python3
"""Regression checks for editor saves, revisions and local HTTP boundaries."""
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, build_opener, ProxyHandler

import regional_editor as editor


class EditorSaveTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.blueprints = self.root / "blueprints"
        self.compiled = self.root / "compiled"
        self.blueprints.mkdir()
        self.compiled.mkdir()
        self.patchers = [patch.object(editor, "BLUEPRINT_DIR", self.blueprints),
                         patch.object(editor, "COMPILED_DIR", self.compiled)]
        for item in self.patchers:
            item.start()
        self.path = self.blueprints / "test_map.json"
        self.output = self.compiled / "test_map.json"
        self.blueprint = {"scenario": {"id": "test_map", "name": "Test battlefield"}}
        self.path.write_bytes(editor.json_bytes(self.blueprint))
        self.output.write_bytes(b'{"previous": true}\n')

    def tearDown(self):
        for item in reversed(self.patchers):
            item.stop()
        self.directory.cleanup()

    def test_only_known_blueprints_can_be_resolved(self):
        for value in ["../test_map", "../../etc/passwd", "/tmp/test_map", "missing"]:
            with self.subTest(value=value), self.assertRaises(editor.EditorError):
                editor.blueprint_path(value)
        self.assertEqual(editor.blueprint_path("test_map"), self.path)

    def test_invalid_build_leaves_both_files_unchanged(self):
        before = (self.path.read_bytes(), self.output.read_bytes())
        with patch.object(editor, "compile_validated", side_effect=editor.EditorError("Road crosses water.")):
            with self.assertRaisesRegex(editor.EditorError, "Road crosses water"):
                editor.save_map("test_map", self.blueprint, editor.revision(self.path))
        self.assertEqual(before, (self.path.read_bytes(), self.output.read_bytes()))

    def test_external_change_rejected_before_compiling(self):
        old = editor.revision(self.path)
        self.path.write_text('{"newer": true}\n')
        with patch.object(editor, "compile_validated") as compile_map:
            with self.assertRaises(editor.EditorError) as caught:
                editor.save_map("test_map", self.blueprint, old)
            self.assertEqual(caught.exception.status, 409)
            compile_map.assert_not_called()
        self.assertEqual(self.path.read_text(), '{"newer": true}\n')

    def test_external_change_during_compilation_is_preserved(self):
        old = editor.revision(self.path)
        def compile_map(*_):
            self.path.write_text('{"external": true}\n')
            return {"compiled": True}
        with patch.object(editor, "compile_validated", side_effect=compile_map):
            with self.assertRaises(editor.EditorError) as caught:
                editor.save_map("test_map", self.blueprint, old)
            self.assertEqual(caught.exception.status, 409)
        self.assertEqual(self.path.read_text(), '{"external": true}\n')
        self.assertEqual(self.output.read_text(), '{"previous": true}\n')

    def test_successful_save_uses_canonical_serialization(self):
        from build_region_maps import encode_json
        result = {"id": "test_map", "map_renderer": "harbor", "blocks": [[1, 2, 3, 4]]}
        changed = {"scenario": {"id": "test_map", "name": "Renamed"}}
        with patch.object(editor, "compile_validated", return_value=result):
            saved = editor.save_map("test_map", changed, editor.revision(self.path))
        self.assertTrue(saved["saved"])
        self.assertEqual(json.loads(self.path.read_text()), changed)
        self.assertEqual(self.output.read_text(), encode_json(result))
        self.assertEqual(saved["revision"], editor.revision(self.path))
        self.assertFalse(list(self.root.rglob(".regional-*")))

    def test_failed_second_replace_restores_source(self):
        before = self.path.read_bytes()
        replace = Path.replace
        def fail_second(path, target):
            if target == self.output:
                raise OSError("Simulated write failure")
            return replace(path, target)
        with patch.object(Path, "replace", fail_second):
            with self.assertRaises(OSError):
                editor.replace_pair(self.path, b'{"changed":true}', self.output, b'{"new":true}')
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(self.output.read_text(), '{"previous": true}\n')
        self.assertFalse(list(self.root.rglob(".regional-*")))


class EditorHTTPTests(unittest.TestCase):
    def setUp(self):
        self.server = editor.EditorServer(("127.0.0.1", 0))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"
        self.opener = build_opener(ProxyHandler({}))

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def request(self, path, data=None, **headers):
        request = Request(self.base + path, data=data, headers=headers)
        try:
            with self.opener.open(request, timeout=3) as response:
                return response.status, response.read()
        except HTTPError as error:
            return error.code, error.read()

    def test_api_rejects_missing_token_and_foreign_origin(self):
        self.assertEqual(self.request("/api/catalog")[0], 403)
        self.assertEqual(self.request("/api/catalog", Authorization="Bearer " + self.server.token,
                                      Origin="https://unrelated.example")[0], 403)

    def test_preview_does_not_invoke_save(self):
        with patch.object(editor, "compile_validated", return_value={"id": "test_map"}), patch.object(editor, "save_map") as save:
            code, body = self.request("/api/preview", json.dumps({"id": "test_map", "blueprint": {}}).encode(),
                                      Authorization="Bearer " + self.server.token, **{"Content-Type": "application/json"})
            self.assertEqual(code, 200)
            self.assertFalse(json.loads(body)["saved"])
            save.assert_not_called()

    def test_invalid_json_and_unknown_routes_are_rejected(self):
        headers = {"Authorization": "Bearer " + self.server.token, "Content-Type": "application/json"}
        self.assertEqual(self.request("/api/save", b'{"x":NaN}', **headers)[0], 400)
        self.assertEqual(self.request("/api/save", b'[1,2]', **headers)[0], 400)
        self.assertEqual(self.request("/api/unknown", b'{}', **headers)[0], 404)


if __name__ == "__main__":
    unittest.main()
