"""把评审视频的台词与分镜导出成一份可改的 Word。

用法： python tools/export_review_script_docx.py [输出路径]
默认输出到桌面与 outputs/review-video/ 各一份。

数据来源：
  scripts/demo_director.gd   —— 屏幕字幕与章节卡（连行号一起读，改代码时能定位）
  docs/评审视频脚本与分镜.md —— 旁白逐字稿与画面描述

表格分两张：表一是屏幕上真的会出现的字（改完要重录），表二是旁白（只影响配音稿）。
"""

import re
import sys
import os
from pathlib import Path

from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.section import WD_ORIENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "demo_director.gd"
MD = ROOT / "docs" / "评审视频脚本与分镜.md"
FONT = "微软雅黑"


# ---------------- 读代码里的台词 ----------------

def parse_lines():
    rows = []
    func = ""
    for i, line in enumerate(SRC.read_text(encoding="utf-8").splitlines(), 1):
        m = re.match(r"func (\w+)\(", line)
        if m:
            func = m.group(1)
        for mm in re.finditer(r'_say\("([^"]*)"\s*(?:,\s*([\d.]+))?\)', line):
            rows.append(dict(line=i, func=func, kind="say", text=mm.group(1)))
        for mm in re.finditer(r'_card\("([^"]*)"\s*,\s*"([^"]*)"\s*(?:,\s*([\d.]+))?\)', line):
            rows.append(dict(line=i, func=func, kind="card",
                             text=mm.group(1) + "｜" + mm.group(2)))
    return rows


# 每条的约时间与它出现的界面（按代码顺序，人工校准过一遍成片）
PLACE = [
    ("0:00", "黑底片头卡（录制时叠加，不在游戏内）"),
    ("0:05", "主菜单｜左上标题 + 左下按钮列"),
    ("0:07", "主菜单｜开始页全景"),
    ("0:12", "主菜单｜开始页全景"),
    ("0:16", "主菜单｜开始页全景"),
    ("0:21", "主菜单｜右上实拍相册"),
    ("0:24", "知识卡图鉴（主菜单→知识卡）"),
    ("0:30", "知识卡图鉴｜卡面网格"),
    ("0:38", "知识卡图鉴｜下滑一屏后"),
    ("0:42", "黑底章节卡"),
    ("0:45", "主菜单｜难度四档展开"),
    ("0:51", "主菜单｜种子输入框"),
    ("0:57", "本局天赋弹窗（开局第一屏）"),
    ("1:01", "局内｜左守护站面板 + 右生态监测"),
    ("1:06", "局内｜沙盘候鸟、水草、房屋"),
    ("1:11", "局内｜水位双线与参考区间"),
    ("1:15", "局内｜手牌扇形展开"),
    ("1:22", "局内｜待执行区（三张牌落桌）"),
    ("1:31", "局内｜甩牌逐张弹分 + 结算小票"),
    ("1:36", "局内｜结算反馈弹窗"),
    ("1:42", "局内｜知识卡弹窗"),
    ("1:41", "局内｜第 2 回合起手牌"),
    ("1:53", "局内｜危机预警横幅 / 回合结算"),
    ("2:09", "黑底章节卡"),
    ("2:11", "局内｜手牌（讲卡牌厚度）"),
    ("2:18", "牌库全屏「全部卡牌」"),
    ("2:24", "卡牌详情页｜左侧大卡 + 右侧说明"),
    ("2:37", "卡牌详情关闭后回局内"),
    ("2:43", "局内｜手牌与沙盘同框"),
    ("2:47", "结尾短片（两分钟成片，取第 4 秒起 12 秒）"),
    ("3:05", "黑底收尾卡"),
    ("3:10", "黑底收尾卡（数据页）"),
]

REWRITE_HINT = ""


# ---------------- 读 md 里的旁白 ----------------

def parse_md():
    rows = []
    for line in MD.read_text(encoding="utf-8").splitlines():
        if not re.match(r"^\| \d:\d\d \|", line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 4:
            rows.append(dict(time=cells[0], shot=cells[1], sub=cells[2], vo=cells[3]))
    return rows


# ---------------- Word 小工具 ----------------

def font(run, size=9, bold=False, color=None):
    run.font.name = FONT
    run.font.size = Pt(size)
    run.font.bold = bold
    if color:
        run.font.color.rgb = RGBColor(*color)
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:eastAsia"), FONT)


def shade(cell, hex_fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:fill"), hex_fill)
    tc_pr.append(shd)


def header_repeat(row):
    tr_pr = row._tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader")
    el.set(qn("w:val"), "true")
    tr_pr.append(el)


def fill_cell(cell, text, size=9, bold=False, align=None, color=None):
    cell.text = ""
    p = cell.paragraphs[0]
    if align is not None:
        p.alignment = align
    p.paragraph_format.space_before = Pt(1)
    p.paragraph_format.space_after = Pt(1)
    run = p.add_run(text)
    font(run, size=size, bold=bold, color=color)


def make_table(doc, widths, head, rows, yellow_last=True):
    table = doc.add_table(rows=1, cols=len(head))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    hdr = table.rows[0]
    header_repeat(hdr)
    for i, name in enumerate(head):
        c = hdr.cells[i]
        c.width = Cm(widths[i])
        fill_cell(c, name, size=9, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)
        shade(c, "DCE4EC")
    for row in rows:
        cells = table.add_row().cells
        for i, val in enumerate(row):
            cells[i].width = Cm(widths[i])
            align = WD_ALIGN_PARAGRAPH.CENTER if i in (0, 1) else None
            fill_cell(cells[i], str(val), size=9, align=align)
            if yellow_last and i == len(head) - 1:
                shade(cells[i], "FFF8DC")
    return table


def para(doc, text, size=10, bold=False, space_after=6, color=None):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing = 1.25
    run = p.add_run(text)
    font(run, size=size, bold=bold, color=color)
    return p


# ---------------- 组装 ----------------

def build(out_path: Path):
    code = parse_lines()
    if len(code) != len(PLACE):
        raise SystemExit(f"台词条数 {len(code)} 与时间表 {len(PLACE)} 对不上，先核一遍 demo_director.gd")
    md = parse_md()

    doc = Document()
    sec = doc.sections[0]
    sec.orientation = WD_ORIENT.LANDSCAPE
    sec.page_width, sec.page_height = sec.page_height, sec.page_width
    for attr in ("left_margin", "right_margin"):
        setattr(sec, attr, Cm(1.4))
    sec.top_margin = Cm(1.4)
    sec.bottom_margin = Cm(1.2)

    style = doc.styles["Normal"]
    style.font.name = FONT
    style.font.size = Pt(10)
    style.element.rPr.rFonts.set(qn("w:eastAsia"), FONT)

    t = doc.add_paragraph()
    t.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = t.add_run("评审视频台词校对表 · 鄱阳归翎-生态修复手记")
    font(r, size=17, bold=True)
    sub = doc.add_paragraph()
    sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = sub.add_run("对应成片 outputs/review-video/demo_review.mp4（1280×720 / 30fps / 3 分 12 秒）")
    font(r, size=9, color=(0x55, 0x5F, 0x66))

    para(doc, "这份表是给你改台词用的。表一是屏幕上真的会出现的字，改它等于改片子，改完必须重录；表二是旁白，只决定配音稿，不动画面。两张表最后一列都是空的，直接在里面写新词，写完整份发回来，我按“代码位置”那一列落回代码再录一遍。你要是想自己动手，代码位置给到了文件、函数和行号，改完跑文末那条命令就行。", size=10)
    para(doc, "写的时候有个尺寸限制：字幕条宽 780 像素、字号 21，一行大约放 40 个汉字。超过会自动折行，条子会跟着变高（这版已经改成按行数撑高），现在最长的一条 44 字就会折成两行（条子跟着变高，字不会跑出去），但两行会遮住更多画面，所以尽量一句话说完，控制在 40 字以内。", size=10)

    para(doc, "分镜大纲", size=12, bold=True, space_after=3)
    para(doc, "片头到 0:42 是立意段：片头卡给一句话定位，接着用主菜单全景讲鄱阳湖、讲玩家身份（16 个回合走完四年的湿地守护站站长）、讲受众（中小学生与亲子），最后用知识卡图鉴把「牌背后是真实行动、照片带出处」讲掉。这一段不操作，镜头停在开始页，靠右上角相册自动翻页提供运动。", size=10)
    para(doc, "0:42 到 1:41 是玩法段：选普通难度、输固定种子 20261018、点出发，先看天赋弹窗，再在局内把左右面板、沙盘、水位线讲一遍，然后完整打一个回合——选三张牌、执行、逐张弹分、结算弹窗、知识卡弹窗。这一回合是全片唯一完整展示的回合，目的是让人看清「一步操作换来哪些数字」。", size=10)
    para(doc, "1:41 到 3:12 是后果与技术：先连打三个回合，每个回合压到 2.6 倍结算速度，展示危机预警怎么变成下一回合的账单；再用牌库全屏和一张卡详情页讲卡面渲染（透视、投影、陀螺仪倾斜都在 2D 画布里算完）；然后播十二秒结尾短片，收在黑底数据页。", size=10)
    para(doc, "表里的时间码是按成片逐段校准的，误差在一两秒内，够你判断这句是在哪个镜头里说的。", size=9, color=(0x55, 0x5F, 0x66))

    para(doc, "表一　屏幕字幕与章节卡（改完要重录）", size=12, bold=True, space_after=3)
    rows = []
    for i, item in enumerate(code, 1):
        time, place = PLACE[i - 1]
        loc = f"demo_director.gd:{item['line']}｜{item['func']}"
        kind = "章节卡" if item["kind"] == "card" else "字幕"
        rows.append([i, time, place, kind, item["text"], loc, REWRITE_HINT])
    make_table(doc, [0.9, 1.3, 5.2, 1.3, 6.6, 5.3, 4.4],
               ["#", "时间", "画面 / 界面", "类型", "现在的台词", "代码位置", "改写"],
               rows)

    doc.add_paragraph()
    para(doc, "表二　旁白逐字稿（只影响配音，不改画面）", size=12, bold=True, space_after=3)
    rows2 = []
    for i, item in enumerate(md, 1):
        rows2.append([i, item["time"], item["shot"], item["vo"], REWRITE_HINT])
    make_table(doc, [0.9, 1.3, 7.4, 10.4, 5.6],
               ["#", "时间", "画面", "现在的旁白", "改写"],
               rows2)

    doc.add_paragraph()
    para(doc, "重录一次要动的东西", size=12, bold=True, space_after=3)
    rows3 = [
        ["录制", "Godot_v4.7.2-stable_win64_console.exe --path <工程> res://scenes/demo.tscn --write-movie <目录>/demo.avi --fixed-fps 30", "约 2 分 25 秒，比实时快"],
        ["转码", "ffmpeg -i demo.avi -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart demo_review.mp4", "约 20 秒，47 MB"],
        ["试跑", "同上加 --fast（解说等待压到 8%，35 秒跑完全片）或 --skip-intro（直接从开局看）", "改完先用这个验"],
    ]
    make_table(doc, [2.4, 17.3, 5.6], ["做什么", "命令", "耗时"], rows3, yellow_last=False)

    para(doc, "改旁白不影响这几条命令，只有改表一（屏幕字幕）才需要重录。录完的音轨是游戏原声，旁白要另外录一条干声再混。", size=9, space_after=0, color=(0x55, 0x5F, 0x66))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(out_path))
    return out_path


if __name__ == "__main__":
    outs = []
    if len(sys.argv) > 1:
        outs.append(Path(sys.argv[1]))
    else:
        desktop = Path(os.path.expanduser("~")) / "Desktop" / "评审视频台词校对表.docx"
        outs.append(desktop)
        outs.append(ROOT / "outputs" / "review-video" / "评审视频台词校对表.docx")
    for o in outs:
        build(o)
        print("wrote", o)
