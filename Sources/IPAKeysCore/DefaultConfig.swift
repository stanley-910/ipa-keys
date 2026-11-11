// The config written on first run. Generated once from the ipa.typeit.org
// tables; edit the user's copy at ~/.config/ipa-keys/config.txt instead.

public let defaultConfigText = #"""
# ipa-keys config. Edit, save, and the change applies at once.
# Lines starting with # are comments. The file is UTF-8 text.
#
# A dotted circle ◌ in front of a combining mark is only there so you can
# see the mark; ipa-keys removes it when it reads the file.

[settings]
# Hold these keys and press a key from [groups] below.
# Any of: control, shift, option, command, joined with +.
chord = control+shift

# Type this, then a name from [names], e.g. ;schwa
prefix = ;

# A chord that turns ipa-keys on and off, e.g. control+shift+escape.
# Empty means none (use the menu bar item).
toggle =

# Apps where cycling a symbol uses Backspace instead of selecting it
# (terminals, where Shift+Left does not select). Bundle ids, space-separated.
backspace_apps = com.apple.Terminal com.googlecode.iterm2 com.mitchellh.ghostty net.kovidgoyal.kitty io.alacritty org.alacritty com.github.wez.wezterm dev.warp.Warp-Stable co.zeit.hyper

[groups]
# key = symbols. The chord plus the key types the first symbol; press it
# again to swap in the next one. These follow ipa.typeit.org (Alt+letter).
# Each symbol also gets a typed name: the key and its place, so ;e1 is ə
# and ;e2 is ɚ.
# Keys other than letters and digits are written as names:
# grave comma period slash semicolon quote minus equals lbracket rbracket backslash

a = ɑ æ ɐ ɑ̃
b = β ɓ
c = ç ɕ
d = ð d͡ʒ ɖ ɗ
e = ə ɚ ɵ
3 = ɛ ɜ ɝ ɛ̃
g = ɠ ɢ
h = ħ ɦ ɥ ɧ ʜ
i = ɪ ɨ ɪ̈
j = ʝ ɟ
l = ɫ ɭ ɬ ʟ ɮ
m = ɱ
n = ŋ ɲ ɳ ɴ
o = ɔ œ ɒ ɔ̃
0 = ø
p = ɸ
r = ɾ ɹ ʁ ʀ ɻ ɽ
s = ʃ ʂ
t = θ t͡ʃ t͡s ʈ
u = ʊ ʉ
v = ʌ ʋ
w = ɯ ʍ ɰ
x = χ
y = ɣ ʎ ʏ ɤ
z = ʒ ʐ ʑ
2 = ʔ ʕ ʡ ʢ
q = ˈ ˌ
f = ◌͡ ‿

# Not on ipa.typeit.org: diacritics, tones and clicks
# clicks (k for click)
k = ʘ ǀ ǃ ǂ ǁ
# ejective (looks like the key)
quote = ʼ
# length: long, half-long, extra-short
period = ː ˑ ◌̆
# nasalized, velarized (tilde is on this key)
grave = ◌̃ ◌̴
# phonation: voiceless, voiceless above, voiced, breathy, creaky
comma = ◌̥ ◌̊ ◌̬ ◌̤ ◌̰
# place: dental, apical, laminal, linguolabial
lbracket = ◌̪ ◌̺ ◌̻ ◌̼
# tongue: advanced, retracted, raised, lowered, ATR, RTR
rbracket = ◌̟ ◌̠ ◌̝ ◌̞ ◌̘ ◌̙
# vowels: centralized, mid-centralized, more/less rounded, rhotic, syllabic, non-syllabic
minus = ◌̈ ◌̽ ◌̹ ◌̜ ˞ ◌̩ ◌̯
# release: nasal, lateral, unreleased; prenasal ᵐ ᵑ
equals = ⁿ ˡ ◌̚ ᵐ ᵑ
# tie below
backslash = ◌͜
# superscripts (^ is on this key)
6 = ʰ ʷ ʲ ˠ ˤ ʱ ˀ ᵊ
# more superscripts (8 is next to 6)
8 = ʳ ᵗ ᵝ
# rules: becomes, null
9 = → ∅
# tone letters, extra-high to extra-low
1 = ˥ ˦ ˧ ˨ ˩
# level tone marks, extra-high to extra-low
4 = ◌̋ ◌́ ◌̄ ◌̀ ◌̏
# contour tone marks: rising, falling, high rising, low rising, rising-falling
5 = ◌̌ ◌̂ ◌᷄ ◌᷅ ◌᷈
# downstep, upstep, global rise, global fall, major group
7 = ↓ ↑ ↗ ↘ ‖

[names]
# name = text. Type the prefix and the name; it becomes the text.
# A combining mark goes after its letter: u;extrashort gives ŭ.
# No name may be the start of another (lo and long would clash), because a
# name is replaced as soon as it is typed.

# Plosives
tretro = ʈ
dretro = ɖ
barj = ɟ
ipag = ɡ
smallg = ɢ
glottal = ʔ

# Nasals
meng = ɱ
nretro = ɳ
npal = ɲ
eng = ŋ
smalln = ɴ

# Trills and taps
smallb = ʙ
smallr = ʀ
vflap = ⱱ
tap = ɾ
flapretro = ɽ

# Fricatives
phi = ɸ
beta = β
theta = θ
eth = ð
esh = ʃ
ezh = ʒ
sretro = ʂ
zretro = ʐ
ccedilla = ç
jcurly = ʝ
gamma = ɣ
chi = χ
rinverted = ʁ
hbar = ħ
revglottal = ʕ
hhook = ɦ

# Laterals and approximants
belt = ɬ
lezh = ɮ
vscript = ʋ
rturned = ɹ
rretro = ɻ
mleg = ɰ
lretro = ɭ
yturned = ʎ
smalll = ʟ
ldark = ɫ

# Clicks
bullseye = ʘ
clickdental = ǀ
clickalveolar = ǃ
clickpalatal = ǂ
clicklateral = ǁ

# Implosives and ejective
bhook = ɓ
dhook = ɗ
jhook = ʄ
ghook = ɠ
uvularimplosive = ʛ
ejective = ʼ

# Other consonants
wturned = ʍ
hturned = ɥ
smallh = ʜ
epiglottalfric = ʢ
epiglottalstop = ʡ
ccurly = ɕ
zcurly = ʑ
lateralflap = ɺ
heng = ɧ

# Vowels
ibar = ɨ
ubar = ʉ
mturned = ɯ
smalli = ɪ
smally = ʏ
upsilon = ʊ
oslash = ø
ereversed = ɘ
obar = ɵ
ramshorn = ɤ
schwa = ə
epsilon = ɛ
oe = œ
revepsilon = ɜ
closedepsilon = ɞ
wedge = ʌ
openo = ɔ
ash = æ
aturned = ɐ
smalloe = ɶ
ascript = ɑ
scriptaturned = ɒ
rschwa = ɚ
rrevepsilon = ɝ

# Length, stress and breaks
primary = ˈ
secondary = ˌ
long = ː
halflong = ˑ
extrashort = ◌̆
majorgroup = ‖
linking = ‿

# Intonation
downstep = ↓
upstep = ↑
globalrise = ↗
globalfall = ↘

# Tone letters
tone5 = ˥
tone4 = ˦
tone3 = ˧
tone2 = ˨
tone1 = ˩

# Tone marks
extrahigh = ◌̋
hightone = ◌́
midtone = ◌̄
lowtone = ◌̀
extralow = ◌̏
risingtone = ◌̌
fallingtone = ◌̂

# Diacritics
voiceless = ◌̥
abovevoiceless = ◌̊
voiced = ◌̬
aspirated = ʰ
morerounded = ◌̹
lessrounded = ◌̜
advanced = ◌̟
retracted = ◌̠
centralized = ◌̈
midcentralized = ◌̽
syllabic = ◌̩
nonsyllabic = ◌̯
rhotic = ˞
breathy = ◌̤
creaky = ◌̰
linguolabial = ◌̼
labialized = ʷ
palatalized = ʲ
velarized = ˠ
pharyngealized = ˤ
midtilde = ◌̴
raised = ◌̝
lowered = ◌̞
atr = ◌̘
rtr = ◌̙
dental = ◌̪
apical = ◌̺
laminal = ◌̻
nasalized = ◌̃
nasalrelease = ⁿ
lateralrelease = ˡ
unreleased = ◌̚
tiebar = ◌͡
tiebelow = ◌͜

# Affricate ligatures
tshlig = ʧ
dzhlig = ʤ
tslig = ʦ
dzlig = ʣ
tclig = ʨ
dzclig = ʥ

# More superscripts
supglottal = ˀ
murmuraspirated = ʱ
supm = ᵐ
supeng = ᵑ
supschwa = ᵊ
supr = ʳ
supt = ᵗ
supbeta = ᵝ

# Contour tones
highrising = ◌᷄
lowrising = ◌᷅
risingfalling = ◌᷈

# Rules
becomes = →
null = ∅
"""#
