#!/usr/bin/env python3
import argparse
import json
import re
import time
import sys
from pathlib import Path
from urllib.parse import urlencode, urlparse
from urllib.error import URLError
from urllib.request import Request, urlopen


API_URL = "https://store.oppo.com/cn/oapi/cms-business/goods/switch"
IMAGE_PATTERN = re.compile(r"https?://[^\s\"'<>]+?\.(?:png|jpe?g|webp|gif)(?:\?[^\s\"'<>]*)?", re.I)


def fetch_payload(sku_id: str) -> dict:
    query = urlencode(
        {
            "interfaceVersion": "v2",
            "pageCode": "skuDetail",
            "skuId": sku_id,
        }
    )
    request = Request(
        f"{API_URL}?{query}",
        headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json,text/plain,*/*",
        },
    )
    with urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def collect_images(value) -> list[str]:
    result = []

    def walk(node):
        if isinstance(node, dict):
            for item in node.values():
                walk(item)
            return
        if isinstance(node, list):
            for item in node:
                walk(item)
            return
        if isinstance(node, str):
            result.extend(match.group(0) for match in IMAGE_PATTERN.finditer(node))

    walk(value)
    return list(dict.fromkeys(result))


def file_name_for(index: int, url: str) -> str:
    path = urlparse(url).path
    suffix = Path(path).suffix or ".jpg"
    stem = Path(path).stem or "image"
    return f"{index:03d}_{stem[:80]}{suffix}"


def request_bytes(url: str, timeout: int = 30, retries: int = 3) -> bytes:
    last_error = None
    for attempt in range(1, retries + 1):
        try:
            request = Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0",
                    "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
                    "Connection": "close",
                },
            )
            with urlopen(request, timeout=timeout) as response:
                return response.read()
        except URLError as error:
            last_error = error
            time.sleep(min(attempt, 3))
    raise last_error


def download_images(sku_id: str, urls: list[str], output_dir: Path) -> list[str]:
    sku_dir = output_dir / sku_id
    sku_dir.mkdir(parents=True, exist_ok=True)
    failed = []
    for index, url in enumerate(urls, 1):
        target = sku_dir / file_name_for(index, url)
        try:
            target.write_bytes(request_bytes(url))
        except Exception as error:
            failed.append(url)
            print(f"[warn] {sku_id}: 下载失败 {url} ({error})", file=sys.stderr)
    return failed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sku_ids", nargs="+")
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--output-dir", default="oppo_images")
    args = parser.parse_args()

    output = {}
    failed_downloads = {}
    for sku_id in args.sku_ids:
        payload = fetch_payload(sku_id)
        if payload.get("code") != 200:
            raise RuntimeError(f"{sku_id}: {payload.get('message') or payload}")

        images = collect_images(payload)
        output[sku_id] = images

        if args.download:
            failed = download_images(sku_id, images, Path(args.output_dir))
            if failed:
                failed_downloads[sku_id] = failed

    print(json.dumps(output, ensure_ascii=False, indent=2))
    if failed_downloads:
        failed_file = Path(args.output_dir) / "failed_downloads.json"
        failed_file.parent.mkdir(parents=True, exist_ok=True)
        failed_file.write_text(json.dumps(failed_downloads, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[warn] 部分图片下载失败，已写入 {failed_file}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
