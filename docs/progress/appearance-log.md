# Appearance foundation — execution log

Branch: `feat/appearance-foundation`. Owner manual checks remain pending.

## Atkinson gate (Task 15)

Downloaded into the new empty directory `/tmp/bugvoice-atkinson-eb1_3g8t` from the
[official Google Fonts source](https://github.com/googlefonts/atkinson-hyperlegible-next/tree/7925f50f649b3813257faf2f4c0b381011f434f1/fonts/otf),
commit `7925f50f649b3813257faf2f4c0b381011f434f1`, version **2.001**, SIL OFL 1.1.
Regular, SemiBold, Bold, Italic, SemiBoldItalic and BoldItalic were checked with
`python3 -I Scripts/check-font-glyphs.py <six OTF files>`.

Result: **FAIL, 98 of 151 required code points missing in every face**:
`U+0128–U+0129`, `U+0168–U+0169`, `U+01A0–U+01A1`, `U+01AF–U+01B0`,
`U+0309`, `U+0323`, `U+1EA0–U+1EF1`, `U+1EF4–U+1EF9`.
No font or license resource was copied into the app; no third-party dependency
was added. `hyperlegibleAvailable` is permanently false; the font card is hidden;
a stored `.hyperlegible` still decodes and renders as System.
