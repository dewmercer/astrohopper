# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AstroHopper is a PWA for star-hopping with a phone strapped to a telescope (like digital setting circles, using the phone's gyro/gravity/compass sensors). The deployed product is a **single self-contained HTML file**: all code, the star/DSO database, images and the user manual are embedded in it. It must work fully offline and must never contact external services. The only network access is the optional Wikipedia frame the user opens.

## Build / run

Requires Python 3 and `python-markdown` (`pip install markdown`). The data sources are git submodules, so initialize them first:

```sh
git submodule update --init      # OpenNGC, western_constellations_atlas_of_space, vsop87-multilang
python3 deploy.py                # build astrohopper_deploy.html, sw_deploy.js, manual.html, jsdb.js
python3 deploy.py /path/to/www   # build, then copy deploy files into the target dir
python3 deploy.py -g /path/to/www  # also inject ga.html (Google Analytics); ga.html is not in the repo
python3 pyserver.py              # serve astrohopper_deploy.html at https://<ip>:8443/ using cert.pem
```

HTTPS is needed because browsers only expose device orientation and geolocation APIs on secure origins. Test on a real phone over `https://<your-ip>:8443/`. There are no tests and no linter.

## Architecture

- **`astrohopper.html`** is the entire app: CSS, markup and roughly 1900 lines of plain global-scope JS functions. There is no framework or bundler. The main parts:
  - Sensor input (`setupOrientationEvents`, iOS-specific `deviceOrientationListenerIOS`, and manual drag mode via `manual*`).
  - Rotation/projection math (`getRotationMatrix`, `getCameraRays`, `projectToCamera`).
  - Alignment (`selectAlign`).
  - Rendering (`plotStars`, `plotLines`, `plotBearing`).
  - Planets via VSOP87 (`getSolarSystemObject`).
  - Watch lists and user DSOs, persisted in `localStorage` per origin.
- **`create_data.py`** builds `jsdb.js` (generated, gitignored) from the submodules. HYG star data (mag ≤ 6), OpenNGC DSOs (mag ≤ 14) and Stellarium constellation lines go into globals: `allstars`, `allstars_index`, `constellation_lines`, `allstars_index_name`, `allstars_db_specs`.
  - Objects are grouped by type and sorted by magnitude. Constellation labels (`Ca`) and stars (`S`) always come last. `allstars_index[type]` holds the end offset of each type's group, and user objects (`U`) are appended after the stars at runtime.
  - Type codes: `S` star, `Ca` constellation, `Oc`/`Gc` open/globular cluster, `Ga` galaxy, `Ne` nebula, `P` planet/Moon.
  - Names are normalized (leading zeros are stripped, e.g. `NGC 0224` → `NGC224`). The JS `normalizeName` must stay consistent with the Python `normalize_name`.
- **`deploy.py`** inlines files by pattern-matching lines of `astrohopper.html`, so these exact forms matter:
  - A line starting with `<script src="path.js"></script>` is replaced by that file's contents.
  - `url(name.png)` in CSS and `<img ... src="path.png">` are replaced by base64 data URIs. Filenames must match `[a-z0-9_\-/]*\.png`.
  - A line starting with `MANUAL` is replaced by `README.md` rendered to HTML. `README.md` is the in-app user manual, so edits to it ship in the app.
  - `Settings (version)` gets the version string.
- **iOS app (`ios/`)** is a native SwiftUI port; see `ios/README.md`.
  - `AstroHopper.xcodeproj` is generated from `ios/project.yml` by XcodeGen; run `xcodegen generate` after adding files.
  - A pre-build script runs `ios/Tools/generate_data.py`, which reuses `create_data.py` and extracts the VSOP87 terms from `vsop87a_combined.js` into gitignored JSON.
  - `Model/` ports the web app's logic function-by-function, with doc comments naming the JS function each one replaces. Behavior changes to the web app should usually be mirrored there.
  - Tests (Swift Testing, including planet positions checked against the JS): `xcodebuild -project ios/AstroHopper.xcodeproj -scheme AstroHopper -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`. To run one test, add `-only-testing:AstroHopperTests/ParsingTests/parsesRA`.
- **Versioning:** `deploy.py` reads the version from the first line of `Changelog.md`, which must look like `YYYY-MM-DD: vX.Y.Z`. The same version goes into `sw.js` as the cache name (`astrohopper-<version>`), so bump the Changelog to force clients to pick up a new release.
