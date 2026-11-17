"""Rebuild the bounded Helsinki pack without downloading the 1.94 GB archive.

Requires requests and Blender 5.x. This is a development tool, not a runtime
dependency. Selected ZIP members are checked against their size and CRC.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import threading
import xml.etree.ElementTree as ET
import zipfile
import zlib

import requests

ROOT = Path(__file__).resolve().parents[2]
URL = ("https://3d.hel.ninja/data/mesh/"
       "Helsinki3D-MESH_2017_OBJ_2km-250m_ZIP/Helsinki3D_2017_OBJ_672496x2.zip")
ANCHOR = (7363.062073022, 4947.252662436, 6.4395913690821)
FOLDERS = ("672497b4/", "673497a3/")


class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        self.session = requests.Session()
        response = self.session.head(url, timeout=60)
        response.raise_for_status()
        self.size = int(response.headers["Content-Length"])
        self.pos = 0

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos if whence == 1 else self.size) + offset
        return self.pos

    def read(self, n=-1):
        n = self.size - self.pos if n < 0 else min(n, self.size - self.pos)
        if n <= 0:
            return b""
        if n > 64 * 1024 * 1024:
            raise ValueError("Unexpected large ZIP read")
        response = self.session.get(self.url, headers={"Range": f"bytes={self.pos}-{self.pos+n-1}"}, timeout=60)
        response.raise_for_status()
        if response.status_code != 206 or len(response.content) != n:
            raise ValueError("The server did not return the requested byte range")
        self.pos += n
        return response.content


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", required=True, type=Path)
    parser.add_argument("--cache", type=Path, default=ROOT / "data/world_sources/helsinki_senate_square/cache")
    parser.add_argument("--prepare-only", action="store_true", help="Download and rebase without invoking Blender")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    remote = RemoteZip(URL)
    try:
        with zipfile.ZipFile(remote) as archive:
            infos = [i for i in archive.infolist() if i.filename.startswith(FOLDERS) and "_L19_" in i.filename]
            metadata = archive.read("metadata.xml")
    finally:
        remote.session.close()
    if len(infos) != 393:
        raise ValueError("Source archive changed; review the LOD selection before rebuilding")
    declared = ET.fromstring(metadata)
    if declared.findtext("SRS") != "EPSG:3879+5773" or declared.findtext("SRSOrigin") != "25490000,6668000,0":
        raise ValueError("Source coordinate metadata changed; review the anchor before rebuilding")
    local = threading.local()

    def fetch(info):
        # Only fixed, flat OBJ/MTL/JPG names from the two selected directories.
        path = args.cache / "source" / info.filename
        if ".." in Path(info.filename).parts or Path(info.filename).is_absolute():
            raise ValueError("Unsafe archive path")
        path.parent.mkdir(parents=True, exist_ok=True)
        data = path.read_bytes() if path.exists() else b""
        if len(data) != info.file_size or zlib.crc32(data) != info.CRC:
            if not hasattr(local, "session"):
                local.session = requests.Session()
            end = info.header_offset + 30 + len(info.filename.encode()) + info.compress_size + 512
            response = local.session.get(URL, headers={"Range": f"bytes={info.header_offset}-{end}"}, timeout=60)
            response.raise_for_status()
            if response.status_code != 206:
                raise ValueError("Byte-range download unavailable")
            raw = response.content
            if raw[:4] != b"PK\x03\x04":
                raise ValueError("Invalid ZIP member header")
            name_size, extra_size = struct.unpack_from("<HH", raw, 26)
            offset = 30 + name_size + extra_size
            data = zlib.decompress(raw[offset:offset+info.compress_size], -15)
            if len(data) != info.file_size or zlib.crc32(data) != info.CRC:
                raise ValueError("Source member integrity check failed: " + info.filename)
            path.write_bytes(data)
        return {"name": info.filename, "bytes": len(data), "crc": info.CRC,
                "sha256": hashlib.sha256(data).hexdigest()}

    print(f"Fetching {len(infos)} members ({sum(i.compress_size for i in infos):,} compressed bytes)", flush=True)
    with ThreadPoolExecutor(max_workers=8) as pool:
        receipt = list(pool.map(fetch, infos))
    rebased = args.cache / "rebased"
    rebased.mkdir(exist_ok=True)
    for item in receipt:
        path = args.cache / "source" / item["name"]
        target = rebased / path.name
        if path.suffix == ".obj":
            lines = []
            for line in path.read_text(encoding="utf-8").splitlines():
                fields = line.split()
                if fields and fields[0] == "v":
                    line = "v " + " ".join(f"{float(fields[k+1])-ANCHOR[k]:.7f}" for k in range(3))
                lines.append(line)
            target.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        else:
            shutil.copy2(path, target)
    source = ROOT / "data/world_sources/helsinki_senate_square"
    source.mkdir(parents=True, exist_ok=True)
    (source / "metadata.xml").write_bytes(metadata)
    (source / "download_integrity.json").write_text(json.dumps({"url": URL, "zip_bytes": remote.size,
        "lod": 19, "selected_members": receipt}, indent=2) + "\n", encoding="utf-8", newline="\n")
    if not args.prepare_only:
        subprocess.run([str(args.blender), "--background", "--python", str(Path(__file__).with_name("export_helsinki.py")),
                        "--", str(rebased), str(ROOT)], check=True)


if __name__ == "__main__":
    main()
