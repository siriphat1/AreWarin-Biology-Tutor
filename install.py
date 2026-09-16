#!/usr/bin/env python3
from pathlib import Path
import shutil, sys

HERE = Path(__file__).resolve().parent

def patch_before_body(path: Path, tag: str, marker: str):
    text = path.read_text(encoding="utf-8")
    if marker in text:
        print(f"[skip] {path}: already patched")
        return

    backup = path.with_suffix(path.suffix + ".bak-course-category")
    if not backup.exists():
        shutil.copy2(path, backup)
        print(f"[backup] {backup}")

    if "</body>" not in text:
        raise RuntimeError(f"</body> not found in {path}")

    text = text.replace("</body>", f"  {tag}\n</body>", 1)
    path.write_text(text, encoding="utf-8")
    print(f"[patch] {path}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python install.py /path/to/arewarin-complete-system")
        raise SystemExit(2)

    root = Path(sys.argv[1]).resolve()
    manager = root / "manager"
    jsdir = root / "js"
    supabase = root / "supabase"

    required = [root / "index.html", manager / "index.html"]
    for f in required:
        if not f.exists():
            raise SystemExit(f"Missing required file: {f}")

    manager.mkdir(parents=True, exist_ok=True)
    jsdir.mkdir(parents=True, exist_ok=True)
    supabase.mkdir(parents=True, exist_ok=True)

    shutil.copy2(HERE / "manager" / "course-category-addon.js",
                 manager / "course-category-addon.js")
    shutil.copy2(HERE / "js" / "course-category-public-addon.js",
                 jsdir / "course-category-public-addon.js")
    shutil.copy2(HERE / "supabase" / "COURSE_CATEGORY_UPGRADE.sql",
                 supabase / "COURSE_CATEGORY_UPGRADE.sql")

    patch_before_body(
        manager / "index.html",
        '<script src="./course-category-addon.js?v=1.0"></script>',
        'course-category-addon.js'
    )
    patch_before_body(
        root / "index.html",
        '<script src="./js/course-category-public-addon.js?v=1.0"></script>',
        'course-category-public-addon.js'
    )

    print()
    print("Installed frontend files successfully.")
    print("NEXT: Run supabase/COURSE_CATEGORY_UPGRADE.sql in Supabase SQL Editor.")
    print("Then hard refresh the website (Ctrl+F5).")

if __name__ == "__main__":
    main()
