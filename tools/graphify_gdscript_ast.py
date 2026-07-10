#!/usr/bin/env python3
"""Deterministic structural extraction for GDScript (.gd) and Godot scene/resource
(.tscn/.tres) files, in the same node/edge JSON schema graphify's own AST pass
(graphify.extract) produces. Fills the gap left by graphify having no GDScript
tree-sitter grammar of its own (see graphify-out/GRAPH_REPORT.md history).

Usage:
    python3 tools/graphify_gdscript_ast.py <root> <file1> [file2 ...] > out.json

Requires the `tree-sitter-gdscript` package (PrestonKnopp/tree-sitter-gdscript)
to be installed in the interpreter running this script.
"""
import json
import re
import sys
from pathlib import Path

from tree_sitter import Language, Parser
import tree_sitter_gdscript as tsgd

_LANG = Language(tsgd.language())
_PARSER = Parser(_LANG)


def normalize(s: str) -> str:
    return re.sub(r"[^a-z0-9_]", "_", s.lower())


def stem_for(path: Path, root: Path) -> str:
    rel = path.relative_to(root)
    parts = list(rel.parts[:-1]) + [rel.stem]
    return "_".join(normalize(p) for p in parts)


def node_id(stem: str, entity: str | None = None) -> str:
    if entity is None:
        return stem
    return f"{stem}_{normalize(entity)}"


def child_by_field(node, field):
    return node.child_by_field_name(field)


def text(src: bytes, node) -> str:
    return src[node.start_byte : node.end_byte].decode("utf-8", "replace")


class GdFile:
    """One parsed .gd file: definitions + call/reference edges found in it."""

    def __init__(self, path: Path, root: Path):
        self.path = path
        self.root = root
        self.stem = stem_for(path, root)
        self.abs_path = str(path)
        src = path.read_bytes()
        self.src = src
        self.tree = _PARSER.parse(src)
        self.class_name: str | None = None
        self.extends_name: str | None = None
        self.functions: set[str] = set()
        self.signals: set[str] = set()
        self.preload_paths: list[str] = []
        self.calls: list[tuple[str, str]] = []  # (caller_func_or_file, callee_name)
        self._walk(self.tree.root_node, current_func=None)

    def _walk(self, node, current_func):
        if node.type == "class_name_statement":
            name_node = child_by_field(node, "name")
            if name_node:
                self.class_name = text(self.src, name_node)
        elif node.type == "extends_statement":
            type_node = child_by_field(node, "type")
            if type_node:
                self.extends_name = text(self.src, type_node)
        elif node.type == "signal_statement":
            name_node = child_by_field(node, "name")
            if name_node:
                self.signals.add(text(self.src, name_node))
        elif node.type == "function_definition":
            name_node = child_by_field(node, "name")
            fname = text(self.src, name_node) if name_node else None
            if fname:
                self.functions.add(fname)
            for c in node.children:
                self._walk(c, current_func=fname or current_func)
            return
        elif node.type == "call":
            ident = node.children[0] if node.children else None
            if ident and ident.type == "identifier":
                callee = text(self.src, ident)
                if callee in ("preload", "load"):
                    args = child_by_field(node, "arguments")
                    if args:
                        for c in args.children:
                            if c.type == "string":
                                raw = text(self.src, c).strip("\"'")
                                self.preload_paths.append(raw)
                elif current_func:
                    self.calls.append((current_func, callee))
        for c in node.children:
            self._walk(c, current_func)


def resolve_res_path(raw: str, project_root: Path) -> Path | None:
    if not raw.startswith("res://"):
        return None
    candidate = project_root / raw[len("res://") :]
    return candidate if candidate.exists() else None


def extract_gd(path: Path, root: Path, project_root: Path, class_name_to_stem: dict, corpus: set):
    f = GdFile(path, root)
    nodes = []
    edges = []

    label = f.class_name or path.stem
    nodes.append(
        {
            "id": f.stem,
            "label": label,
            "file_type": "code",
            "source_file": f.abs_path,
            "source_location": None,
            "source_url": None,
            "captured_at": None,
            "author": None,
            "contributor": None,
        }
    )

    if f.extends_name:
        target_stem = class_name_to_stem.get(f.extends_name)
        if target_stem:
            edges.append(
                {
                    "source": f.stem,
                    "target": target_stem,
                    "relation": "implements",
                    "confidence": "EXTRACTED",
                    "confidence_score": 1.0,
                    "source_file": f.abs_path,
                    "source_location": None,
                    "weight": 1.0,
                }
            )
        else:
            builtin_id = node_id("godot_engine_builtin", f.extends_name)
            nodes.append(
                {
                    "id": builtin_id,
                    "label": f.extends_name,
                    "file_type": "concept",
                    "source_file": f.abs_path,
                    "source_location": None,
                    "source_url": None,
                    "captured_at": None,
                    "author": None,
                    "contributor": None,
                }
            )
            edges.append(
                {
                    "source": f.stem,
                    "target": builtin_id,
                    "relation": "implements",
                    "confidence": "EXTRACTED",
                    "confidence_score": 1.0,
                    "source_file": f.abs_path,
                    "source_location": None,
                    "weight": 1.0,
                }
            )

    for sig in f.signals:
        sig_id = node_id(f.stem, sig + "_signal")
        nodes.append(
            {
                "id": sig_id,
                "label": f"signal {sig}",
                "file_type": "code",
                "source_file": f.abs_path,
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            }
        )
        edges.append(
            {
                "source": f.stem,
                "target": sig_id,
                "relation": "declares_signal",
                "confidence": "EXTRACTED",
                "confidence_score": 1.0,
                "source_file": f.abs_path,
                "source_location": None,
                "weight": 1.0,
            }
        )

    for fn in f.functions:
        fn_id = node_id(f.stem, fn)
        nodes.append(
            {
                "id": fn_id,
                "label": fn,
                "file_type": "code",
                "source_file": f.abs_path,
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            }
        )

    for raw in f.preload_paths:
        target_path = resolve_res_path(raw, project_root)
        if target_path and target_path in corpus:
            target_stem = stem_for(target_path, root)
            edges.append(
                {
                    "source": f.stem,
                    "target": target_stem,
                    "relation": "references",
                    "confidence": "EXTRACTED",
                    "confidence_score": 1.0,
                    "source_file": f.abs_path,
                    "source_location": None,
                    "weight": 1.0,
                }
            )

    for caller, callee in f.calls:
        if callee in f.functions and callee != caller:
            edges.append(
                {
                    "source": node_id(f.stem, caller),
                    "target": node_id(f.stem, callee),
                    "relation": "calls",
                    "confidence": "EXTRACTED",
                    "confidence_score": 1.0,
                    "source_file": f.abs_path,
                    "source_location": None,
                    "weight": 1.0,
                }
            )

    return nodes, edges, f.class_name


_EXT_RESOURCE_RE = re.compile(
    r'\[ext_resource[^\]]*type="(?P<type>[^"]+)"[^\]]*path="(?P<path>[^"]+)"[^\]]*id="(?P<id>[^"]+)"'
)
_EXT_RESOURCE_RE_ALT = re.compile(
    r'\[ext_resource[^\]]*path="(?P<path>[^"]+)"[^\]]*type="(?P<type>[^"]+)"[^\]]*id="(?P<id>[^"]+)"'
)


def extract_scene(path: Path, root: Path, project_root: Path, corpus: set):
    text_content = path.read_text(encoding="utf-8", errors="replace")
    stem = stem_for(path, root)
    file_type = "code" if path.suffix == ".tscn" else "document"
    nodes = [
        {
            "id": stem,
            "label": path.name,
            "file_type": file_type,
            "source_file": str(path),
            "source_location": None,
            "source_url": None,
            "captured_at": None,
            "author": None,
            "contributor": None,
        }
    ]
    edges = []
    for rx in (_EXT_RESOURCE_RE, _EXT_RESOURCE_RE_ALT):
        for m in rx.finditer(text_content):
            raw = m.group("path")
            target_path = resolve_res_path(raw, project_root)
            if target_path and target_path in corpus:
                target_stem = stem_for(target_path, root)
                edges.append(
                    {
                        "source": stem,
                        "target": target_stem,
                        "relation": "references",
                        "confidence": "EXTRACTED",
                        "confidence_score": 1.0,
                        "source_file": str(path),
                        "source_location": None,
                        "weight": 1.0,
                    }
                )
    return nodes, edges


def main():
    root = Path(sys.argv[1]).resolve()
    files = [Path(p).resolve() for p in sys.argv[2:]]
    project_root = root

    corpus = set(files)
    gd_files = [p for p in files if p.suffix == ".gd"]
    scene_files = [p for p in files if p.suffix in (".tscn", ".tres")]
    other_files = [p for p in files if p.suffix not in (".gd", ".tscn", ".tres")]

    # Pass 1: build class_name -> stem map so extends edges can resolve across files.
    class_name_to_stem: dict[str, str] = {}
    parsed: dict[Path, GdFile] = {}
    for p in gd_files:
        try:
            gf = GdFile(p, root)
        except Exception as e:
            print(f"WARN: failed to parse {p}: {e}", file=sys.stderr)
            continue
        parsed[p] = gf
        if gf.class_name:
            class_name_to_stem[gf.class_name] = gf.stem

    all_nodes = []
    all_edges = []
    for p, gf in parsed.items():
        nodes, edges, _ = extract_gd(p, root, project_root, class_name_to_stem, corpus)
        all_nodes.extend(nodes)
        all_edges.extend(edges)

    for p in scene_files:
        try:
            nodes, edges = extract_scene(p, root, project_root, corpus)
        except Exception as e:
            print(f"WARN: failed to parse {p}: {e}", file=sys.stderr)
            continue
        all_nodes.extend(nodes)
        all_edges.extend(edges)

    for p in other_files:
        # .gdshader/.gdextension etc: no dedicated parser here, register a bare
        # file node so scene ext_resource edges can still resolve to it.
        all_nodes.append(
            {
                "id": stem_for(p, root),
                "label": p.name,
                "file_type": "code",
                "source_file": str(p),
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            }
        )

    seen = set()
    deduped_nodes = []
    for n in all_nodes:
        if n["id"] not in seen:
            seen.add(n["id"])
            deduped_nodes.append(n)

    result = {
        "nodes": deduped_nodes,
        "edges": all_edges,
        "input_tokens": 0,
        "output_tokens": 0,
    }
    json.dump(result, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
