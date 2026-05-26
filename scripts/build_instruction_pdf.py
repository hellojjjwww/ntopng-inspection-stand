#!/usr/bin/env python3
"""Build the PDF installation guide from the Markdown source.

File: build_instruction_pdf.py
Version: 1.0.0
License: MIT
"""

from __future__ import annotations

import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "thesis" / "sources" / "instruction.md"
OUTPUT = ROOT / "thesis" / "installation_guide.pdf"
FONT_REGULAR = Path(r"C:\Windows\Fonts\arial.ttf")
FONT_BOLD = Path(r"C:\Windows\Fonts\arialbd.ttf")


def register_fonts() -> tuple[str, str]:
    """Register fonts with Cyrillic support and return regular/bold names."""
    if FONT_REGULAR.exists() and FONT_BOLD.exists():
        pdfmetrics.registerFont(TTFont("ArialCustom", str(FONT_REGULAR)))
        pdfmetrics.registerFont(TTFont("ArialCustom-Bold", str(FONT_BOLD)))
        return "ArialCustom", "ArialCustom-Bold"
    return "Helvetica", "Helvetica-Bold"


def escape_inline(text: str) -> str:
    """Escape lightweight Markdown inline syntax for ReportLab paragraphs."""
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"`([^`]+)`", r"<font name='Courier'>\1</font>", text)
    return text


def build_styles() -> dict[str, ParagraphStyle]:
    """Create the document style map."""
    regular, bold = register_fonts()
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName=bold,
            fontSize=22,
            leading=27,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#1f2937"),
            spaceAfter=8 * mm,
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["BodyText"],
            fontName=regular,
            fontSize=10.5,
            leading=15,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#4b5563"),
            spaceAfter=10 * mm,
        ),
        "h1": ParagraphStyle(
            "Heading1",
            parent=base["Heading1"],
            fontName=bold,
            fontSize=15,
            leading=19,
            textColor=colors.HexColor("#0f766e"),
            spaceBefore=5 * mm,
            spaceAfter=3 * mm,
            keepWithNext=True,
        ),
        "h2": ParagraphStyle(
            "Heading2",
            parent=base["Heading2"],
            fontName=bold,
            fontSize=12.5,
            leading=16,
            textColor=colors.HexColor("#1f2937"),
            spaceBefore=3 * mm,
            spaceAfter=2 * mm,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName=regular,
            fontSize=9.8,
            leading=14,
            alignment=TA_LEFT,
            spaceAfter=2.2 * mm,
        ),
        "bullet": ParagraphStyle(
            "Bullet",
            parent=base["BodyText"],
            fontName=regular,
            fontSize=9.6,
            leading=13,
            leftIndent=4 * mm,
            spaceAfter=1.5 * mm,
        ),
        "code": ParagraphStyle(
            "Code",
            parent=base["Code"],
            fontName="Courier",
            fontSize=8.2,
            leading=10,
            textColor=colors.HexColor("#111827"),
            backColor=colors.HexColor("#f3f4f6"),
            borderPadding=5,
            leftIndent=0,
            rightIndent=0,
            spaceBefore=1.5 * mm,
            spaceAfter=3 * mm,
        ),
        "footer": ParagraphStyle(
            "Footer",
            parent=base["BodyText"],
            fontName=regular,
            fontSize=8,
            leading=10,
            textColor=colors.HexColor("#6b7280"),
            alignment=TA_CENTER,
        ),
    }


def parse_markdown(markdown: str, styles: dict[str, ParagraphStyle]) -> list:
    """Convert a controlled Markdown subset into ReportLab flowables."""
    story: list = []
    lines = markdown.splitlines()
    idx = 0
    in_code = False
    code_lines: list[str] = []
    bullet_lines: list[str] = []
    numbered_lines: list[str] = []

    def flush_lists() -> None:
        nonlocal bullet_lines, numbered_lines
        if bullet_lines:
            items = [ListItem(Paragraph(escape_inline(item), styles["bullet"])) for item in bullet_lines]
            story.append(ListFlowable(items, bulletType="bullet", start="circle", leftIndent=8 * mm))
            story.append(Spacer(1, 1.5 * mm))
            bullet_lines = []
        if numbered_lines:
            items = [ListItem(Paragraph(escape_inline(item), styles["bullet"])) for item in numbered_lines]
            story.append(ListFlowable(items, bulletType="1", leftIndent=8 * mm))
            story.append(Spacer(1, 1.5 * mm))
            numbered_lines = []

    while idx < len(lines):
        raw = lines[idx]
        line = raw.rstrip()
        if line.startswith("```"):
            if in_code:
                story.append(Preformatted("\n".join(code_lines), styles["code"], maxLineLength=92))
                code_lines = []
                in_code = False
            else:
                flush_lists()
                in_code = True
            idx += 1
            continue
        if in_code:
            code_lines.append(line)
            idx += 1
            continue
        if not line:
            flush_lists()
            idx += 1
            continue
        if line.startswith("# "):
            flush_lists()
            story.append(Paragraph(escape_inline(line[2:]), styles["title"]))
            story.append(Paragraph("Краткое руководство по установке, запуску и проверке", styles["subtitle"]))
            idx += 1
            continue
        if line.startswith("## "):
            flush_lists()
            story.append(Paragraph(escape_inline(line[3:]), styles["h1"]))
            idx += 1
            continue
        if line.startswith("- "):
            bullet_lines.append(line[2:])
            idx += 1
            continue
        number_match = re.match(r"^\d+\.\s+(.*)$", line)
        if number_match:
            numbered_lines.append(number_match.group(1))
            idx += 1
            continue
        flush_lists()
        story.append(Paragraph(escape_inline(line), styles["body"]))
        idx += 1

    flush_lists()
    if code_lines:
        story.append(Preformatted("\n".join(code_lines), styles["code"], maxLineLength=92))
    return story


def add_footer(canvas, doc) -> None:  # noqa: ANN001
    """Draw page footer."""
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#6b7280"))
    canvas.drawCentredString(A4[0] / 2, 10 * mm, f"ntopng inspection stand · page {doc.page}")
    canvas.restoreState()


def main() -> None:
    """Build the PDF guide."""
    styles = build_styles()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    source_text = SOURCE.read_text(encoding="utf-8")
    story = parse_markdown(source_text, styles)

    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=18 * mm,
        title="Инструкция по установке и эксплуатации стенда ntopng / Zeek",
        author="ntopng inspection stand contributors",
    )
    doc.build(story, onFirstPage=add_footer, onLaterPages=add_footer)
    print(OUTPUT)


if __name__ == "__main__":
    main()
