# img2ascii

Upload an image in your browser, get ASCII art back. Decoding and rendering
happen on your machine — nothing is sent anywhere.

```
                  :=*%@@@@@@@@@#+-.
              -#@@@@@@%%%%%%%%@@@@@@%=.
           :#@@@%%%%%%%%%%%%%%%%%%%%@@@@=
         =@@@%%%%%%%%%%%%%%%%%%%%%%%%%%@@@*
       .%@@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@=
      +@@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@@
     #@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@.
    %@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@.
   %@%%%%%%%%%@@@@@@@%%%%%%%%%%@@@@@@@%%%%%%%%%@@.
  +@%%%%%%%%%@@-   :#@%%%%%%%%@@=   .#@%%%%%%%%%@@
  @%%%%%%%%%%@       #@%%%%%%%@       *@%%%%%%%%%@+
 +@%%%%%%%%%%@       +@%%%%%%%@       -@%%%%%%%%%@@
 @@%%%%%%%%%%@-      @@%%%%%%%@-      @@%%%%%%%%%%@-
 @%%%%%%%%%%%@@%+==#@@%%%%%%%%@@@+==*@@%%%%%%%%%%%@#
.@%%%%%%%%%%%%%@@@@@%%%%%%%%%%%%@@@@@%%%%%%%%%%%%%@#
.@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
.@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%
 @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@=
 #@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@
  .@%%%%%%%@@@@@@@@%%%%%%%%%%%%%%%%@@@@@@@@@%%%%%%@*
   #@%%%%%%+  ... *@@@%%%%%%%%%%%@@%. ..  :@%%%%%@@
    @@%%%%%@+       +@@@@@@@@@@@@#:       @@%%%%@@=
     @@%%%%%@%         :=****+-.        =@@%%%%@@+
      @@%%%%%@@#                      =@@@%%%%@@=
       %@@%%%%%@@%-                .*@@@%%%%%@@-
        =@@%%%%%%@@@%*-.      .:+#@@@%%%%%%@@#
          #@@@%%%%%%@@@@@@@@@@@@@@%%%%%%%@@@:
            +@@@%%%%%%%%%%%%%%%%%%%%%%@@@#:
              :*@@@@@%%%%%%%%%%%%@@@@@%=
                  -*%@@@@@@@@@@@@%#=.
                        ......
```

## Modes

| mode | resolution | notes |
|---|---|---|
| `chars` | 1 cell = 1 sample | classic ASCII; charsets: standard, detailed, blocks, solid |
| `halfblocks` | 2 vertical px per cell | `▀` with per-half colors — 2× detail, renders in every monospace font |
| `braille` | 2×4 dots per cell | 8× detail; Otsu's-method thresholding; needs a braille-capable font |

Same image, three levels of detail — pick in the *mode* dropdown.

## Quality pipeline

1. box downsample to the output grid
2. unsharp sharpen (on by default)
3. contrast: histogram **stretch** (default) or **equalize** — fixes washed-out
   photos that would otherwise collapse into two characters
4. render: brightness → character ramp, colors → `<span>`s, or for braille an
   **Otsu** threshold decides which dots are lit
5. aspect correction (default 0.6 = typical browser cell width/height, so
   circles come out round, not squashed)

## Run it

Needs Lua 5.4, lua-socket, lua-zlib, and `djpeg` (libjpeg-turbo):

```bash
# with root / package manager
sudo apt install lua5.4 lua-socket lua-zlib libjpeg-turbo-progs
lua5.4 server.lua 8080
```

```bash
# without root: extract the same .debs into ./local/ (dpkg-deb -x), then
./run.sh 8080
```

Open <http://localhost:8080>, choose an image, convert.

Form controls: **mode**, **width** (10–400, default 160 — 160–200 resolves
faces and text), **charset**, **contrast**, **aspect**, **sharpen**, **invert**,
**color**.

## Supported formats

| format | decoder |
|---|---|
| PNG | pure Lua (`src/png.lua`) — all color types, 1/2/4/8/16-bit, Adam7 |
| JPEG | `djpeg -pnm` subprocess |
| BMP, PPM, PGM | built-in parsers |

Limits: 8 MB upload, up to 16384 px per side, 40 MP. Render times for a
1920×1080 PNG: ~0.3 s (chars, width 160), ~0.6 s (braille, width 200).

## Layout

```
server.lua           HTTP server, form UI, result pages
src/ascii.lua        resample → sharpen → contrast → render (all three modes)
src/image.lua        format dispatch (PNG / JPEG / BMP / PNM)
src/png.lua          pure-Lua PNG decoder
src/multipart.lua    multipart/form-data parser
tests/test_core.lua  63-assertion test suite
tests/gen_test_images.py  regenerates tests/img/*
run.sh               launcher (uses ./local toolchain if present)
```

## Tests

```bash
python3 tests/gen_test_images.py
lua5.4 tests/test_core.lua
```

Covers PNG variants (color types, 16-bit, palette, interlaced), JPEG/BMP/PNM,
all render modes, contrast, braille codepoint correctness, and input validation.
