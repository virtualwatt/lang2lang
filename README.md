# lang2lang

A one-shot converter for text typed in the wrong keyboard layout. Select text, press a hotkey, and it retypes the selection in the correct layout (for example, English `ghbdtn` becomes Russian `привет`).

Works by:
1. Reading the PRIMARY selection (the text you have highlighted).
2. Picking the best conversion table for the requested target language (it scores how many characters in your selection match a given table, ignoring punctuation).
3. Switching the GNOME input source to that target layout.
4. Retyping the converted text with `xdotool`.

If the selection is empty, nothing matches, or the conversion is a no-op, it plays an error sound (`error.wav`) and exits.

---

## Requirements

- Linux with GNOME Shell (the layout switching uses `gdbus` against the `org.gnome.Shell` `me.madhead.Shyriiwook` interface, so the **Shyriiwook** GNOME extension is required: https://github.com/madhead/shyriiwook).
- Python `>=3.12,<3.13` (see `pyproject.toml`).
- System binaries:
  - `gsettings` (part of GNOME, for reading input sources)
  - `gdbus` (part of GLib, for switching layouts)
  - `xdotool` (for typing the converted text)
  - `paplay` (PulseAudio/PipeWire, for the error sound; optional — if missing, the error sound is silently skipped)
  - `tkinter` (Python Tk, used to read the PRIMARY selection; usually provided by your distro's `python3-tk` package)

### Install the system dependencies

On Debian/Ubuntu-based systems:

```bash
sudo apt install xdotool pulseaudio-utils python3-tk libglib2.0-bin
```

On Fedora:

```bash
sudo dnf install xdotool pulseaudio-utils python3-tkinter glib2
```

On Arch:

```bash
sudo pacman -S xdotool libpulse tk glib2
```

Also install the **Shyriiwook** GNOME extension and make sure you have more than one input source configured (e.g. English + Russian, English + Ukrainian).

---

## Install `uv`

`uv` is the project's toolchain (dependency/environment manager and runner).

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

This installs `uv` into `~/.local/bin` (make sure that directory is on your `PATH`, then restart your shell or `source ~/.profile`).

Alternatively, via pipx:

```bash
pipx install uv
```

Verify:

```bash
uv --version
```

---

## Set up the project

Clone/copy the project directory somewhere (in the examples below it lives at `~/dev/py/lang2lang`), then from inside the project directory:

```bash
cd ~/dev/py/lang2lang
uv sync
```

`uv sync` creates a `.venv` in the project directory and installs the project (there are no third-party dependencies, so this is quick).

You can test the converter manually from a terminal while some text is selected:

```bash
uv run python lang2lang.py --convert en
```bash
uv run python lang2lang.py --convert ru
```bash
uv run python lang2lang.py --convert ua
```

Notes:
- `--convert` is the **target** language: `en`, `ru`, or `ua`.
- The script reads the PRIMARY selection, so select some text with the mouse first.
- Logs go to `/tmp/lang2lang.log` if something misbehaves.

---

## Assign GNOME hotkeys

Open **Settings → Keyboard → Keyboard Shortcuts → View and Customize Shortcuts → Custom Shortcuts** and add one shortcut per target language.

Use the **absolute path** to the `uv` binary (usually `~/.local/bin/uv`) and the absolute path to the project's `lang2lang.py`. Passing the interpreter from the project's `.venv` explicitly is the most reliable form:

```text
/home/virtualvat/.local/bin/uv run /home/virtualvat/dev/py/lang2lang/.venv/bin/python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert en
```

Replace `/home/virtualvat` with your own home directory, and the project path with wherever you put it.

Suggested shortcuts:

| Shortcut        | Command (example)                                                                                                                  |
|-----------------|-------------------------------------------------------------------------------------------------------------------------------------|
| `Super+Shift+E` | `/home/virtualvat/.local/bin/uv run /home/virtualvat/dev/py/lang2lang/.venv/bin/python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert en` |
| `Super+Shift+R` | `/home/virtualvat/.local/bin/uv run /home/virtualvat/dev/py/lang2lang/.venv/bin/python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert ru` |
| `Super+Shift+U` | `/home/virtualvat/.local/bin/uv run /home/virtualvat/dev/py/lang2lang/.venv/bin/python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert ua` |

A simpler alternative (works if the script is executable and the environment is already synced):

```text
/home/virtualvat/.local/bin/uv run python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert en
```

### Usage

1. Select (highlight) the text in any application.
2. Press the hotkey for the layout the text *should* be in.
3. The text is replaced in place, and the active layout is switched to the target language.

If nothing happens, check `/tmp/lang2lang.log` and make sure `error.wav` exists next to the script (otherwise errors are silent).

---

## How the conversion tables work

Conversion tables live in `*.json` files next to `lang2lang.py`. Each file can contain one or more pairs, keyed as `from_to`:

```json
{
  "en_ru": { "q": "й", "w": "ц", "...": "..." },
  "ru_en": { "й": "q", "ц": "w", "...": "..." }
}
```

- The **file name is irrelevant**; every `*.json` in the script's directory is loaded.
- The key is split on the first `_`: the left part is the source language, the right part is the target language.
- When you run `--convert <lang>`, only tables whose target equals `<lang>` are considered. Among those, the table that matches the most non-punctuation characters in the selection wins.
- Characters not present in the chosen table are left unchanged.
- Both directions must be present for a pair to be useful in practice (`en_ru` **and** `ru_en`, etc.), because the converter only uses the direction pointing at the requested target language.

Existing tables:

| File          | Pairs                       |
|---------------|-----------------------------|
| `en-ru.json`  | `en_ru`, `ru_en`            |
| `en-ua.json`  | `en_ua`, `ua_en`            |
| `ru-ua.json`  | `ru_ua`, `ua_ru` (only the differing letters: `ы/і`, `ъ/ї`, `э/є`, `ё/'`) |

Note that `ru-ua.json` is a *letter-level* mapping between two Cyrillic layouts, not a full physical keyboard mapping. It is used to fix individual letters, not to translate whole words typed in the other Cyrillic layout.

---

## Adding a new language

1. Decide the language codes (they are free-form strings used in `--convert` and in the JSON keys), e.g. `de`, `fr`, `pl`.
2. Create a new JSON file, e.g. `en-de.json`, containing both directions:

```json
{
  "en_de": {
    "q": "q", "w": "w", "e": "e",
    "a": "a", "s": "s", "d": "d",
    "...": "..."
  },
  "de_en": {
    "q": "q", "w": "w", "e": "e",
    "a": "a", "s": "s", "d": "d",
    "...": "..."
  }
}
```

The full standard 105-key physical mapping (rows `qwertyuiop[]`, `asdfghjkl;'`, `zxcvbnm,./`, plus `\|` and the shifted variants) is what you want for a complete table. See `en-ru.json` / `en-ua.json` for the exact shape.

3. Add the target language to the layout detection if you also want automatic layout switching. In `lang2lang.py`:

```python
LANG_MATCHERS = {
    "en": lambda code: code == "us" or "eng" in code.split("+") or "en" in code.split("+"),
    "ru": lambda code: "ru" in code.split("+"),
    "ua": lambda code: "ua" in code.split("+"),
    # add e.g.:
    # "de": lambda code: "de" in code.split("+"),
}
```

The matcher receives the xkb source code (e.g. `us`, `ru`, `ua+eng`) and must return `True` for the layout that corresponds to the target language.

4. Add a GNOME hotkey for the new `--convert <lang>` command, as described above.

> No code changes are needed just to *convert text* — dropping a new `*.json` file is enough. The `LANG_MATCHERS` change only controls the automatic layout switch.

### Prompt for generating a new table with an LLM

Paste the following into your favorite LLM (adjust the languages):

```text
I need a keyboard-layout conversion table in JSON for a tool that fixes text typed
in the wrong layout.

Source layout: English (US QWERTY, xkb code "us").
Target layout: German (xkb code "de").

Produce a JSON object with two keys, "en_de" and "de_en", in exactly this format:

{
  "en_de": { "<english char>": "<german char>", ... },
  "de_en": { "<german char>": "<english char>", ... }
}

Rules:
- Include ALL printable characters on a standard 105-key keyboard for both layouts:
  unshifted and shifted forms.
- Rows to cover, as physical positions on the keyboard:
    ` q w e r t y u i o p [ ] \ `
    ` a s d f g h j k l ; ' `
    ` z x c v b n m , . / `
  (backtick and tilde included)
- `en_de` maps the character produced by a key in the English layout to the
  character produced by the SAME physical key in the German layout.
- `de_en` must be the exact inverse of `en_de` (swap every key/value pair).
- Preserve case: uppercase maps to uppercase (e.g. "Q" -> "Q").
- Use literal characters (e.g. "й", "ї", "ß"), not escape sequences, except for
  backslash and double quote which must be escaped in JSON ("\\\\" and "\\"").
- Output valid JSON only, no comments, no trailing commas.
- If a character has no counterpart on the same physical key in the other layout,
  omit that entry from the table (do not guess).
```

Then save the result as `en-de.json` (or whatever matches your codes) in the project directory. It will be picked up automatically on the next run.

**Also useful to add after generating a table:**
- Spot-check a few tricky keys (punctuation, brackets, quotes) by comparing with the actual layouts in GNOME's keyboard layout viewer.
- Make sure the two halves are exact inverses of each other, e.g. with a quick script:
  ```bash
  uv run python -c "import json; d=json.load(open('en-de.json')); print(all(d['en_de'][k]==v and d['de_en'][v]==k for k,v in d['en_de'].items() if v in d['de_en']))"
  ```
- Add the corresponding `LANG_MATCHERS` entry if you want automatic layout switching.
- Add a hotkey for the new `--convert` target.

---

## Troubleshooting

- **Nothing happens when pressing the hotkey.** Check `/tmp/lang2lang.log`. Also make sure `error.wav` is present next to the script — otherwise failure is silent.
- **Error sound plays instead of converting.** Either nothing is selected, or the selection contains no characters that match the target table (e.g. you're converting to `en` while the text is already Latin with no Cyrillic characters).
- **Layout doesn't switch.** Confirm the **Shyriiwook** extension is installed and enabled, and that `gsettings get org.gnome.desktop.input-sources sources` lists a matching xkb source (e.g. `ru` or `ua+eng`).
- **`xdotool` types the wrong characters.** The active layout must actually be switched before typing. If needed, increase the pause in the script (the `threading.Event().wait(...)` calls show where a delay can be added).
- **`tkinter` import error.** Install `python3-tk` (Debian/Ubuntu), `python3-tkinter` (Fedora), or `tk` (Arch).
- **`gdbus`/`gsettings` not found.** Install GLib utilities (`libglib2.0-bin` on Debian/Ubuntu, `glib2` on Fedora/Arch).

---

## License

MIT — see `LICENSE`. Copyright (c) 2026 Vitaliy Tkachenko.