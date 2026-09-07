# Screenshot provenance and reproduction

The four localized READMEs use actual window captures of MakerDock 1.5.1 Release:

| Locale | Library | Enlarged plate | Print record | Multiple selection |
| --- | --- | --- | --- | --- |
| English | [View](en/library.png) | [View](en/plates.png) | [View](en/print-record.png) | [View](en/selection.png) |
| Korean | [View](ko/library.png) | [View](ko/plates.png) | [View](ko/print-record.png) | [View](ko/selection.png) |
| Japanese | [View](ja/library.png) | [View](ja/plates.png) | [View](ja/print-record.png) | [View](ja/selection.png) |
| Simplified Chinese | [View](zh-Hans/library.png) | [View](zh-Hans/plates.png) | [View](zh-Hans/print-record.png) | [View](zh-Hans/selection.png) |

The images are native app captures, not mockups with translated text painted over them. Each app session uses its matching interface language and localized demo names, categories, and notes. No personal library data, website session, or third-party downloaded model is used.

## Original examples

`scripts/create-demo-library.py` generates six simple original model meshes, their preview renders, and a separate demo index. The example durations, filament amounts, and completion records are illustrative. They are not verified printer measurements. The meshes are demonstration assets rather than a set of validated printable products. The previews and metadata deliberately exercise multiple plates and completion states.

The generator refuses to overwrite an existing folder. Requires Python 3 and Pillow:

```sh
python3 -m venv /tmp/makerdock-demo-tools
/tmp/makerdock-demo-tools/bin/pip install Pillow
/tmp/makerdock-demo-tools/bin/python scripts/create-demo-library.py \
  /tmp/MakerDock-Demo-en --locale en
open -n /path/to/MakerDock.app --args \
  --library-root /tmp/MakerDock-Demo-en \
  -MakerDockLanguage en -AppleLanguages '(en)'
```

Repeat with `ko`, `ja`, and `zh-Hans`, using a new folder for each. Capture the actual app window after selecting a model, opening a plate, opening the completion dialog, and selecting multiple cards. Exit only the demo instance when finished. Do not point the generator at Application Support or replace a user's library to take screenshots.

Original example code, geometry, previews, and screenshots are part of this repository's MIT-licensed materials. The app icon was generated specifically for MakerDock; see [brand provenance](../../assets/brand/README.md).
