#!/usr/bin/env python3
"""Local visual editor for regional battlefield blueprints (Python stdlib only).

Run python3 tools/regional_editor.py. The browser edits source blueprints;
Preview and Save compile through the game's existing geometry pipeline. A save
is accepted only after structural and compiled-world validation succeeds.
"""
from __future__ import annotations

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import secrets
import sys
import tempfile
import urllib.parse
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
BLUEPRINT_DIR = ROOT / "resources/maps/blueprints"
COMPILED_DIR = ROOT / "resources/maps/region"
HTML = Path(__file__).with_name("regional_editor.html")
MAX_REQUEST_BYTES = 2 * 1024 * 1024


class EditorError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


def revision(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def known_blueprints() -> dict[str, Path]:
    """Only checked-in authoring locations can be opened or overwritten."""
    return {p.stem: p for p in sorted(BLUEPRINT_DIR.glob("*.json"))}


def blueprint_path(map_id: str) -> Path:
    path = known_blueprints().get(map_id)
    if path is None:
        raise EditorError("Unknown battlefield. Choose a map from the editor.", 404)
    return path


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def catalog() -> dict:
    from build_harbor_map import load_designs, load_library
    from regional_map_schema import MORPHOLOGIES
    maps = []
    for map_id, path in known_blueprints().items():
        data = json.loads(path.read_text())
        scenario = data["scenario"]
        maps.append({"id": map_id, "name": scenario["name"],
                     "size": scenario["size"], "brief": scenario.get("brief", "")})
    designs = load_designs()
    assets = load_library()
    return {"maps": maps, "designs": designs, "assets": assets, "morphologies": sorted(MORPHOLOGIES),
            "rules": ["Roads do not bridge water. Keep land routes connected.",
                      "Solid ridges block movement; elevation plateaus add walkable ground and slope constraints.",
                      "Building walls, low steps and props retain the shared physical footprints.",
                      "Generated street frontage updates on Preview; authored landmarks stay explicit."]}


def load_map(map_id: str) -> dict:
    path = blueprint_path(map_id)
    compiled = COMPILED_DIR / f"{map_id}.json"
    source = path.read_bytes()
    return {"blueprint": json.loads(source), "revision": hashlib.sha256(source).hexdigest(),
            "compiled": json.loads(compiled.read_text()) if compiled.is_file() else None}


def compile_validated(map_id: str, blueprint: object) -> dict:
    from build_region_maps import compile_blueprint
    from regional_map_schema import validate_blueprint
    blueprint_path(map_id)
    if not isinstance(blueprint, dict):
        raise EditorError("The blueprint must be a JSON object.")
    if not isinstance(blueprint.get("scenario"), dict) or blueprint["scenario"].get("id") != map_id:
        raise EditorError("The blueprint identity must match the selected battlefield.")
    errors = validate_blueprint(blueprint)
    if errors:
        raise EditorError("\n".join(errors[:40]))
    try:
        compiled = compile_blueprint(blueprint)
    except (ValueError, KeyError, TypeError, IndexError, AssertionError) as exc:
        raise EditorError(str(exc)) from exc
    return compiled


def replace_pair(first: Path, first_data: bytes, second: Path, second_data: bytes) -> None:
    """Prepare both files before replacement; restore the first on I/O failure.

    Each replacement is atomic on the destination filesystem. This is not a
    database transaction across process/power loss; the compiler can recreate
    the derived map from the source blueprint in that case.
    """
    first_old = first.read_bytes()
    temporary = []
    try:
        for destination, data in ((first, first_data), (second, second_data)):
            destination.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".regional-", delete=False) as file:
                temporary.append(Path(file.name))
                file.write(data)
        temporary[0].replace(first)
        try:
            temporary[1].replace(second)
        except OSError:
            first.write_bytes(first_old)
            raise
    finally:
        for path in temporary:
            path.unlink(missing_ok=True)


def save_map(map_id: str, blueprint: dict, expected_revision: str) -> dict:
    path = blueprint_path(map_id)
    if revision(path) != expected_revision:
        raise EditorError("This blueprint changed on disk. Export your edits, then reload before saving.", 409)
    compiled = compile_validated(map_id, blueprint)
    # Recheck after compilation so an external edit during the build is retained.
    if revision(path) != expected_revision:
        raise EditorError("The blueprint changed while building. Export your edits and reload.", 409)
    import build_region_maps
    encoder = getattr(build_region_maps, "encode_json", None)
    compiled_data = encoder(compiled).encode("utf-8") if encoder else json_bytes(compiled)
    replace_pair(path, json_bytes(blueprint), COMPILED_DIR / f"{map_id}.json", compiled_data)
    return {"compiled": compiled, "revision": revision(path), "saved": True}


class EditorServer(HTTPServer):
    # Single-threaded: the existing compiler caches geometry during compilation.
    def __init__(self, address: tuple[str, int]):
        self.token = secrets.token_urlsafe(24)
        super().__init__(address, EditorHandler)


class EditorHandler(BaseHTTPRequestHandler):
    server_version = "ForEveryDawnEditor/1"

    def log_message(self, format: str, *args: object) -> None:
        # The session token travels in a header/hash, never in the request URL.
        print(f"Editor: {format % args}", file=sys.stderr)

    def send_json(self, status: int, value: object) -> None:
        body = json_bytes(value)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def authorized(self) -> bool:
        expected = f"127.0.0.1:{self.server.server_port}"
        if self.headers.get("Host") != expected:
            self.send_json(403, {"error": "Open the local address printed by the editor launcher."})
            return False
        origin = self.headers.get("Origin")
        if origin and origin != f"http://{expected}":
            self.send_json(403, {"error": "Requests must come from this editor window."})
            return False
        if not secrets.compare_digest(self.headers.get("Authorization", ""), f"Bearer {self.server.token}"):
            self.send_json(403, {"error": "Open the complete editor link printed by the launcher."})
            return False
        return True

    def do_GET(self) -> None:
        request = urllib.parse.urlparse(self.path)
        if request.path == "/":
            body = HTML.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(body)
            return
        if not self.authorized():
            return
        try:
            if request.path == "/api/catalog":
                value = catalog()
            elif request.path == "/api/map":
                map_id = urllib.parse.parse_qs(request.query).get("id", [""])[0]
                value = load_map(map_id)
            else:
                raise EditorError("Not found.", 404)
            self.send_json(200, value)
        except EditorError as exc:
            self.send_json(exc.status, {"error": str(exc)})
        except (OSError, ValueError) as exc:
            self.send_json(500, {"error": f"Could not read the authoring files: {exc}"})

    def do_POST(self) -> None:
        if not self.authorized():
            return
        try:
            if self.path not in ("/api/preview", "/api/save"):
                raise EditorError("Not found.", 404)
            if not self.headers.get("Content-Type", "").startswith("application/json"):
                raise EditorError("Send JSON data.", 415)
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_REQUEST_BYTES:
                raise EditorError("The blueprint request must be smaller than 2 MB.", 413)
            body = json.loads(self.rfile.read(length), parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"Invalid number {value}")))
            if not isinstance(body, dict):
                raise EditorError("Expected a JSON object.")
            if self.path == "/api/save":
                value = save_map(str(body.get("id", "")), body.get("blueprint"), str(body.get("revision", "")))
            else:
                value = {"compiled": compile_validated(str(body.get("id", "")), body.get("blueprint")), "saved": False}
            self.send_json(200, value)
        except EditorError as exc:
            self.send_json(exc.status, {"error": str(exc)})
        except (ValueError, TypeError, UnicodeError) as exc:
            self.send_json(400, {"error": f"Invalid blueprint: {exc}"})
        except OSError as exc:
            self.send_json(500, {"error": f"Could not save the files: {exc}"})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0, help="Local port; default chooses a free port")
    parser.add_argument("--no-browser", action="store_true", help="Print the link without opening a browser")
    args = parser.parse_args(argv)
    if not known_blueprints():
        parser.error("No regional blueprints found. Run this from a complete regional-map checkout.")
    with EditorServer(("127.0.0.1", args.port)) as server:
        url = f"http://127.0.0.1:{server.server_port}/#{server.token}"
        print(f"For Every Dawn — regional map editor\n{url}\nKeep this terminal open. Ctrl+C stops the editor.", flush=True)
        if not args.no_browser:
            webbrowser.open(url)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nEditor stopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
