#!/usr/bin/env python3
"""
lang2lang.py — одноразовый конвертер выделенного текста между раскладками.

Использование:
    python3 lang2lang.py --convert ru
    python3 lang2lang.py --convert ua
    python3 lang2lang.py --convert en

Горячие клавиши назначаются через настройки GNOME на запуск этой команды.

Зависимости: -
Системные: paplay
"""

import argparse
import ast
import json
import os
import subprocess
import sys
import threading
import tkinter

import logging
import string

# Символы, которые не должны влиять на выбор таблицы
PUNCTUATION = set(string.punctuation) | set("«»—–…“”„‘’")

# Кандидаты для целевого языка -> как распознать xkb-код
LANG_MATCHERS = {
    "en": lambda code: code == "us" or "eng" in code.split("+") or "en" in code.split("+"),
    "ru": lambda code: "ru" in code.split("+"),
    "ua": lambda code: "ua" in code.split("+"),
}

logging.basicConfig(
    filename='/tmp/lang2lang.log',
    level=logging.DEBUG,
    format='%(asctime)s %(levelname)s %(message)s'
)


def log(msg):
    logging.info(msg)
    print(msg)


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ERROR_SOUND = os.path.join(SCRIPT_DIR, "error.wav")


def get_input_sources():
    """Возвращает список xkb-кодов в порядке input-sources."""
    try:
        res = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.input-sources", "sources"],
            capture_output=True, check=True, text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return []

    raw = res.stdout.strip()
    try:
        parsed = ast.literal_eval(raw)  # [('xkb', 'ca+eng'), ...]
    except (ValueError, SyntaxError):
        return []

    return [code for _kind, code in parsed if _kind == "xkb"]


def find_layout_index(target_lang):
    """Ищет индекс раскладки для целевого языка или None."""
    matcher = LANG_MATCHERS.get(target_lang)
    if matcher is None:
        return None

    sources = get_input_sources()
    for idx, code in enumerate(sources):
        if matcher(code):
            return idx
    return None


def switch_layout(target_lang):
    """Переключение текущей раскладки на целевой язык через D-Bus интерфейс Shyriiwook"""
    # Сначала находим фактическое имя раскладки, соответствующее целевому языку
    idx = find_layout_index(target_lang)
    if idx is None:
        log(f"layout for '{target_lang}' not found")
        return

    # Получаем список раскладок и извлекаем имя целевой раскладки
    sources = get_input_sources()
    if not sources or idx >= len(sources):
        return
    layout_name = sources[idx]

    try:
        subprocess.run([
            "gdbus", "call",
            "--session",
            "--dest", "org.gnome.Shell",
            "--object-path", "/me/madhead/Shyriiwook",
            "--method", "me.madhead.Shyriiwook.activate",
            layout_name
        ], check=False, capture_output=True)
    except FileNotFoundError:
        log("gdbus not found")

# ---------------------------------------------------------------
# 1. Загрузка парных таблиц из JSON-файлов
# ---------------------------------------------------------------
def load_pair_tables():
    """
    Читает все *.json в каталоге скрипта.
    Ожидаемый формат:
      { "en_ru": {"a": "ф", ...}, "ru_en": {"ф": "a", ...} }
    Возвращает список словарей:
      [ {"from": "en", "to": "ru", "map": {...}}, ... ]
    """
    tables = []
    for name in sorted(os.listdir(SCRIPT_DIR)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(SCRIPT_DIR, name)
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:
            print(f"[lang2lang] Не удалось прочитать {path}: {e}", file=sys.stderr)
            continue
        for pair_key, mapping in data.items():
            if "_" not in pair_key:
                continue
            src, dst = pair_key.split("_", 1)
            tables.append({"from": src, "to": dst, "map": mapping})
    return tables


# ---------------------------------------------------------------
# 2. Чтение текущего выделения (PRIMARY selection)
# ---------------------------------------------------------------
def get_primary_selection():
    """Возвращает текст PRIMARY selection или пустую строку."""
    root = tkinter.Tk()
    root.withdraw()
    try:
        text = root.selection_get(selection="PRIMARY")
        return text or ""
    except tkinter.TclError:
        return ""
    finally:
        root.destroy()


# ---------------------------------------------------------------
# 3. Работа с буфером обмена и вставка
# ---------------------------------------------------------------
def get_clipboard():
    try:
        res = subprocess.run(
            ["xclip", "-selection", "clipboard", "-o"],
            capture_output=True,
            check=True,
        )
        return res.stdout.decode("utf-8", errors="replace")
    except (FileNotFoundError, subprocess.CalledProcessError):
        return ""


def set_clipboard(text):
    try:
        subprocess.run(
            ["xclip", "-selection", "clipboard"],
            input=text.encode("utf-8"),
            check=False,
            capture_output=True,
        )
    except FileNotFoundError:
        pass


def paste():
    """Эмулирует Ctrl+V."""
    # pyautogui.hotkey("ctrl", "v")
    subprocess.run(["xdotool", "key", "ctrl+v"], check=False)


# ---------------------------------------------------------------
# 4. Звук ошибки
# ---------------------------------------------------------------
def play_error_sound():
    if not os.path.exists(ERROR_SOUND):
        return
    try:
        subprocess.run(["paplay", ERROR_SOUND], check=False, capture_output=True)
    except FileNotFoundError:
        pass


# ---------------------------------------------------------------
# 5. Логика преобразования
# ---------------------------------------------------------------
def convert(text, target_lang, tables):
    """
    Ищет пару, у которой to == target_lang и которая даёт
    максимальное число совпадений с исходным текстом.
    Пунктуация при подсчёте score игнорируется, чтобы общие
    символы (запятая, точка и т.п.) не выбирали чужую таблицу.
    Возвращает (converted_text, found_bool).
    """
    candidates = [t for t in tables if t["to"] == target_lang]
    if not candidates:
        return text, False

    best = None
    best_score = 0
    for t in candidates:
        score = sum(
            1 for ch in text
            if ch not in PUNCTUATION and ch in t["map"]
        )
        if score > best_score:
            best_score = score
            best = t

    if best is None or best_score == 0:
        return text, False

    converted = "".join(best["map"].get(ch, ch) for ch in text)
    return converted, True


# ---------------------------------------------------------------
# 6. Одноразовое выполнение
# ---------------------------------------------------------------
def run_once(target_lang):
    log(f"=== start, target={target_lang} ===")
    tables = load_pair_tables()
    log(f"tables loaded: {len(tables)}")

    selected = get_primary_selection()
    log(f"selection: {repr(selected[:100])}")  # первые 100 символов

    if not selected:
        log("empty selection, abort")
        play_error_sound()
        sys.exit(0)

    converted, found = convert(selected, target_lang, tables)
    log(f"converted: {repr(converted[:100])}, found={found}")
    if not found or converted == selected:
        play_error_sound()
        sys.exit(0)

    switch_layout(target_lang)
    # threading.Event().wait(0.1)  # небольшая пауза, чтобы раскладка применилась

    # orig_clipboard = get_clipboard()
    # set_clipboard(converted)
    #
    # # Небольшая задержка, чтобы буфер успел обновиться
    threading.Event().wait(0.3)
    # paste()
    # threading.Event().wait(0.5)
    #
    # # Восстанавливаем буфер
    # set_clipboard(orig_clipboard)

    subprocess.run(["xdotool", "type", "--clearmodifiers", converted], check=False)


# ---------------------------------------------------------------
# 7. main
# ---------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Одноразовый конвертер выделенного текста между раскладками."
    )
    parser.add_argument(
        "--convert",
        required=True,
        metavar="LANG",
        help="Целевой язык: ru, ua, en",
    )
    args = parser.parse_args()

    target_lang = args.convert.strip().lower()
    if not target_lang:
        print("[lang2lang] Пустой целевой язык", file=sys.stderr)
        sys.exit(1)

    run_once(target_lang)


if __name__ == "__main__":
    main()
