#!/usr/bin/env python3
"""
ch32fun_zig 技術ドキュメント — PDF 生成スクリプト

使い方:
    /tmp/ch32pdfgen/bin/python docs/generate-book.py

出力:
    docs/ch32fun-zig-tutorial.pdf
"""

import os
import re
import subprocess
import tempfile

import markdown
import weasyprint
from pygments import highlight as pygments_highlight
from pygments.lexers import get_lexer_by_name
from pygments.formatters import HtmlFormatter

BASE = os.path.dirname(os.path.abspath(__file__))

# ── 本の構造定義 ──────────────────────────────────────────

PARTS = [
    {
        "title": "第I部 ターゲットとツールチェイン",
        "subtitle": "RV32EC を Zig のクロスコンパイル基盤で扱う",
        "chapters": [
            ("01-overview", "本書の対象とゴール", "ch32fun_zig が解決していること"),
            ("02-rv32ec-target", "RV32EC というターゲットを正しく指定する", "Target.Query で RV32EC を組む"),
            ("03-zig-cross-toolchain", "Zig 0.16 のクロスコンパイル基盤", "LLVM + lld + compiler_rt の役割"),
        ],
    },
    {
        "title": "第II部 リンクと起動",
        "subtitle": "FLASH/RAM 配置と起動シーケンスを解剖する",
        "chapters": [
            ("04-memory-map-linker", "メモリマップとリンカスクリプト", "VMA/LMA と .data トリック"),
            ("05-startup-runtime", "起動コードとランタイム初期化", "_start から main() までの段取り"),
            ("06-vector-table-irq", "ベクタテーブルと割り込みエントリ", "PFIC と SysTick ハンドラ"),
        ],
    },
    {
        "title": "第III部 ビルドパイプラインと書き込み",
        "subtitle": "ソースから実機 FLASH までの一直線の経路",
        "chapters": [
            ("07-build-zig-walkthrough", "build.zig をひと通り歩く", "Examples 切替とステップ DAG"),
            ("08-objcopy-artifacts", "ELF から .bin / .hex への変換", "objcopy が抜き出すもの"),
            ("09-flash-minichlink", "minichlink で実機に書き込む", "SWIO と tools/flash.sh"),
        ],
    },
    {
        "title": "第IV部 HAL の構造",
        "subtitle": "レジスタ層からアプリ寄り HAL までを段で積む",
        "chapters": [
            ("10-registers-mmio", "MMIO とレジスタ抽象化", "extern struct と *volatile T"),
            ("11-hal-gpio-time", "HAL — GPIO と SysTick", "Pin 型と delayMs の作り"),
            ("12-i2c-ssd1306", "HAL — I2C と SSD1306", "ブロッキング送信と 1024B フレームバッファ"),
        ],
    },
    {
        "title": "第V部 言語仕様と標準ライブラリ",
        "subtitle": "freestanding + RV32EC で使える Zig の範囲を見極める",
        "chapters": [
            ("13-zig-on-ch32", "本プロジェクトで使える Zig 言語機能と std", "使える / 使えない / 太る の見分け方"),
        ],
    },
    {
        "title": "第VI部 永続化",
        "subtitle": "内蔵 FLASH への書き込みで設定/スコアを残す",
        "chapters": [
            ("14-persistence-flash", "データの永続化 — 内蔵 FLASH に書く HAL", "Slot(T) で 1 構造体 = 1 ページ"),
        ],
    },
    {
        "title": "第VII部 便利な周辺機能",
        "subtitle": "ファームウェアでよく使う 5 機能を HAL に揃える",
        "chapters": [
            ("15-uart-pwm-adc-exti", "周辺機能の HAL — UART / log / PWM / Tone / ADC / EXTI", "ログ・LED調光・音・アナログ・割り込み入力"),
        ],
    },
    {
        "title": "第VIII部 Zig 言語機能を活かす",
        "subtitle": "comptime / tagged union / packed struct で書くファーム",
        "chapters": [
            ("16-zig-idioms", "Zig 言語機能を活かしたファームウェアパターン", "4 つのサンプルで Zig らしさを実装で示す"),
        ],
    },
]

APPENDICES = [
    ("glossary.md", "用語集"),
    ("rv32-asm-cheatsheet.md", "RV32 アセンブリ チートシート"),
    ("register-map.md", "CH32V003 レジスタ早見表"),
    ("troubleshooting.md", "トラブルシューティング"),
]

# ── CSS スタイル ──────────────────────────────────────────

CSS = r"""
@page {
    size: A4;
    margin: 25mm 20mm 25mm 20mm;
    @bottom-center {
        content: counter(page);
        font-size: 9pt;
        color: #666;
    }
}

@page :first {
    @bottom-center { content: none; }
}

body {
    font-family: "Hiragino Kaku Gothic ProN", "Hiragino Sans", "Noto Sans JP",
                 "Yu Gothic", "Meiryo", sans-serif;
    font-size: 10pt;
    line-height: 1.7;
    color: #1a1a1a;
}

/* 表紙 */
.cover {
    page-break-after: always;
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    min-height: 85vh;
    text-align: center;
}
.cover h1 {
    font-size: 26pt;
    margin-bottom: 8pt;
    color: #c0392b;
    letter-spacing: 1pt;
}
.cover .subtitle {
    font-size: 14pt;
    color: #555;
    margin-bottom: 30pt;
}
.cover .meta {
    font-size: 10pt;
    color: #888;
    margin-top: 20pt;
}
.cover .logo {
    font-size: 48pt;
    margin-bottom: 16pt;
}

/* 目次 */
.toc {
    page-break-after: always;
}
.toc h2 {
    font-size: 18pt;
    border-bottom: 2px solid #c0392b;
    padding-bottom: 6pt;
    margin-bottom: 16pt;
}
.toc ul {
    list-style: none;
    padding: 0;
}
.toc > ul > li {
    margin-top: 14pt;
    font-weight: bold;
    font-size: 11pt;
    color: #333;
}
.toc > ul > li > ul {
    margin-top: 4pt;
}
.toc > ul > li > ul > li {
    font-weight: normal;
    font-size: 10pt;
    color: #555;
    margin: 2pt 0;
    padding-left: 16pt;
}
.toc a {
    color: inherit;
    text-decoration: none;
}

/* 部の扉ページ */
.part-title {
    page-break-before: always;
    page-break-after: always;
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    min-height: 60vh;
    text-align: center;
}
.part-title h2 {
    font-size: 24pt;
    color: #c0392b;
    margin-bottom: 8pt;
    border: none;
}
.part-title .part-subtitle {
    font-size: 12pt;
    color: #666;
}

/* 章 */
.chapter {
    page-break-before: always;
}
.chapter h2 {
    font-size: 18pt;
    color: #c0392b;
    border-bottom: 2px solid #c0392b;
    padding-bottom: 6pt;
    margin-top: 0;
}
.chapter h3 {
    font-size: 13pt;
    color: #333;
    margin-top: 18pt;
    border-left: 4px solid #c0392b;
    padding-left: 10pt;
}
.chapter h4 {
    font-size: 11pt;
    color: #444;
    margin-top: 14pt;
}

/* コードブロック */
pre {
    background: #f8f8f5;
    border: 1px solid #ddd;
    border-left: 4px solid #c0392b;
    padding: 10pt 12pt;
    font-size: 8.5pt;
    line-height: 1.5;
    overflow-wrap: break-word;
    white-space: pre-wrap;
    font-family: "SF Mono", "Menlo", "Monaco", "Consolas", monospace;
}
code {
    background: #fbeae5;
    padding: 1pt 4pt;
    border-radius: 2pt;
    font-size: 9pt;
    font-family: "SF Mono", "Menlo", "Monaco", "Consolas", monospace;
}
pre code {
    background: none;
    padding: 0;
    border-radius: 0;
    font-size: inherit;
}

/* Pygments syntax highlighting */
.highlight { background: #f8f8f5; }
.highlight pre {
    background: #f8f8f5;
    border: 1px solid #ddd;
    border-left: 4px solid #c0392b;
    padding: 10pt 12pt;
    font-size: 8.5pt;
    line-height: 1.5;
    overflow-wrap: break-word;
    white-space: pre-wrap;
    font-family: "SF Mono", "Menlo", "Monaco", "Consolas", monospace;
}
.highlight .c { color: #6a9955; font-style: italic }
.highlight .ch { color: #6a9955; font-style: italic }
.highlight .cm { color: #6a9955; font-style: italic }
.highlight .c1 { color: #6a9955; font-style: italic }
.highlight .cs { color: #6a9955; font-style: italic }
.highlight .cp { color: #6a9955 }
.highlight .cpf { color: #6a9955; font-style: italic }
.highlight .k { color: #cf8e6d; font-weight: bold }
.highlight .kc { color: #cf8e6d; font-weight: bold }
.highlight .kd { color: #cf8e6d; font-weight: bold }
.highlight .kn { color: #cf8e6d; font-weight: bold }
.highlight .kp { color: #cf8e6d }
.highlight .kr { color: #cf8e6d; font-weight: bold }
.highlight .kt { color: #2b91af }
.highlight .m { color: #2aacb8 }
.highlight .mi { color: #2aacb8 }
.highlight .mh { color: #2aacb8 }
.highlight .mb { color: #2aacb8 }
.highlight .mo { color: #2aacb8 }
.highlight .mf { color: #2aacb8 }
.highlight .s { color: #6aab73 }
.highlight .s1 { color: #6aab73 }
.highlight .s2 { color: #6aab73 }
.highlight .sa { color: #6aab73 }
.highlight .sb { color: #6aab73 }
.highlight .sc { color: #6aab73 }
.highlight .se { color: #d7ba7d; font-weight: bold }
.highlight .nb { color: #56b6c2 }
.highlight .nf { color: #61afef }
.highlight .fm { color: #61afef }
.highlight .n { color: #1a1a1a }
.highlight .o { color: #888 }
.highlight .p { color: #888 }
.highlight .w { color: #bbb }
.highlight .err { color: #e06c75; border: none }

/* テーブル */
table {
    border-collapse: collapse;
    width: 100%;
    margin: 10pt 0;
    font-size: 9pt;
}
th, td {
    border: 1px solid #ccc;
    padding: 6pt 8pt;
    text-align: left;
    word-break: break-word;
}
th {
    background: #c0392b;
    color: white;
    font-weight: bold;
}
tr:nth-child(even) {
    background: #fff5f3;
}

/* 付録 */
.appendix {
    page-break-before: always;
}
.appendix h2 {
    font-size: 16pt;
    color: #555;
    border-bottom: 2px solid #888;
    padding-bottom: 6pt;
}

/* 図 (mermaid 由来 SVG) */
.diagram-inline {
    text-align: center;
    margin: 12pt 0;
    padding: 8pt;
    background: #fafafa;
    border: 1px solid #eee;
    border-radius: 4pt;
    page-break-inside: avoid;
}
.diagram-inline svg {
    max-width: 100%;
    height: auto;
}

/* blockquote */
blockquote {
    border-left: 4px solid #c0392b;
    margin: 10pt 0;
    padding: 6pt 12pt;
    background: #fff5f3;
    color: #555;
}

/* リスト */
ul, ol {
    margin: 6pt 0;
    padding-left: 20pt;
}
li {
    margin: 3pt 0;
}

/* 強調 */
strong {
    color: #a83224;
}

/* はじめに */
.intro {
    page-break-after: always;
}
.intro h2 {
    font-size: 18pt;
    color: #c0392b;
    border-bottom: 2px solid #c0392b;
    padding-bottom: 6pt;
}
"""


# ── ヘルパー関数 ─────────────────────────────────────────

def read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


SVG_NS = "http://www.w3.org/2000/svg"
XHTML_NS = "http://www.w3.org/1999/xhtml"


def _flatten_foreign_objects(svg_text):
    """mermaid が出力する SVG 内の <foreignObject> を <text> 要素に置換する。

    WeasyPrint は SVG 内の foreignObject (HTML) をレンダリングしないため、
    そのままだと PDF 上でテキストが消える。各 foreignObject の中身を
    プレーンテキストに正規化し、相当する <text>/<tspan> ノードに置き直す。
    """
    try:
        from lxml import etree
    except Exception:
        return svg_text

    try:
        parser = etree.XMLParser(remove_blank_text=False)
        root = etree.fromstring(svg_text.encode("utf-8"), parser=parser)
    except etree.XMLSyntaxError:
        return svg_text

    fos = root.findall(".//{%s}foreignObject" % SVG_NS)
    for fo in fos:
        # <br/> を改行に置換
        for br in list(fo.iter("{%s}br" % XHTML_NS)):
            tail = br.tail or ""
            br.tail = "\n" + tail
            parent = br.getparent()
            if parent is not None:
                parent.remove(br)
        text_content = "".join(fo.itertext()).strip()
        try:
            width = float(fo.get("width") or 0)
        except ValueError:
            width = 0.0
        try:
            height = float(fo.get("height") or 0)
        except ValueError:
            height = 0.0

        parent = fo.getparent()
        if parent is None:
            continue
        idx = list(parent).index(fo)
        parent.remove(fo)

        text_el = etree.Element("{%s}text" % SVG_NS)
        text_el.set("x", str(width / 2))
        text_el.set("y", str(height / 2))
        text_el.set("text-anchor", "middle")
        text_el.set("dominant-baseline", "middle")
        text_el.set(
            "font-family",
            "Hiragino Sans, Noto Sans CJK JP, sans-serif",
        )
        text_el.set("font-size", "13px")
        text_el.set("fill", "#1a1a1a")

        lines = [l for l in text_content.splitlines() if l.strip()]
        if not lines:
            lines = [""]
        n = len(lines)
        for i, line in enumerate(lines):
            tspan = etree.SubElement(text_el, "{%s}tspan" % SVG_NS)
            tspan.set("x", str(width / 2))
            dy = (i - (n - 1) / 2) * 1.2 * 13
            tspan.set("y", str(height / 2 + dy))
            tspan.text = line

        parent.insert(idx, text_el)

    return etree.tostring(root, encoding="unicode")


def mermaid_to_svg(mermaid_src):
    """Mermaid ソースを mmdc (mermaid-cli) で SVG に変換する。"""
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False) as f:
            f.write(mermaid_src)
            mmd_path = f.name
        svg_path = mmd_path.replace(".mmd", ".svg")
        result = subprocess.run(
            [
                "npx",
                "--yes",
                "@mermaid-js/mermaid-cli",
                "-i",
                mmd_path,
                "-o",
                svg_path,
                "-b",
                "white",
                "--width",
                "700",
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode == 0 and os.path.exists(svg_path):
            with open(svg_path, "r") as f:
                svg = f.read()
            os.remove(mmd_path)
            os.remove(svg_path)
            return _flatten_foreign_objects(svg)
        os.remove(mmd_path)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def render_mermaid_blocks(text):
    """Markdown 中の ```mermaid ブロックを SVG に変換して埋め込む。SVG 生成に失敗したら code として残す。"""

    def replace_mermaid(match):
        mermaid_src = match.group(1)
        svg = mermaid_to_svg(mermaid_src)
        if svg:
            return f'\n<div class="diagram-inline">{svg}</div>\n'
        return f"\n```text\n{mermaid_src}```\n"

    return re.sub(
        r"```mermaid\n(.*?)```",
        replace_mermaid,
        text,
        flags=re.DOTALL,
    )


def md_to_html(text):
    """Markdown を HTML に変換する。fenced code は Pygments でハイライト。"""
    text = render_mermaid_blocks(text)
    result = markdown.markdown(
        text,
        extensions=["tables", "fenced_code", "codehilite", "toc"],
        extension_configs={
            "codehilite": {"guess_lang": False, "css_class": "highlight"},
            "fenced_code": {
                "lang_prefix": "language-",
            },
        },
    )

    def highlight_block(match):
        lang = match.group(1) or ""
        code_html = match.group(2)
        import html as html_mod

        code_text = html_mod.unescape(code_html)
        try:
            lexer_name = lang if lang else "zig"
            lexer = get_lexer_by_name(lexer_name)
        except Exception:
            return match.group(0)
        fmt = HtmlFormatter(nowrap=False, cssclass="highlight", style="friendly")
        return pygments_highlight(code_text, lexer, fmt)

    result = re.sub(
        r'<pre><code class="language-(\w*)">(.*?)</code></pre>',
        highlight_block,
        result,
        flags=re.DOTALL,
    )
    return result


def strip_first_heading(md_text):
    """先頭の # 見出しを除去 (章タイトルは別途付ける)。"""
    lines = md_text.split("\n")
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    return "\n".join(lines).strip()


def make_anchor(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


# ── HTML 構築 ────────────────────────────────────────────

def build_cover():
    total_chapters = sum(len(p["chapters"]) for p in PARTS)
    return f"""
    <div class="cover">
        <div class="logo">&#x1F50C;</div>
        <h1>ch32fun_zig 技術ドキュメント</h1>
        <div class="subtitle">Zig 0.16 で CH32V003 (RV32EC) を焼くまで</div>
        <div class="meta">
            <p>対象: Zig 0.16 / CH32V003 / RV32EC</p>
            <p>全{total_chapters}章 + 付録{len(APPENDICES)}本</p>
        </div>
    </div>
    """


def build_toc():
    items = []
    ch_num = 1
    for part in PARTS:
        part_anchor = make_anchor(part["title"])
        items.append(f'<li><a href="#{part_anchor}">{part["title"]}</a><ul>')
        for _dir, title, desc in part["chapters"]:
            label = f"第{ch_num}章 {title}"
            anchor = make_anchor(f"ch{ch_num:02d}-{title}")
            ch_num += 1
            items.append(f'<li><a href="#{anchor}">{label}</a> — {desc}</li>')
        items.append("</ul></li>")

    items.append('<li><a href="#appendices">付録</a><ul>')
    for i, (_, label) in enumerate(APPENDICES):
        letter = chr(ord("A") + i)
        anchor = make_anchor(f"appendix-{letter}")
        items.append(f'<li><a href="#{anchor}">付録{letter}. {label}</a></li>')
    items.append("</ul></li>")

    inner = "\n".join(items)
    return f"""
    <div class="toc">
        <h2>目次</h2>
        <ul>{inner}</ul>
    </div>
    """


def build_intro():
    readme_path = os.path.join(BASE, "README.md")
    if not os.path.exists(readme_path):
        return ""
    md = read_file(readme_path)
    md = strip_first_heading(md)
    return f"""
    <div class="intro">
        <h2>はじめに</h2>
        {md_to_html(md)}
    </div>
    """


def build_chapters():
    parts_html = []
    ch_num = 1

    for part in PARTS:
        part_anchor = make_anchor(part["title"])
        parts_html.append(
            f"""
        <div class="part-title" id="{part_anchor}">
            <h2>{part["title"]}</h2>
            <div class="part-subtitle">{part["subtitle"]}</div>
        </div>
        """
        )

        for dir_name, title, desc in part["chapters"]:
            label = f"第{ch_num}章 {title}"
            anchor = make_anchor(f"ch{ch_num:02d}-{title}")
            ch_num += 1

            ch_dir = os.path.join(BASE, "chapters", dir_name)
            readme_path = os.path.join(ch_dir, "README.md")
            readme_md = read_file(readme_path)
            readme_md = strip_first_heading(readme_md)
            readme_html = md_to_html(readme_md)

            parts_html.append(
                f"""
            <div class="chapter" id="{anchor}">
                <h2>{label}</h2>
                <p style="color:#666; font-style:italic; margin-top:-6pt;">{desc}</p>
                {readme_html}
            </div>
            """
            )

    return "\n".join(parts_html)


def build_appendices():
    parts = []
    parts.append(
        """
    <div class="part-title" id="appendices">
        <h2>付録</h2>
        <div class="part-subtitle">補足資料</div>
    </div>
    """
    )

    for i, (fname, label) in enumerate(APPENDICES):
        letter = chr(ord("A") + i)
        anchor = make_anchor(f"appendix-{letter}")
        fpath = os.path.join(BASE, "notes", fname)
        md = read_file(fpath)
        md = strip_first_heading(md)
        content = md_to_html(md)
        parts.append(
            f"""
        <div class="appendix" id="{anchor}">
            <h2>付録{letter}. {label}</h2>
            {content}
        </div>
        """
        )

    return "\n".join(parts)


def build_full_html():
    return f"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<style>{CSS}</style>
</head>
<body>
{build_cover()}
{build_toc()}
{build_intro()}
{build_chapters()}
{build_appendices()}
</body>
</html>
"""


# ── メイン ───────────────────────────────────────────────

def main():
    print("Generating HTML...")
    full_html = build_full_html()

    html_path = os.path.join(BASE, "ch32fun-zig-tutorial.html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(full_html)
    print(f"  HTML written to {html_path}")

    print("Converting to PDF (this may take a minute)...")
    pdf_path = os.path.join(BASE, "ch32fun-zig-tutorial.pdf")
    weasyprint.HTML(filename=html_path).write_pdf(pdf_path)
    print(f"  PDF written to {pdf_path}")

    # HTML 中間ファイルを残すには KEEP_HTML=1 を指定する
    if not os.environ.get("KEEP_HTML"):
        os.remove(html_path)
    print("Done!")


if __name__ == "__main__":
    main()
