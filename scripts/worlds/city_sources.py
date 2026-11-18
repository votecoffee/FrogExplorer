"""Bounded, resumable access to the reviewed municipal photomesh sources."""
import hashlib
import json
import math
from pathlib import Path
import time
import threading
from urllib.parse import urljoin, urlsplit

import numpy as np
import requests


class Cache:
    def __init__(self, folder, allowed_prefix, maximum_bytes=8_000_000_000):
        self.folder = Path(folder)
        self.folder.mkdir(parents=True, exist_ok=True)
        self.prefix = allowed_prefix
        self.maximum = maximum_bytes
        self.downloaded = 0
        self.receipts = {}
        self.session = requests.Session()
        self.lock = threading.Lock()

    def get(self, url, limit=64_000_000):
        if not url.startswith(self.prefix) or urlsplit(url).scheme != 'https':
            raise ValueError('Source URL leaves the reviewed HTTPS data directory: ' + url)
        name = hashlib.sha256(url.encode()).hexdigest()
        path = self.folder / (name + Path(urlsplit(url).path).suffix)
        if not path.exists():
            temporary = path.with_suffix(path.suffix + '.part')
            for attempt in range(4):
                try:
                    start = temporary.stat().st_size if temporary.exists() else 0
                    with self.session.get(url, stream=True, timeout=(20, 60),
                                          headers={'Range': f'bytes={start}-'} if start else {}) as response:
                        response.raise_for_status()
                        if not response.url.startswith(self.prefix):
                            raise ValueError('Source redirected outside its reviewed directory')
                        if start and response.status_code != 206:
                            temporary.unlink()
                            continue
                        expected = int(response.headers.get('Content-Length', 0)) + start
                        if expected > limit:
                            raise ValueError('Source payload exceeds the per-file limit')
                        with temporary.open('ab' if start else 'wb') as file:
                            for chunk in response.iter_content(1024*1024):
                                with self.lock:
                                    self.downloaded += len(chunk)
                                    if file.tell() + len(chunk) > limit or self.downloaded > self.maximum:
                                        raise ValueError('City source download budget exceeded')
                                file.write(chunk)
                        if expected and temporary.stat().st_size != expected:
                            raise IOError('Truncated source payload')
                    temporary.replace(path)
                    break
                except (requests.RequestException, IOError):
                    if attempt == 3:
                        raise
                    time.sleep(1 + attempt)
            if not path.exists():
                raise IOError('Could not complete source download')
        if path.stat().st_size > limit:
            raise ValueError('Cached payload exceeds its limit')
        # Receipts bind this preparation to the exact first downloaded bytes.
        receipt_path = path.with_suffix(path.suffix + '.receipt.json')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        receipt = {'url': url, 'bytes': path.stat().st_size, 'sha256': digest}
        if receipt_path.exists() and json.loads(receipt_path.read_bytes()) != receipt:
            raise ValueError('Cached source identity changed: ' + str(path))
        receipt_path.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8', newline='\n')
        self.receipts[url] = receipt
        return path

    def json(self, url):
        return json.loads(self.get(url).read_bytes())


class Tileset:
    def __init__(self, cache, root_url, longitude, latitude, half_size):
        self.cache = cache
        self.root_url = root_url
        lon, lat = np.radians([longitude, latitude])
        # Conservative geographic envelope; exact clipping happens in local metres.
        dy = (half_size + 25) / 6_350_000
        dx = dy / math.cos(lat)
        self.region = [lon-dx, lat-dy, lon+dx, lat+dy]
        self.documents = {}

    def intersects(self, tile):
        region = tile.get('boundingVolume', {}).get('region')
        if not region or len(region) != 6:
            raise ValueError('Reviewed feeds require geographic region bounding volumes')
        a = self.region
        return region[2] >= a[0] and region[0] <= a[2] and region[3] >= a[1] and region[1] <= a[3]

    def document(self, url):
        if url not in self.documents:
            if len(self.documents) >= 5000:
                raise ValueError('Too many source tileset documents')
            self.documents[url] = self.cache.json(url)
        return self.documents[url]

    def frontier(self, error):
        selected = []
        def walk(tile, base, parent, depth):
            if depth > 48:
                raise ValueError('Source hierarchy is too deep or cyclic')
            if not self.intersects(tile):
                return
            if tile.get('refine', 'REPLACE') != 'REPLACE':
                raise ValueError('Only replacement photomesh refinement is supported')
            matrix = parent @ np.asarray(tile.get('transform', np.eye(4).T.ravel()), float).reshape(4, 4).T
            content = tile.get('content', {})
            uri = content.get('uri', content.get('url', ''))
            children = tile.get('children', [])
            if uri.endswith('.json'):
                url = urljoin(base, uri)
                doc = self.document(url)
                walk(doc['root'], url, matrix, depth+1)
            elif uri and (float(tile.get('geometricError', 0)) <= error or not children):
                if not uri.endswith('.b3dm'):
                    raise ValueError('Expected a static b3dm photomesh tile')
                selected.append({'url': urljoin(base, uri), 'transform': matrix.tolist(),
                                 'geometric_error': float(tile.get('geometricError', 0)),
                                 'region': tile['boundingVolume']['region']})
            else:
                for child in children:
                    walk(child, base, matrix, depth+1)
        walk(self.document(self.root_url)['root'], self.root_url, np.eye(4), 0)
        if not selected:
            raise ValueError('No source geometry intersects this city area')
        if len(selected) > 10000:
            raise ValueError('Too many photomesh payloads for this preparation')
        return selected
