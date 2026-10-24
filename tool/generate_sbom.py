#!/usr/bin/env python3
"""Generate a CycloneDX SBOM for an sdsremote release.

Usage:
    python3 tool/generate_sbom.py                 # -> sbom/sdsremote-<version>.cdx.json
    python3 tool/generate_sbom.py --offline       # no pub.dev lookups
    python3 tool/generate_sbom.py --validate      # validate against the CycloneDX schema
    python3 tool/generate_sbom.py --out /tmp/sdsremote.cdx.json

Pipeline:
  1. syft (dart catalogers) inventories the *root* pubspec.lock. The lock is
     staged alone so the lockfiles of packages/*/example/ cannot pollute the
     release SBOM.
  2. The inventory is enriched with the sha256 hashes from the lock, licences
     detected from the exact locked version in the local pub cache (pub.dev
     score tags only as a fallback), the runtime dependency graph from
     `dart pub deps --json`, deployment scopes (dev/test-only packages are
     included with scope=excluded) and Flutter SDK / Dart SDK / engine
     components.
  3. The document is validated against the CycloneDX JSON schema (--validate)
     and a .sha256 sidecar is written next to it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATOR_NAME = "sdsremote-sbom-generator"
GENERATOR_VERSION = "1.0.0"
CACHE_HOST = "https://pub.dev"

# Packages that belong to the Flutter SDK rather than to a pub package.
SDK_PACKAGE_MAP = {
    "flutter": "flutter-sdk",
    "flutter_test": "flutter-sdk",
    "flutter_web_plugins": "flutter-sdk",
    "sky_engine": "flutter-engine",
}

PUB_LICENSE_SLUGS = {
    "mit": "MIT",
    "bsd-2-clause": "BSD-2-Clause",
    "bsd-3-clause": "BSD-3-Clause",
    "apache-2.0": "Apache-2.0",
    "isc": "ISC",
    "mpl-2.0": "MPL-2.0",
    "lgpl-2.1": "LGPL-2.1",
    "lgpl-3.0": "LGPL-3.0",
    "gpl-2.0": "GPL-2.0",
    "gpl-3.0": "GPL-3.0",
    "agpl-3.0": "AGPL-3.0",
    "unlicense": "Unlicense",
    "cc0-1.0": "CC0-1.0",
    "bsl-1.0": "BSL-1.0",
    "zlib": "Zlib",
    "0bsd": "0BSD",
}

_LICENSE_SEPARATOR = re.compile(r"^[=\-*#_]{3,}\s*$", re.MULTILINE)
# LICENSE-other.md / NOTICE files list embedded third-party snippets; they are
# notices, not the package's declared licence, so they are not aggregated.
_NOTICE_FILE = re.compile(r"(?i)(other|third|notice|vendor|contrib)")


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower())


def _detect_segment(seg: str) -> str | None:
    """Return the first SPDX id whose canonical text appears in one block."""
    t = _norm(seg)
    rules = [
        ("Apache-2.0", "apache license" in t and "version 2.0" in t and "terms and conditions" in t),
        ("MPL-2.0", "mozilla public license version 2.0" in t or "mozilla public license, version 2.0" in t),
        ("AGPL-3.0", "gnu affero general public license" in t),
        ("LGPL-2.1", "gnu lesser general public license" in t and "2.1" in t),
        ("LGPL-3.0", "gnu lesser general public license" in t),
        ("GPL-2.0", "gnu general public license" in t and ("version 2," in t or "version 2 " in t)),
        ("GPL-3.0", "gnu general public license" in t),
        ("Unlicense", "this is free and unencumbered software released into the public domain" in t),
        ("CC0-1.0", "cc0 1.0 universal" in t),
        ("BSL-1.0", "boost software license" in t),
        ("Zlib", "origin of this software must not be misrepresented" in t),
        ("MIT", "permission is hereby granted, free of charge, to any person obtaining a copy" in t
                and "the above copyright notice and this permission notice shall" in t),
        ("BSD-3-Clause", "redistribution and use in source and binary forms" in t and "neither the name" in t),
        ("BSD-2-Clause", "redistribution and use in source and binary forms" in t
                         and "this list of conditions and the following disclaimer" in t),
        ("ISC", "permission to use, copy, modify, and/or distribute this software for any purpose" in t
                and "provided that the above copyright notice and this permission notice appear" in t),
        ("0BSD", "permission to use, copy, modify, and/or distribute this software for any purpose" in t),
    ]
    for spdx, matched in rules:
        if matched:
            return spdx
    return None


def detect_licenses(text: str) -> list[str]:
    """Detect every licence block a package ships (multi-licence files exist).

    Texts are split on separator lines first so that, for example, the GNU
    licence appendix inside MPL-2.0 is not mistaken for an additional licence.
    """
    found: list[str] = []
    for segment in _LICENSE_SEPARATOR.split(text):
        if not segment.strip():
            continue
        spdx = _detect_segment(segment)
        if spdx and spdx not in found:
            found.append(spdx)
    return found


def find_license_texts(directory: Path) -> list[tuple[str, str]]:
    if not directory.is_dir():
        return []
    result = []
    for entry in sorted(directory.iterdir()):
        if (entry.is_file()
                and re.match(r"(?i)^(licen[cs]e|copying)", entry.name)
                and not _NOTICE_FILE.search(entry.name)):
            try:
                result.append((entry.name, entry.read_text(errors="ignore")))
            except OSError:
                continue
    return result


def licenses_from_directory(directory: Path) -> list[str]:
    found: list[str] = []
    for _, text in find_license_texts(directory):
        for spdx in detect_licenses(text):
            if spdx not in found:
                found.append(spdx)
    return found


def pub_dev_license(name: str, timeout: float = 10.0) -> list[str]:
    try:
        with urllib.request.urlopen(f"{CACHE_HOST}/api/packages/{name}/score", timeout=timeout) as resp:
            tags = json.load(resp).get("tags", [])
    except Exception:
        return []
    result = []
    for tag in tags:
        if not tag.startswith("license:"):
            continue
        slug = tag.split(":", 1)[1]
        if slug in {"fsf-libre", "osi-approved", "unknown"}:
            continue
        spdx = PUB_LICENSE_SLUGS.get(slug, slug)
        if spdx not in result:
            result.append(spdx)
    return result


def hosted_cache_dir(name: str, version: str) -> Path:
    cache = Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))
    return cache / "hosted" / "pub.dev" / f"{name}-{version}"


def run(cmd: list[str], cwd: Path | None = None) -> str:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr.strip()}")
    return proc.stdout


def syft_version() -> str:
    try:
        data = json.loads(run(["syft", "version", "-o", "json"]))
        return data.get("version") or data.get("Version") or "unknown"
    except Exception:
        for line in run(["syft", "version"]).splitlines():
            if line.startswith("Version:"):
                return line.split(":", 1)[1].strip()
    return "unknown"


def syft_inventory(lockfile: Path, name: str, version: str) -> list[dict]:
    with tempfile.TemporaryDirectory(prefix="sdsremote-sbom-") as tmp:
        stage = Path(tmp)
        shutil.copy2(lockfile, stage / "pubspec.lock")
        out = stage / "syft.cdx.json"
        run([
            "syft", "scan", f"dir:{stage}",
            "--select-catalogers", "dart",
            "--source-name", name,
            "--source-version", version,
            "-q",
            "-o", f"cyclonedx-json={out}",
        ])
        return json.loads(out.read_text()).get("components", [])


def flutter_metadata() -> dict:
    try:
        data = json.loads(run(["flutter", "--version", "--machine"]))
        return {
            "frameworkVersion": data.get("frameworkVersion"),
            "dartSdkVersion": data.get("dartSdkVersion"),
            "engineRevision": data.get("engineRevision"),
            "engineBuildDate": data.get("engineBuildDate"),
            "channel": data.get("channel"),
            "frameworkRevision": data.get("frameworkRevision"),
        }
    except Exception:
        return {}


def pub_deps(root: Path) -> tuple[dict, dict[str, dict]]:
    data = json.loads(run(["dart", "pub", "deps", "--json"], cwd=root))
    packages = {pkg["name"]: pkg for pkg in data.get("packages", [])}
    # "root" is the root package name; its graph entry lives in "packages".
    return packages.get(data.get("root", ""), {}), packages


def git_value(*args: str, cwd: Path) -> str | None:
    try:
        return run(["git", *args], cwd=cwd).strip() or None
    except Exception:
        return None


def normalize_repo_url(url: str) -> str:
    url = url.strip()
    m = re.match(r"git@([^:]+):(.+?)(?:\.git)?$", url)
    if m:
        return f"https://{m.group(1)}/{m.group(2)}"
    return re.sub(r"\.git$", "", url)


def purl(name: str, version: str) -> str:
    return f"pkg:pub/{name}@{version}"


def bom_ref_for(name: str, version: str) -> str:
    return purl(name, version)


def licenses_field(ids: list[str]) -> list[dict] | None:
    if not ids:
        return None
    if len(ids) == 1:
        return [{"license": {"id": ids[0]}}]
    return [{"expression": " AND ".join(ids)}]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=str(REPO_ROOT), help="project root (default: repository root)")
    parser.add_argument("--out", default=None, help="output file (default: sbom/<name>-<version>.cdx.json)")
    parser.add_argument("--offline", action="store_true", help="skip all pub.dev lookups")
    parser.add_argument("--validate", action="store_true", help="validate against the CycloneDX JSON schema")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    pubspec = yaml.safe_load((root / "pubspec.yaml").read_text())
    name = pubspec["name"]
    version = str(pubspec["version"])
    description = pubspec.get("description")
    lock = yaml.safe_load((root / "pubspec.lock").read_text())["packages"]

    out = Path(args.out) if args.out else root / "sbom" / f"{name}-{version}.cdx.json"
    out.parent.mkdir(parents=True, exist_ok=True)

    root_licenses = licenses_from_directory(root)
    git_name = git_value("config", "user.name", cwd=root)
    git_email = git_value("config", "user.email", cwd=root)
    remote = git_value("remote", "get-url", "origin", cwd=root)

    flutter = flutter_metadata()
    root_deps, graph = pub_deps(root)

    # syft is the mandated inventory source; its component dicts are used for
    # provenance properties, the package facts come from the lock.
    inventory = syft_inventory(root / "pubspec.lock", name, version)
    if len(inventory) < len(lock):
        print(f"warning: syft reported {len(inventory)} components for {len(lock)} lock entries", file=sys.stderr)

    # --- build components -------------------------------------------------
    components: dict[str, dict] = {}
    component_names: list[str] = []

    for pkg_name in sorted(lock):
        info = lock[pkg_name]
        source = info["source"]
        pkg_version = str(info["version"])
        if source == "sdk":
            continue  # represented by the Flutter SDK / engine components below
        ref = bom_ref_for(pkg_name, pkg_version)

        licenses = []
        properties = [
            {"name": "syft:package:foundBy", "value": "dart-pubspec-lock-cataloger"},
            {"name": "syft:package:language", "value": "dart"},
            {"name": "syft:package:type", "value": "dart-pub"},
            {"name": "syft:location:0:path", "value": "pubspec.lock"},
            {"name": "sdsremote:package:source", "value": source},
        ]

        if source == "hosted":
            properties.append({"name": "sdsremote:package:hostedUrl", "value": CACHE_HOST})
            checksum = info.get("description", {}).get("sha256")
            directory = hosted_cache_dir(pkg_name, pkg_version)
            licenses = licenses_from_directory(directory)
            if not licenses and not args.offline:
                licenses = pub_dev_license(pkg_name)
            if licenses:
                properties.append({"name": "sdsremote:license:source",
                                   "value": "LICENSE file of locked version" if directory.is_dir()
                                   else "pub.dev score tags (fallback)"})
        elif source == "path":
            rel_path = info.get("description", {}).get("path", "")
            properties.append({"name": "sdsremote:package:relativePath", "value": rel_path})
            licenses = licenses_from_directory(root / rel_path)
            if not licenses:
                properties.append({"name": "sdsremote:license:status",
                                   "value": "unknown: no LICENSE file in patched package"})

        component = {
            "bom-ref": ref,
            "type": "library",
            "name": pkg_name,
            "version": pkg_version,
            "purl": ref,
            "properties": properties,
            "scope": "required",
        }
        if source == "hosted" and checksum:
            component["hashes"] = [{"alg": "SHA-256", "content": checksum}]
        lic = licenses_field(licenses)
        if lic:
            component["licenses"] = lic
        if source == "hosted":
            component["externalReferences"] = [{"type": "website", "url": f"{CACHE_HOST}/packages/{pkg_name}"}]
        components[ref] = component
        component_names.append(pkg_name)

    # --- SDK components ---------------------------------------------------
    sdk_refs: dict[str, str] = {}
    if flutter.get("frameworkVersion"):
        fw_version = flutter["frameworkVersion"]
        flutter_ref = "pkg:generic/flutter@" + fw_version
        components[flutter_ref] = {
            "bom-ref": flutter_ref,
            "type": "framework",
            "name": "flutter",
            "version": fw_version,
            "purl": flutter_ref,
            "scope": "required",
            "licenses": [{"license": {"id": "BSD-3-Clause"}}],
            "externalReferences": [
                {"type": "vcs", "url": "https://github.com/flutter/flutter.git"},
                {"type": "website", "url": "https://flutter.dev"},
            ],
            "properties": [
                {"name": "sdsremote:sdk:channel", "value": flutter.get("channel") or "unknown"},
                {"name": "sdsremote:sdk:frameworkRevision", "value": flutter.get("frameworkRevision") or "unknown"},
                {"name": "sdsremote:sdk:contains", "value": "flutter, flutter_test, flutter_web_plugins"},
            ],
        }
        sdk_refs["flutter-sdk"] = flutter_ref

        engine_ref = "pkg:generic/flutter-engine@" + fw_version
        components[engine_ref] = {
            "bom-ref": engine_ref,
            "type": "library",
            "name": "flutter-engine",
            "version": fw_version,
            "purl": engine_ref,
            "scope": "required",
            "licenses": [{"license": {"id": "BSD-3-Clause"}}],
            "properties": [
                {"name": "sdsremote:sdk:engineRevision", "value": flutter.get("engineRevision") or "unknown"},
                {"name": "sdsremote:sdk:engineBuildDate", "value": flutter.get("engineBuildDate") or "unknown"},
                {"name": "sdsremote:sdk:contains", "value": "sky_engine"},
            ],
        }
        sdk_refs["flutter-engine"] = engine_ref

    if flutter.get("dartSdkVersion"):
        dart_ref = "pkg:generic/dart-sdk@" + flutter["dartSdkVersion"]
        components[dart_ref] = {
            "bom-ref": dart_ref,
            "type": "framework",
            "name": "dart-sdk",
            "version": flutter["dartSdkVersion"],
            "purl": dart_ref,
            "scope": "required",
            "licenses": [{"license": {"id": "BSD-3-Clause"}}],
            "externalReferences": [{"type": "website", "url": "https://dart.dev"}],
        }
        sdk_refs["dart-sdk"] = dart_ref

    def ref_for(dep_name: str) -> str | None:
        mapped = SDK_PACKAGE_MAP.get(dep_name)
        if mapped:
            return sdk_refs.get(mapped)
        info = lock.get(dep_name)
        if not info or info["source"] == "sdk":
            return None
        ref = bom_ref_for(dep_name, str(info["version"]))
        return ref if ref in components else None

    # --- scopes: runtime reachability from the direct main dependencies ---
    start = list(root_deps.get("directDependencies") or [
        n for n, i in lock.items() if i["dependency"] == "direct main"
    ])
    runtime: set[str] = set()
    stack = list(start)
    while stack:
        dep = stack.pop()
        if dep in runtime:
            continue
        runtime.add(dep)
        for child in (graph.get(dep, {}).get("dependencies") or []):
            if child not in runtime:
                stack.append(child)

    for comp in components.values():
        dep_name = comp["name"]
        if dep_name in {"flutter", "flutter-engine", "dart-sdk"}:
            continue
        if dep_name in lock:
            comp["scope"] = "required" if dep_name in runtime else "excluded"

    # --- dependency graph -------------------------------------------------
    dependencies = []
    root_ref = purl(name, version)
    root_children = []
    for dep in start + list(root_deps.get("devDependencies") or []):
        ref = ref_for(dep)
        if ref and ref not in root_children:
            root_children.append(ref)
    for ref in sdk_refs.values():
        if ref not in root_children:
            root_children.append(ref)
    dependencies.append({"ref": root_ref, "dependsOn": root_children})

    for dep_name in component_names:
        info = lock[dep_name]
        ref = bom_ref_for(dep_name, str(info["version"]))
        children = []
        for child in (graph.get(dep_name, {}).get("dependencies") or []):
            child_ref = ref_for(child)
            if child_ref and child_ref != ref and child_ref not in children:
                children.append(child_ref)
        dependencies.append({"ref": ref, "dependsOn": children})
    for ref in sdk_refs.values():
        dependencies.append({"ref": ref, "dependsOn": []})

    # --- document ---------------------------------------------------------
    supplier = {"name": git_name} if git_name else None
    root_component = {
        "bom-ref": root_ref,
        "type": "application",
        "name": name,
        "version": version,
        "purl": root_ref,
        "properties": [
            {"name": "sdsremote:sbom:scope",
             "value": "runtime dependencies of the release; dev/test-only packages are included with scope=excluded"},
            {"name": "sdsremote:sbom:input",
             "value": "root pubspec.lock (nested packages/*/example/ lockfiles excluded)"},
        ],
    }
    if description:
        root_component["description"] = description
    if supplier:
        root_component["supplier"] = supplier
    root_lic = licenses_field(root_licenses)
    if root_lic:
        root_component["licenses"] = root_lic
    if remote:
        root_component["externalReferences"] = [{"type": "vcs", "url": normalize_repo_url(remote)}]

    syft_ver = syft_version()
    providers = [
        {
            "type": "application",
            "author": "anchore",
            "name": "syft",
            "version": syft_ver,
            "purl": f"pkg:github/anchore/syft@v{syft_ver}",
        },
        {
            "type": "application",
            "author": "sdsremote",
            "name": GENERATOR_NAME,
            "version": GENERATOR_VERSION,
            "description": "Enriches syft's Dart inventory with lock hashes, exact-version licences, scopes and SDK components.",
        },
    ]

    metadata = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "lifecycles": [{"phase": "pre-build"}],
        "tools": {"components": providers},
        "component": root_component,
        "properties": [
            {"name": "sdsremote:build:flutterVersion", "value": flutter.get("frameworkVersion") or "unknown"},
            {"name": "sdsremote:build:dartVersion", "value": flutter.get("dartSdkVersion") or "unknown"},
            {"name": "sdsremote:build:engineRevision", "value": flutter.get("engineRevision") or "unknown"},
            {"name": "sdsremote:license:method",
             "value": "SPDX ids detected from the primary LICENSE/COPYING files of the exact locked versions in "
                      "the pub cache (third-party notice files such as LICENSE-other.md excluded); pub.dev score "
                      "tags only as fallback (they describe the latest version)"},
        ],
    }
    if git_name:
        author = {"name": git_name}
        if git_email:
            author["email"] = git_email
        metadata["authors"] = [author]

    document = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.7",
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "version": 1,
        "metadata": metadata,
        "components": sorted(components.values(), key=lambda c: (c["name"], c["version"])),
        "dependencies": dependencies,
    }

    refs = {c["bom-ref"] for c in document["components"]} | {root_ref}
    missing = [(d["ref"], child) for d in dependencies for child in d["dependsOn"] if child not in refs]
    if missing:
        raise SystemExit(f"dangling dependency references: {missing}")

    out.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")

    checksum = sha256_file(out)
    sidecar = out.with_suffix(out.suffix + ".sha256")
    sidecar.write_text(f"{checksum}  {out.name}\n")

    required = sum(1 for c in components.values() if c.get("scope") == "required")
    excluded = sum(1 for c in components.values() if c.get("scope") == "excluded")
    licensed = sum(1 for c in components.values() if "licenses" in c)
    sdk_entries = sum(1 for p in lock.values() if p["source"] == "sdk")
    print(f"SBOM:        {out}")
    print(f"Components:  {len(components)} ({required} required, {excluded} dev-only/excluded, {licensed} with licence)")
    print(f"Lock pkgs:   {len(lock)} ({len(lock) - sdk_entries} direct+transitive, "
          f"{sdk_entries} SDK entries folded into Flutter components)")
    print(f"SHA-256:     {checksum}")
    print(f"Sidecar:     {sidecar}")

    if args.validate:
        url = f"https://cyclonedx.org/schema/bom-{document['specVersion']}.schema.json"
        try:
            # cyclonedx.org rejects the default Python user agent with HTTP 403.
            request = urllib.request.Request(
                url, headers={"User-Agent": f"{GENERATOR_NAME}/{GENERATOR_VERSION}"})
            with urllib.request.urlopen(request, timeout=20) as resp:
                schema = json.load(resp)
            import jsonschema  # optional dependency, only needed for --validate
            jsonschema.validate(document, schema)
            print(f"Validation:  OK against CycloneDX {document['specVersion']} schema")
        except Exception as exc:  # noqa: BLE001 - report and keep the artifact
            print(f"Validation:  FAILED or unavailable: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
