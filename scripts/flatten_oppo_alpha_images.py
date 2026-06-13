#!/usr/bin/env python3
import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


CATEGORY_API_URL = "https://www.opposhop.cn/cn/oapi/goods-business/category/goods"
SUPPORTED_SUFFIXES = {".png", ".webp", ".gif", ".jpg", ".jpeg"}


def fetch_goods_names(category_code: str, page_size: int) -> dict[str, str]:
    query = urlencode(
        {
            "scene": "mall",
            "categoryCode": category_code,
            "pageIndex": 1,
            "pageSize": page_size,
        }
    )
    request = Request(
        f"{CATEGORY_API_URL}?{query}",
        headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json,text/plain,*/*",
        },
    )
    with urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))

    if payload.get("code") != 200:
        raise RuntimeError(payload.get("message") or payload)

    names = {}
    for item in payload.get("data", []):
        sku_id = str(item.get("skuId") or "")
        sku_name = item.get("skuName") or item.get("spuName") or sku_id
        if sku_id:
            names[sku_id] = sku_name
    return names


def safe_name(value: str) -> str:
    value = re.sub(r"[\\/:*?\"<>|]", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value or "未命名商品"


def image_suffix(path: Path) -> str:
    data = path.read_bytes()[:16]
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return ".gif"
    if data.startswith(b"\xff\xd8"):
        return ".jpg"
    return path.suffix.lower()


def flatten_images(input_dir: Path, output_dir: Path, names: dict[str, str]) -> tuple[int, list[str]]:
    copied = 0
    missing_names = []

    for sku_dir in sorted(path for path in input_dir.iterdir() if path.is_dir()):
        sku_id = sku_dir.name
        product_name = names.get(sku_id)
        if not product_name:
            product_name = sku_id
            missing_names.append(sku_id)

        files = sorted(
            path
            for path in sku_dir.iterdir()
            if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES
        )
        for index, source in enumerate(files, 1):
            target_name = f"{safe_name(product_name)}_{index:03d}{image_suffix(source)}"
            target = output_dir / target_name
            output_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            copied += 1

    return copied, missing_names


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", nargs="?", default="oppo_alpha_images")
    parser.add_argument("output_dir", nargs="?", default="oppo_alpha_images_named")
    parser.add_argument("--category-code", default="003925")
    parser.add_argument("--page-size", type=int, default=50)
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    if not input_dir.is_dir():
        raise SystemExit(f"输入目录不存在: {input_dir}")

    names = fetch_goods_names(args.category_code, args.page_size)
    copied, missing_names = flatten_images(input_dir, output_dir, names)

    print(f"已复制并重命名: {copied}")
    print(f"输出目录: {output_dir}")
    if missing_names:
        print(f"[warn] 以下 SKU 未在分类接口中找到名称: {', '.join(missing_names)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
