# three.js 0.170.0, vendored for Belt 3D

The Belt 3D panel (`panels/belt3d.js`, `belt3d-scene.js`) draws with [three.js](https://threejs.org) 0.170.0. The
page loads no code from another site (its security policy allows only its own folder), so the files it uses are kept
here and served by the dashboard's own server. They are fetched only when the panel is first shown.

- Source: the npm package `three@0.170.0`
  (integrity `sha512-FQK+LEpYc0fBD+J8g6oSEyyNzjp+Q7Ks1C568WWaoMRLW+TkNNWmenWeGgJjV105Gd+p/2ql1ZcjYvNiPZBhuQ==`).
- Licence: MIT, in `LICENSE` beside this file (the package's own).
- `three.module.min.js` is the package's `build/three.module.min.js`, as it is.
- `addons/` holds the add-ons the panel uses (RoundedBoxGeometry and CSS2DRenderer), from the package's
  `examples/jsm/`, in the same folders. Each is as it is but for one line: its `} from 'three';` reads `} from '../../three.module.min.js';`,
  since the page can have no import map (an inline script, which its policy refuses).

To update: fetch the new version with `npm pack three@<version>`, copy the same files, make the same one-line change,
and write each file's sha256 below. The view test checks every file listed here against its sha256.

| File | sha256 |
| --- | --- |
| LICENSE | 4c40a1ef62450b857c3b2aaf294936304cd552d965fbcd9d32d4c5bcf4ba4454 |
| three.module.min.js | 08fd7545d13d2c7fb65ab691530a802dafefd638596501854f267d0fb13c39e7 |
| addons/geometries/RoundedBoxGeometry.js | c28249681123aba730a2362e25ed9e1c0bb907144b719c6e7d84896b14c93e90 |
| addons/renderers/CSS2DRenderer.js | 1fe7f1a247ec72e1c3de8340d4a36bda70ea4df12986fea35f55fed06c5ef17d |
