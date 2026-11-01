"""从已提交、干净的源码构建玩家包；--check 仅审核允许清单。"""
from pathlib import Path
import argparse, hashlib, json, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.1.2"
MODULES = "augments backend controller decorations hunter native planner reader transaction view writer appearance appearance_color appearance_objects appearance_reader appearance_service appearance_adapter appearance_binding appearance_visibility appearance_hooks character_identity appearance_runtime cleanup_controller petalace_cleanup petalace_cleanup_plan petalace_cleanup_scan petalace_layout".split()
FILES = ["reframework/autorun/LoadoutClone.lua"] + [f"reframework/autorun/LoadoutClone/{m}.lua" for m in MODULES] + [
    "reframework/fonts/NotoSansSC-Regular.otf", "README.md",
    "licenses/NotoSansSC-OFL.txt", "licenses/THIRD-PARTY-NOTICES.txt"]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    payload = {name: (ROOT / name).read_bytes() for name in FILES}
    assert len(payload) == 32
    assert b"[LoadoutClone 1.1.2]" in payload[FILES[0]]
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}
    if args.check:
        print(json.dumps({"version": VERSION, "files": len(payload), "bytes": sum(map(len, payload.values())), "sha256": hashes}, ensure_ascii=False, indent=2))
        return
    def git(*cmd):
        return subprocess.check_output(["git", "-C", str(ROOT), *cmd], text=True).strip()
    assert not git("status", "--porcelain"), "发布包必须来自干净的已提交源码"
    commit = git("rev-parse", "HEAD")
    for name in FILES:
        assert git("ls-files", "--error-unmatch", name), name
    manifest = {"name": "Hunter Blueprint", "version": VERSION, "commit": commit, "sha256": hashes}
    payload["manifest.json"] = json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8")
    out = ROOT / "dist" / f"HunterBlueprint-{VERSION}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(payload.items()):
            item = zipfile.ZipInfo(name, (2026, 10, 24, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, data)
    with zipfile.ZipFile(out) as archive:
        assert set(archive.namelist()) == set(payload)
        assert archive.testzip() is None
        for name, data in payload.items():
            assert archive.read(name) == data, name
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    out.with_suffix(".sha256").write_text(f"{digest}  {out.name}\n", encoding="utf-8")
    print(json.dumps({"path": str(out), "commit": commit, "files": len(payload), "bytes": out.stat().st_size, "sha256": digest}, indent=2))

if __name__ == "__main__":
    main()
