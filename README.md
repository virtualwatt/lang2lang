# lang2lang

A one-shot converter for selected text between keyboard layouts. Select text, press a hotkey — the script reads the selection, maps each character to the target layout, switches the system layout to the target, and types the result in place of the selection.

Supported directions are defined by JSON files in the project directory: `en-ru.json`, `en-ua.json`, `ru-ua.json` (and the reverse pairs inside them). To add a new language you just drop another JSON file next to them — no code changes required.

---

## Requirements

### 1. System utilities

The script calls these from the command line, so they must be in `PATH`.

| Utility | Purpose |
|---|---|
| `xdotool` | input emulation (`xdotool type`) |
| `xclip` | clipboard access |
| `paplay` | plays `error.wav` (pipewire/pulseaudio) |
| `gsettings` | reads the GNOME layout list |
| `gdbus` | calls the Shyriiwook extension to switch layout |

Install (Debian/Ubuntu):

```bash
sudo apt install xdotool xclip pulseaudio-utils python3-tk
```

Fedora:

```bash
sudo dnf install xdotool xclip pulseaudio-utils python3-tkinter
```

Arch:

```bash
sudo pacman -S xdotool xclip libpulse tk
```

> `python3-tk` is needed because the script reads the PRIMARY selection through `tkinter`. Some distributions do not ship it with the base Python package.

### 2. GNOME extension Shyriiwook

The standard `gsettings set org.gnome.desktop.input-sources current N` **does not work** on modern GNOME — the key is deprecated and ignored. Layout switching is done through the D-Bus interface exposed by the extension.

1. Install the **Shyriiwook** extension from [extensions.gnome.org](https://extensions.gnome.org/) (or via `gnome-extensions install`).
2. Enable it:

```bash
gnome-extensions enable shyriiwook@madhead.me
```

3. Log out and back in (or `Alt+F2` → `r` → Enter on X11) so the extension loads.
4. Verify the interface is available:

```bash
gdbus introspect --session --dest org.gnome.Shell \
    --object-path /me/madhead/Shyriiwook --only-properties
```

   The output should contain the layout list (`availableLayouts`).

### 3. The `uv` utility

`uv` is a Python environment and dependency manager. Install it:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After installation, restart your shell or run `source ~/.local/bin/env` (the path may differ — check the installer output). Verify:

```bash
uv --version
```

---

## Installing the project

```bash
git clone <REPO-URL> ~/dev/py/lang2lang
cd ~/dev/py/lang2lang

# create the virtual environment and install dependencies
uv sync
```

`uv sync` creates `.venv/` in the project directory and installs the pip dependencies from `pyproject.toml` (if the list is empty the environment will be empty, but `.venv/bin/python` will still exist and be used).

Verify the script runs:

```bash
uv run python lang2lang.py --convert en
```

Expected behavior: if nothing is selected — silence and an error sound (if `error.wav` is present); a record appears in `/tmp/lang2lang.log`.

---

## Assigning hotkeys

Hotkeys are assigned through GNOME: **Settings → Keyboard → Keyboard Shortcuts → Custom Shortcuts** (`+`).

For each command set a name, a key combination, and the **full command**. The command must launch the project's `.venv` Python through `uv run` so the correct environment is used.

Command template:

```
/home/USER/.local/bin/uv run /path/to/lang2lang/.venv/bin/python /path/to/lang2lang/lang2lang.py --convert LANG
```

Replace `USER` and `/path/to/lang2lang` with your own. Example for user `virtualvat` with the project in `~/dev/py/lang2lang`:

**English** (`Super+Alt+E`):

```
/home/virtualvat/.local/bin/uv run /home/virtualvat/dev/py/lang2lang/.venv/bin/python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert en
```

**Russian** (`Super+Alt+R`):

```
/home/virtualvat/.local/bin/uv run /home/virtualvat/dev/py/lang2lang/.venv/bin/python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert ru
```

**Ukrainian** (`Super+Alt+U`):

```
/home/virtualvat/.local/bin/uv run /home/virtualvat/dev/py/lang2lang/.venv/bin/python /home/virtualvat/dev/py/lang2lang/lang2lang.py --convert ua
```

> If `uv` is not installed in `~/.local/bin`, find its path with `command -v uv` and substitute it into the command.
>
> Do not use `uv run lang2lang.py` without an explicit path to `.venv/bin/python` — in that case `uv run` will try to recreate the environment and may behave unpredictably when launched from a hotkey (no working directory, no TTY). An explicit interpreter path is more reliable.

### How it works step by step

1. Select text in any application (with the mouse or `Shift`+arrows).
2. Press the hotkey.
3. The script reads the PRIMARY selection, picks the JSON pair whose `to` matches `--convert` and which yields the most matches (punctuation is ignored when scoring so common characters like a comma do not select the wrong table).
4. If conversion is possible and the result differs from the source:
   - it switches the layout to the target via Shyriiwook;
   - it types the converted text with `xdotool type --clearmodifiers`.
5. If conversion is not possible (no matches, empty selection) — it plays `error.wav` and does nothing.

The log is written to `/tmp/lang2lang.log` — look there when debugging.

---

## Adding a new language

The JSON file format is a dictionary of pairs. The pair key is `"<from>_<to>"`, the value is a per-character mapping dictionary. The direction is defined by the presence of a pair with the required `to`: for `--convert xx` the script looks for all pairs where `to == "xx"`.

Example (`en-ru.json`):

```json
{
  "en_ru": { "q": "й", "w": "ц", "...": "..." },
  "ru_en": { "й": "q", "ц": "w", "...": "..." }
}
```

Requirements:

- the pair key must contain `_` (otherwise the pair is ignored);
- the file name is arbitrary, only the `.json` extension matters;
- UTF-8 encoding.

### AI prompt for generating a new pair

Copy the prompt below into a chat with an AI (Claude, GPT, etc.), substituting the desired languages and layouts. The prompt is designed so the AI returns ready-to-save JSON.

```
You are helping generate a key mapping file for the lang2lang utility.
The utility converts selected text from one layout to another
character by character, using a JSON dictionary.

Generate JSON for the language pair: SOURCE_LANG -> TARGET_LANG.
Layouts: SOURCE_LAYOUT (xkb code) and TARGET_LAYOUT (xkb code).

Response format — a single JSON object, no explanations, no markdown wrapper:

{
  "SOURCE_CODE_TARGET_CODE": { "<char in source layout>": "<char in target layout>", ... },
  "TARGET_CODE_SOURCE_CODE": { "<char in target layout>": "<char in source layout>", ... }
}

Requirements:
1. The first pair (SOURCE_TARGET) is a direct mapping: each key of the
   source layout maps to the character the same physical key produces
   in the target layout. This is NOT transliteration but a mapping by
   key position on the keyboard.
2. The second pair (TARGET_SOURCE) is the reverse mapping obtained by
   inverting the first pair.
3. Cover ALL printable keys: letters in both cases, digits (if they
   differ between the layouts), punctuation, brackets, special
   characters. Do not include modifier keys, Enter, Tab, arrows,
   F-keys.
4. If some key in the target layout produces a character that does not
   exist in the source layout, or vice versa — skip it and list it
   separately at the end of the response in an "UNMAPPED: ..." block
   (this is the only text outside the JSON).
5. Make sure the JSON is valid: double quotes, escaping of `"` and `\`.
6. Do not add comments inside the JSON.
```

After receiving the response:

1. Save the JSON to a file in the project directory, e.g. `de-fr.json` (the name is arbitrary, the `.json` extension matters).
2. Validate it: `python -m json.tool de-fr.json > /dev/null`.
3. Put the file next to the others and make sure it is read:

```bash
uv run python -c "import lang2lang; print(len(lang2lang.load_pair_tables()))"
```

   (the number should increase).
4. Assign a hotkey with `--convert <target_code>`.

### What to check after generation

- **The reverse pair** is really the inverse of the forward one. AI sometimes "hallucinates" and builds the reverse mapping by meaning instead of by inversion. Quick check:

```python
import json
d = json.load(open("de-fr.json"))
fwd, rev = list(d.values())
bad = [(k, v, rev.get(v)) for k, v in fwd.items() if rev.get(v) != k]
print(bad)  # should be empty
```

- **Case**: uppercase letters and `Shift` symbols (e.g. `:` `"` `{` `}`) are covered in both the forward and reverse pairs.
- **Target-layout special characters** that do not exist in the source layout (e.g. `ґ` in Ukrainian, `ё` in Russian, `ß` in German) — they must be in the reverse pair even if there is no "physical" source key for them in the forward pair.
- **Punctuation** shared by both layouts (comma, period, space) may be present in both pairs — that is fine; `convert()` ignores punctuation when choosing the table, so it will not affect direction selection.
- **Cyrillic vs Latin**: for pairs like `ru-ua` (both Cyrillic) the forward and reverse pairs differ in only a few letters (`ы↔і`, `ъ↔ї`, `э↔є`, `ё↔'`). The AI may try to "pad" the file with extra mappings — it is better to keep only the real differences, otherwise `convert()` may pick the wrong table due to random matches.

---

## Debugging

Log: `/tmp/lang2lang.log`. Useful entries:

- `selection: '...'` — what was read from the PRIMARY selection (first 100 characters);
- `converted: '...', found=True/False` — the conversion result and whether a matching table was found;
- `layout for 'xx' not found` — there is no layout corresponding to the target language in `input-sources` (check `gsettings get org.gnome.desktop.input-sources sources`).

If the layout does not switch:

- check that the Shyriiwook extension is enabled: `gnome-extensions list --enabled | grep shyriiwook`;
- check D-Bus manually:

```bash
gdbus call --session --dest org.gnome.Shell \
    --object-path /me/madhead/Shyriiwook \
    --method me.madhead.Shyriiwook.activate ru
```

- make sure you are in an X11 session (`echo $XDG_SESSION_TYPE` → `x11`). Under Wayland `xdotool type` does not work; you would need `ydotool`/`wtype` — that is a separate improvement, the current version targets X11.

If `xdotool type` types the wrong thing:

- check that the layout actually switched before typing (there is a 0.3 s pause in `run_once`; if the race remains, increase it);
- make sure the target layout contains all characters from `converted` (e.g. `ґ` requires a Ukrainian layout with `ґ`, not a `ua` variant without it).

---

## License

MIT. See `LICENSE`.
