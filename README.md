# ipa-keys

Type IPA symbols in any Mac app, the way [ipa.typeit.org](https://ipa.typeit.org)
works, plus typed names. It is one small menu bar app with no other tools needed.

- **Chord cycling.** Hold **Control+Shift** and press a key. You get the first
  symbol of that key's group. Press it again straight away to swap in the next
  one; it wraps round. Control+Shift+E gives ə, again ɚ, again ɵ, then ə.
  Keys with no group work as usual.
- **Marks stack on letters.** Diacritics and tone marks are combining
  characters. Type `u`, press Control+Shift+. three times, and you get ŭ.
  Cycling a mark swaps only the mark and keeps the letter.
- **Typed names.** Type `;` and a name, and it is replaced as soon as the
  name is complete: `;schwa` gives ə, `;e1` gives ə (the first symbol under
  E), and `u;extrashort` gives ŭ.

The menu bar item (ə) has **Enabled**, **Edit Config**, **Reload**, **Update…** and **Quit**.
It greys out when ipa-keys is off, has no permission, or a password field has
the keyboard.

## Install (first time)

1. Open **Terminal** and install Apple's command line tools (skip if you
   have Xcode): `xcode-select --install`, then follow the window that opens.
2. Download ipa-keys: `git clone https://github.com/stanley-910/ipa-keys.git ~/ipa-keys`
3. Install it: `~/ipa-keys/scripts/install.sh`. The first time, this makes
   a signing certificate, and macOS may ask for your login password.
4. Allow it: **System Settings > Privacy & Security > Accessibility**, turn on
   **ipa-keys** (click **+** and choose `~/Applications/ipa-keys.app` if it is
   not listed). The **ə** in the menu bar stops being grey.

## Update

1. Click **ə** in the menu bar, then **Update…**. Or in Terminal run
   `~/ipa-keys/scripts/update.sh`.
2. Read the last lines in the window. They say which version is now running,
   or, in plain words, why the update stopped. Your settings file is never
   changed by an update.

## Install details

```sh
scripts/install.sh
```

`scripts/install.sh` checks for the command line tools, builds a release
binary, makes `~/Applications/ipa-keys.app`, signs it, and loads a LaunchAgent (`cc.stanleywang.ipa-keys`) that starts it at login
and restarts it if it crashes (not if you quit it).

Signing: a stable certificate keeps the Accessibility grant across rebuilds.
`build-app.sh` uses `$IPA_KEYS_SIGN_IDENTITY`, otherwise `ipa-keys-dev`,
otherwise `dictate-dev`. When neither exists, `install.sh` runs
`scripts/make-cert.sh` to create `ipa-keys-dev`; if that fails it says so and
prints the command to run. With no certificate the app is signed ad hoc, and macOS asks
for Accessibility again after every build.

## Permission

ipa-keys needs **Accessibility** to read keys and type symbols:

1. On first launch macOS shows a prompt. Click **Open System Settings**, or go
   to **System Settings > Privacy & Security > Accessibility**.
2. Turn on **ipa-keys**. If it is not listed, click **+** and choose
   `~/Applications/ipa-keys.app`.
3. That's all. ipa-keys checks once a second and starts within a second of
   the grant, with no restart. The log says `ready`.

If a rebuild was signed ad hoc and keys stop working, remove ipa-keys from
the list and add it again.

## Config

Everything is in **`~/.config/ipa-keys/config.txt`** (menu: Edit Config). It
is plain text, written on first run and never overwritten after that. Saving
it applies the change within a second; Reload does it at once. To get the
defaults back, delete the file and choose Reload. The built-in copy is in
`Sources/IPAKeysCore/DefaultConfig.swift`.

```
[settings]
chord = control+shift        # any of control shift option command
prefix = ;                   # starts a typed name
toggle =                     # e.g. control+shift+escape; empty = none
backspace_apps = com.apple.Terminal ...   # see "How cycling deletes"

[groups]
e = ə ɚ ɵ                    # key = symbols, in cycling order
comma = ◌̥ ◌̊ ◌̬ ◌̤ ◌̰

[names]
schwa = ə
extrashort = ◌̆
```

- Lines starting with `#` are comments.
- A dotted circle **◌** in front of a combining mark only makes the mark
  visible in the file. It is removed when the file is read.
- Group keys are letters and digits, or these names for other keys: `grave`
  `comma` `period` `slash` `semicolon` `quote` `minus` `equals` `lbracket`
  `rbracket` `backslash`. Keys are matched by what they type on the current
  keyboard layout.
- Every group symbol also gets a name made from its key and place: `e1`, `e2`,
  `,1`, `k3`. These are not written out in the file. A name in `[names]` with
  the same spelling wins.
- A name is replaced as soon as it is typed, so no name may be the start of
  another. If `lo` and `long` were both names, `;long` could never be typed.
  Keep groups to 9 symbols, or `e1` clashes with `e10`. Clashes and other
  mistakes are written to the log, and the menu shows **Config problems**.

### Default groups

The letter groups match ipa.typeit.org's Alt+letter keys, in its order: `a b
c d e 3 g h i j l m n o 0 p r s t u v w x y z 2 q f`. Keys with no letter on
the site:

| Key | Symbols |
|---|---|
| `k` | clicks ʘ ǀ ǃ ǂ ǁ |
| `'` | ejective ʼ |
| `.` | length ː ˑ ◌̆ |
| `` ` `` | nasalized ◌̃, velarized ◌̴ (the tilde key) |
| `,` | phonation: voiceless ◌̥ ◌̊, voiced ◌̬, breathy ◌̤, creaky ◌̰ |
| `[` | place: dental ◌̪, apical ◌̺, laminal ◌̻, linguolabial ◌̼ |
| `]` | tongue: advanced ◌̟, retracted ◌̠, raised ◌̝, lowered ◌̞, ATR ◌̘, RTR ◌̙ |
| `-` | vowels: centralized ◌̈, mid-centralized ◌̽, more ◌̹ / less ◌̜ rounded, rhotic ˞, syllabic ◌̩, non-syllabic ◌̯ |
| `=` | release: nasal ⁿ, lateral ˡ, unreleased ◌̚, prenasal ᵐ ᵑ |
| `\` | tie below ◌͜ |
| `6` | superscripts ʰ ʷ ʲ ˠ ˤ ʱ ˀ ᵊ (^ is on this key) |
| `1` | tone letters ˥ ˦ ˧ ˨ ˩ |
| `4` | level tone marks ◌̋ ◌́ ◌̄ ◌̀ ◌̏ |
| `5` | contour tone marks ◌̌ ◌̂ ◌᷄ ◌᷅ ◌᷈ |
| `7` | intonation ↓ ↑ ↗ ↘ ‖ |

A few symbols the site doesn't put on a key have a name but no chord: ɡ ʙ ⱱ
ɰ ʄ ʛ ʢ ʡ ɺ ɘ ɞ ɶ and the ligatures ʧ ʤ ʦ ʣ ʨ ʥ.

## How cycling deletes

Apps don't agree on what Backspace removes after a combining mark. These were
tested on this machine, in code (no keys typed):

| | Backspace after ŭ (u + breve) |
|---|---|
| Cocoa text (TextEdit, Notes, most text fields) | removes u and the breve |
| WebKit (Safari, Mail) | removes u and the breve |
| Chrome / Chromium / Electron | removes only the breve |

Shift-Left behaves the same in all three: it selects the whole letter with its
marks. So to cycle, ipa-keys selects back over the symbol it typed with
Shift-Left and types over it. If the symbol was a mark, it types the letter
again with the new mark. That needs the letter, so ipa-keys remembers what was
typed since the last click, arrow key, shortcut or app switch.

When it doesn't know the letter (you clicked after an existing letter, added a
mark, then cycled), it sends Control-Backspace once per code point instead.
Cocoa maps that to "delete the last mark only", and Chrome treats it as
Backspace, which already does that. Safari and Mail treat it as a plain
Backspace, so there the letter goes too.

Terminals (`backspace_apps`) don't select with Shift-Left, so ipa-keys sends
one Backspace per code point there. zsh and bash delete one code point per
Backspace by default, so this should be right, but it is not tested.

## Log and troubleshooting

`~/.local/state/ipa-keys/ipa-keys.log` records start-up, the permission state,
config problems, secure input on and off, tap restarts, and for every chord or
name the app it went to and the keys sent, with code points. For example:

```
cycle e2 in com.apple.TextEdit (select mode): Shift-Left x1, type "ɚ" (U+025A)
```

`~/Applications/ipa-keys.app/Contents/MacOS/ipa-keys --check` prints the
config problems and which physical key each group is on, then exits. It needs
no permission.

## Known limits

- **Password fields.** While secure input is on (a password field, or
  Terminal's Secure Keyboard Entry), macOS hides keys from ipa-keys, so it
  does nothing.
- **Cycling a mark on a letter typed before a click** removes the letter too
  in Safari and Mail (see above). Type the letter again, or use a name.
- **Option and dead keys.** After an Option key (Option-E then e gives é),
  ipa-keys stops trusting what it remembers, so a mark cycled right after one
  takes the Control-Backspace path.
- **Autocorrect.** If an app changes the text between two presses (autocorrect,
  smart quotes, autocomplete), the next cycle may select the wrong amount.
- **Shortcuts.** With the default chord, Control+Shift plus a grouped key never
  reaches the app. Change `chord` if an app needs one of those.
- **Layouts.** Keys are matched by what they type with no modifiers on the
  current layout. A config key the layout can only type with Shift (digits on
  AZERTY) falls back to its US position.
- **Names** are case-sensitive and must be typed in one go. Backspace while
  typing a name works; arrow keys or a click start over.
- It does not touch Control+Space, so it doesn't interfere with dictate.

## Development

```sh
swift test               # config parsing, cycling plans, name matching
swift build
scripts/install.sh       # build, install, restart
```

The pure logic is in `Sources/IPAKeysCore` (no AppKit). The event tap, key
posting and menu are in `Sources/ipa-keys`.
