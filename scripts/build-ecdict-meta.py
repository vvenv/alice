#!/usr/bin/env python3
"""Build a compact offline EN→ZH word meta JSON from ECDICT.

Source: https://github.com/skywind3000/ECDICT (MIT)
Downloads ecdict.csv into .cache/ on first run, then writes
src/lib/ecdict-meta.json for in-app lookup.
"""

from __future__ import annotations

import csv
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE_CSV = ROOT / ".cache" / "ecdict.csv"
DATA_DIR = ROOT / "data"
OUT_JSON = ROOT / "src" / "lib" / "ecdict-meta.json"
ECDICT_URL = (
    "https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv"
)

EXAM_TAG_RE = re.compile(r"\b(zk|gk|cet4|cet6|ky|toefl|ielts|gre)\b", re.I)
POS_PREFIX_RE = re.compile(
    r"^(n\.|v\.|vt\.|vi\.|adj\.|adv\.|prep\.|conj\.|pron\.|num\.|art\.|"
    r"int\.|interj\.|aux\.|abbr\.|contr\.|pl\.|a\.|na\.|un\.|vbl\.|pp\.|"
    r"pn\.|exclam\.|pref\.|suf\.|suff\.|comb\.|quant\.|phr\.|ph\.|st\.|"
    r"pr\.|ind\.|pers\.|col\.|ing\.|pla\.|stuff\.)\s*",
    re.I,
)

WEAK_FORM_RE = re.compile(
    r"^[A-Za-z][A-Za-z\s'\-]*的"
    r"(过去式|过去分词|现在分词|第三人称单数|复数|比较级|最高级)"
)
LETTER_NAME_RE = re.compile(r"^第.+字母")
DOMAIN_TAG_RE = re.compile(r"^\[([^\]]+)\]\s*")
# exchange keys that are surface forms of the headword
FORM_KEYS = {"p", "d", "i", "3", "r", "t", "s"}

# ECDICT's entries for a few ultra-common function words are noisy.
OVERRIDES: dict[str, tuple[str, str]] = {
    "a": ("art.", "一个"),
    "an": ("art.", "一个"),
    "the": ("art.", "这；那"),
}


def ensure_csv() -> Path:
    CACHE_CSV.parent.mkdir(parents=True, exist_ok=True)
    if CACHE_CSV.exists() and CACHE_CSV.stat().st_size > 1_000_000:
        return CACHE_CSV
    print(f"Downloading ECDICT → {CACHE_CSV} …")
    urllib.request.urlretrieve(ECDICT_URL, CACHE_CSV)
    print(f"Downloaded {CACHE_CSV.stat().st_size / 1e6:.1f} MB")
    return CACHE_CSV


def speakable(line: str) -> str | None:
    text = line.strip()
    if not text:
        return None
    for pipe in ("|", "｜"):
        if pipe in text:
            text = text.split(pipe, 1)[0].strip()
    if "=" in text or "＝" in text:
        text = re.split(r"[=＝]", text, maxsplit=1)[0].strip()
    return text.lower() if text else None


def load_data_words() -> set[str]:
    words: set[str] = set()
    if not DATA_DIR.is_dir():
        return words
    for path in DATA_DIR.rglob("*.txt"):
        for line in path.read_text(encoding="utf-8").splitlines():
            w = speakable(line)
            if not w:
                continue
            words.add(w)
            if "/" in w:
                for part in w.split("/"):
                    part = part.strip()
                    if part:
                        words.add(part)
    return words


def normalize_meaning(raw: str) -> str:
    text = (
        raw.replace("\\n", " ")
        .replace("\\r", " ")
        .replace("\n", " ")
        .replace("\r", " ")
        .strip()
    )
    if not text:
        return text
    # Sense 内部的分号统一转为逗号，确保「；」只作为义项分隔符
    text = text.replace("；", "，").replace(";", "，")
    text = re.sub(r"\s+", " ", text).strip()
    # 宽松上限，仅防异常超长条目
    if len(text) > 80:
        text = text[:80].strip()
    return text


def parse_sense_line(line: str) -> tuple[str | None, str | None, int] | None:
    """Return (pos, meaning, priority). Higher priority is better."""
    line = line.strip()
    if not line:
        return None
    if line.startswith("【") or line.startswith("[网络]"):
        return None

    domain = DOMAIN_TAG_RE.match(line)
    if domain:
        line = line[domain.end() :].strip()
        if not line:
            return None
        priority = 0  # domain-tagged senses are noisy
    else:
        priority = 1

    pos: str | None = None
    m = POS_PREFIX_RE.match(line)
    if m:
        pos = m.group(1).lower()
        if pos == "a.":
            pos = "adj."
        if pos == "pl.":
            pos = "n."
        # ECDICT 用到的非标准缩写，归一为项目统一词性
        if pos in ("interj.", "exclam."):
            pos = "int."
        if pos in ("na.", "un.", "pla.", "pn."):
            pos = "n."
        if pos in ("vbl.", "pp."):
            pos = "v."
        if pos in ("pref.", "suf.", "suff.", "comb.", "stuff."):
            pos = "abbr."
        line = line[m.end() :].strip()
        # POS + another domain tag, e.g. "art. [计] 累加器"
        domain2 = DOMAIN_TAG_RE.match(line)
        if domain2:
            line = line[domain2.end() :].strip()
            priority = 0
        else:
            priority = 2

    meaning = normalize_meaning(line)
    if WEAK_FORM_RE.match(meaning or ""):
        return None
    if meaning and LETTER_NAME_RE.match(meaning):
        return None
    if not pos and not meaning:
        return None
    return pos, meaning or None, priority


def parse_translation(raw: str) -> tuple[str | None, str | None]:
    """Return (pos, meaning) from an ECDICT translation field.

    All senses are kept: the highest-priority sense supplies the POS, and
    every sense's meaning is joined with「；」. Senses whose POS differs from
    the main POS are prefixed inline (e.g. `n. 放任`) so each sense stays
    self-describing.
    """
    # ECDICT mixes real newlines with literal "\n" / "\r" separators.
    text = (
        (raw or "")
        .replace("\\n", "\n")
        .replace("\\r", "\n")
        .replace("\r", "\n")
        .strip()
    )
    if not text:
        return None, None

    senses: list[tuple[str | None, str | None, int]] = []
    for line in text.split("\n"):
        sense = parse_sense_line(line)
        if sense:
            senses.append(sense)

    if not senses:
        return None, None

    senses.sort(key=lambda s: s[2], reverse=True)
    main_pos = senses[0][0]
    parts: list[str] = []
    for pos, meaning, _ in senses:
        if not meaning:
            continue
        if pos and pos != main_pos:
            parts.append(f"{pos} {meaning}")
        else:
            parts.append(meaning)
    return main_pos, "；".join(parts) if parts else None


def is_weak(pos: str | None, meaning: str | None) -> bool:
    if not pos and not meaning:
        return True
    if meaning and WEAK_FORM_RE.match(meaning):
        return True
    return False


def parse_exchange(raw: str) -> dict[str, str]:
    """Parse `d:done/p:did/0:do` → {d: done, p: did, 0: do}."""
    out: dict[str, str] = {}
    for part in (raw or "").split("/"):
        part = part.strip()
        if not part or ":" not in part:
            continue
        key, val = part.split(":", 1)
        key = key.strip()
        val = val.strip().lower()
        if key and val:
            out[key] = val
    return out


def should_keep(
    word: str,
    tag: str,
    collins: int,
    oxford: int,
    frq: int,
    bnc: int,
) -> bool:
    if EXAM_TAG_RE.search(tag or ""):
        return True
    if oxford:
        return True
    if collins >= 1:
        return True
    if 0 < frq <= 20000 or 0 < bnc <= 20000:
        return True
    return False


def to_int(value: str | None) -> int:
    try:
        return int((value or "0").strip() or "0")
    except ValueError:
        return 0


def main() -> None:
    csv_path = ensure_csv()
    data_words = load_data_words()
    print(f"data words: {len(data_words)}")

    # word(lower) → {pos, meaning, exchange}
    entries: dict[str, dict] = {}
    # 词库词兜底候选:常规过滤未保留的 key → 首个条目的解析结果
    fallback: dict[str, dict] = {}

    with csv_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            word = (row.get("word") or "").strip()
            if not word:
                continue
            translation = (row.get("translation") or "").strip()
            if not translation:
                continue
            key = word.lower()

            pos, meaning = parse_translation(translation)
            if key in OVERRIDES:
                pos, meaning = OVERRIDES[key]

            # 词库词兜底:记录首个条目(无论常规过滤是否通过)
            if key in data_words and key not in fallback:
                fallback[key] = {
                    "pos": pos,
                    "meaning": meaning,
                    "exchange": parse_exchange(row.get("exchange") or ""),
                }

            if not should_keep(
                word,
                row.get("tag") or "",
                to_int(row.get("collins")),
                to_int(row.get("oxford")),
                to_int(row.get("frq")),
                to_int(row.get("bnc")),
            ):
                continue
            # Prefer first occurrence; ECDICT is mostly unique by word
            if key in entries and not is_weak(
                entries[key].get("pos"), entries[key].get("meaning")
            ):
                continue
            entries[key] = {
                "pos": pos,
                "meaning": meaning,
                "exchange": parse_exchange(row.get("exchange") or ""),
            }
            fallback.pop(key, None)

    # 词库词兜底:常规过滤未保留的词库词,保留首个条目
    fallback_keys: set[str] = set()
    for key, meta in fallback.items():
        if key not in entries:
            entries[key] = meta
            fallback_keys.add(key)

    # Resolve weak form glosses via lemma (exchange 0:)
    for key, meta in list(entries.items()):
        if not is_weak(meta.get("pos"), meta.get("meaning")):
            continue
        lemma = meta["exchange"].get("0")
        if not lemma or lemma not in entries:
            continue
        src = entries[lemma]
        if is_weak(src.get("pos"), src.get("meaning")):
            continue
        meta["pos"] = src.get("pos")
        meta["meaning"] = src.get("meaning")

    # Propagate headword meta to surface forms from exchange
    for head, meta in list(entries.items()):
        if is_weak(meta.get("pos"), meta.get("meaning")):
            continue
        for ek, form in meta["exchange"].items():
            if ek not in FORM_KEYS:
                continue
            if form == head:
                continue
            existing = entries.get(form)
            # 词库保底条目(fallback)不阻止词根释义覆盖,避免噪声条目占位
            if (
                existing
                and not is_weak(existing.get("pos"), existing.get("meaning"))
                and form not in fallback_keys
            ):
                continue
            entries[form] = {
                "pos": meta.get("pos"),
                "meaning": meta.get("meaning"),
                "exchange": existing["exchange"] if existing else {},
            }
            # 已被词根释义覆盖的保底条目视为常规条目,避免后续传播再次覆盖
            # (leaves 同时是 leaf/leave 的表层形式,先到先得稳定)
            fallback_keys.discard(form)

    # Compact: "pos|meaning" string (pos may be empty)
    out: dict[str, str] = {}
    for key, meta in entries.items():
        pos = meta.get("pos") or ""
        meaning = meta.get("meaning") or ""
        if not pos and not meaning:
            continue
        out[key] = f"{pos}|{meaning}" if pos else f"|{meaning}"

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(
        json.dumps(out, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    size_kb = OUT_JSON.stat().st_size / 1024
    print(f"wrote {len(out)} entries → {OUT_JSON} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
