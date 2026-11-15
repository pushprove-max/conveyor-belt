// SPDX-License-Identifier: Apache-2.0
// Loads one file per entry of panels/index.js, then starts the page. A file that fails to load does not hold the
// others: its panel says so in its own place.
(function () {
  'use strict';
  const ids = Array.isArray(window.DASH_PANELS) ? window.DASH_PANELS : [];
  let left = ids.length;
  const done = () => { left -= 1; if (left <= 0) window.DASH_APP.start(); };
  if (!ids.length) { window.DASH_APP.start(); return; }
  ids.forEach((id) => {
    const s = document.createElement('script');
    s.src = `panels/${id}.js`;
    s.async = false;
    s.addEventListener('load', done);
    s.addEventListener('error', done);
    document.head.append(s);
  });
}());
