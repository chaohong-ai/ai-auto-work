#!/usr/bin/env python3
"""
网页内容爬取工具 - 供 Claude Code 调研时使用
用法:
    python3 Tools/utils/web_fetch.py <url> [--prompt <提取提示>] [--output <输出文件>] [--raw]

示例:
    # 基础抓取，输出 markdown 到终端
    python3 Tools/utils/web_fetch.py https://example.com

    # 带提取提示，只输出相关内容
    python3 Tools/utils/web_fetch.py https://example.com --prompt "提取关于AI工具的部分"

    # 保存到文件
    python3 Tools/utils/web_fetch.py https://example.com --output result.md

    # 批量抓取（多个URL用空格分隔）
    python3 Tools/utils/web_fetch.py url1 url2 url3

    # 输出原始HTML（调试用）
    python3 Tools/utils/web_fetch.py https://example.com --raw
"""

import sys
import argparse
import re
import requests
from bs4 import BeautifulSoup
import html2text


# 模拟正常浏览器的请求头
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7",
    "Accept-Encoding": "gzip, deflate, br",
    "DNT": "1",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
}

TIMEOUT = 30  # 秒


def fetch_url(url: str, raw: bool = False) -> str:
    """抓取URL内容并转为markdown"""
    try:
        session = requests.Session()
        resp = session.get(url, headers=HEADERS, timeout=TIMEOUT, allow_redirects=True)
        resp.raise_for_status()
        # requests 会自动解压 gzip/deflate/br（如果 brotli 库已安装）
        resp.encoding = resp.apparent_encoding or "utf-8"
        html_content = resp.text
        # 检测是否为乱码（二进制内容被误读为文本）
        if html_content and len(html_content) > 100:
            non_ascii_ratio = sum(1 for c in html_content[:500] if ord(c) > 127) / min(500, len(html_content))
            if non_ascii_ratio > 0.3:
                # 可能是压缩内容未正确解码，尝试用 content 原始字节
                try:
                    html_content = resp.content.decode("utf-8", errors="replace")
                except Exception:
                    pass
    except requests.RequestException as e:
        return f"[错误] 无法访问 {url}: {e}"

    if raw:
        return html_content

    # 用 BeautifulSoup 清理HTML
    soup = BeautifulSoup(html_content, "html.parser")

    # 移除无关标签
    for tag in soup.find_all(["script", "style", "nav", "footer", "header", "aside", "iframe", "noscript"]):
        tag.decompose()

    # 尝试提取主要内容区域
    main_content = (
        soup.find("article")
        or soup.find("main")
        or soup.find(class_=re.compile(r"(post|article|content|entry|blog)", re.I))
        or soup.find(id=re.compile(r"(post|article|content|entry|blog)", re.I))
        or soup.body
        or soup
    )

    # 转为 markdown
    converter = html2text.HTML2Text()
    converter.ignore_links = False
    converter.ignore_images = True
    converter.ignore_emphasis = False
    converter.body_width = 0  # 不折行
    converter.unicode_snob = True

    markdown = converter.handle(str(main_content))

    # 清理多余空行
    markdown = re.sub(r"\n{3,}", "\n\n", markdown)

    # 截断过长内容（保留前15000字符）
    max_chars = 15000
    if len(markdown) > max_chars:
        markdown = markdown[:max_chars] + f"\n\n... [内容已截断，共 {len(markdown)} 字符，显示前 {max_chars} 字符]"

    return markdown


def main():
    parser = argparse.ArgumentParser(description="网页内容爬取工具")
    parser.add_argument("urls", nargs="+", help="要爬取的URL列表")
    parser.add_argument("--prompt", "-p", default="", help="内容提取提示（当前版本仅作标注，不做AI过滤）")
    parser.add_argument("--output", "-o", default="", help="输出文件路径（不指定则输出到终端）")
    parser.add_argument("--raw", action="store_true", help="输出原始HTML")

    args = parser.parse_args()

    results = []
    for url in args.urls:
        print(f"正在抓取: {url}", file=sys.stderr)
        content = fetch_url(url, raw=args.raw)
        results.append(f"# Source: {url}\n\n{content}")

    output = "\n\n---\n\n".join(results)

    if args.prompt:
        output = f"> 提取提示: {args.prompt}\n\n{output}"

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output)
        print(f"已保存到: {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
