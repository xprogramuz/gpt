"""Layout detection for Cursor backup folders.

Mirrors restore-cursor.ps1 so we can test restore mapping without Windows.
"""

from __future__ import annotations

from pathlib import Path
from typing import Dict, Iterable, List, Optional


ROAMING_SKIP_NAMES = {
    "Cache",
    "CachedData",
    "CachedExtensions",
    "Code Cache",
    "Crashpad",
    "DawnCache",
    "DawnGraphiteCache",
    "DawnWebGPUCache",
    "GPUCache",
    "logs",
    "Service Worker",
    "ShaderCache",
    "VideoDecodeStats",
}


def looks_like_roaming_cursor(path: Path) -> bool:
    user = path / "User"
    return (
        (user / "settings.json").is_file()
        or (user / "globalStorage").exists()
        or (user / "keybindings.json").is_file()
        or (path / "storage.json").is_file()
    )


def looks_like_dot_cursor(path: Path) -> bool:
    markers = (
        path / "argv.json",
        path / "mcp.json",
        path / "ide_state.json",
        path / "extensions",
        path / "projects",
        path / "skills-cursor",
        path / "ai-tracking",
    )
    return any(marker.exists() for marker in markers)


def find_dirs_named(root: Path, name: str, depth: int = 6) -> List[Path]:
    matches: List[Path] = []
    if not root.is_dir():
        return matches
    queue: List[tuple[Path, int]] = [(root, 0)]
    while queue:
        current, current_depth = queue.pop(0)
        if current_depth > depth:
            continue
        try:
            children = [p for p in current.iterdir() if p.is_dir()]
        except OSError:
            continue
        for child in children:
            if child.name.lower() == name.lower():
                matches.append(child)
            if current_depth < depth:
                queue.append((child, current_depth + 1))
    return matches


def resolve_backup_layout(root: Path) -> Dict[str, Optional[str]]:
    layout: Dict[str, Optional[str]] = {
        "backup_root": str(root),
        "roaming_cursor": None,
        "dot_cursor": None,
        "loose_user": None,
        "loose_settings": None,
        "loose_keybinds": None,
        "loose_snippets": None,
        "loose_extensions_txt": None,
    }

    roaming_candidates = [
        root / "Cursor",
        root / "AppData" / "Roaming" / "Cursor",
        root / "Roaming" / "Cursor",
        root / "AppData" / "Cursor",
        root / "Users" / "Xp" / "AppData" / "Roaming" / "Cursor",
        root / "Xp" / "AppData" / "Roaming" / "Cursor",
        root,
    ]
    for candidate in roaming_candidates:
        if looks_like_roaming_cursor(candidate):
            layout["roaming_cursor"] = str(candidate)
            break

    if layout["roaming_cursor"] is None:
        for user_dir in find_dirs_named(root, "User"):
            parent = user_dir.parent
            if looks_like_roaming_cursor(parent):
                layout["roaming_cursor"] = str(parent)
                break
            if (user_dir / "settings.json").is_file() or (user_dir / "globalStorage").exists():
                layout["loose_user"] = str(user_dir)

    dot_candidates = [
        root / ".cursor",
        root / "dot-cursor",
        root / "dotcursor",
        root / "cursor-home",
        root / "Users" / "Xp" / ".cursor",
        root / "Xp" / ".cursor",
    ]
    for candidate in dot_candidates:
        if looks_like_dot_cursor(candidate):
            layout["dot_cursor"] = str(candidate)
            break

    if layout["dot_cursor"] is None:
        for directory in find_dirs_named(root, ".cursor"):
            if looks_like_dot_cursor(directory):
                layout["dot_cursor"] = str(directory)
                break

    if (root / "settings.json").is_file():
        layout["loose_settings"] = str(root / "settings.json")
    if (root / "keybindings.json").is_file():
        layout["loose_keybinds"] = str(root / "keybindings.json")
    if (root / "snippets").exists():
        layout["loose_snippets"] = str(root / "snippets")
    if (root / "extensions.txt").is_file():
        layout["loose_extensions_txt"] = str(root / "extensions.txt")
    elif (root / "extensions.json").is_file():
        layout["loose_extensions_txt"] = str(root / "extensions.json")

    return layout


def has_restorable_data(layout: Dict[str, Optional[str]]) -> bool:
    keys: Iterable[str] = (
        "roaming_cursor",
        "dot_cursor",
        "loose_user",
        "loose_settings",
        "loose_keybinds",
        "loose_snippets",
        "loose_extensions_txt",
    )
    return any(layout.get(key) for key in keys)


def _layout_score(layout: Dict[str, Optional[str]], folder_name: str = "") -> int:
    score = 0
    if layout.get("roaming_cursor"):
        score += 100
    if layout.get("dot_cursor"):
        score += 80
    if layout.get("loose_user"):
        score += 40
    if layout.get("loose_settings"):
        score += 10
    if "cursor" in folder_name.lower():
        score += 15
    return score


def find_best_backup_root(search_roots: Iterable[Path]) -> Optional[Dict[str, object]]:
    ranked: List[Dict[str, object]] = []
    seen: set[str] = set()

    for root in search_roots:
        root = Path(root)
        candidates = [root]
        if root.is_dir():
            candidates.extend(sorted(p for p in root.iterdir() if p.is_dir()))
        for candidate in candidates:
            key = str(candidate)
            if key in seen:
                continue
            seen.add(key)
            layout = resolve_backup_layout(candidate)
            if not has_restorable_data(layout):
                continue
            ranked.append(
                {
                    "path": candidate,
                    "score": _layout_score(layout, candidate.name),
                    "layout": layout,
                }
            )

    if not ranked:
        return None
    paths = [Path(item["path"]) for item in ranked]
    ranked = [
        item
        for item in ranked
        if not any(
            Path(item["path"]) != other and other.is_relative_to(Path(item["path"]))
            for other in paths
        )
    ]
    ranked.sort(key=lambda item: int(item["score"]), reverse=True)
    return ranked[0]
