/**
 * Federation Office Stage — thin embed loader for the React OfficeStage bundle.
 *
 * The bundle at /react-dist/assets/office-stage.js is self-contained (React is
 * bundled in) and self-mounting: it renders into #office-stage-root, reading
 * data-gateway / data-project from that element. This loader just prepares the
 * container and imports the module.
 *
 * For the full experience (roster/feed callbacks + vanilla fallback) prefer
 * tv-widget.js. This file remains a minimal drop-in for the diorama alone.
 *
 * Usage:
 *   <script src="/office-stage.js" data-gateway="https://fapi.drdeeks.xyz" data-project="autopilot"></script>
 *   <div id="federation-tv"></div>
 */
(function () {
  var script = document.currentScript;
  if (!script) return;

  var gatewayUrl = script.getAttribute('data-gateway') || 'https://fapi.drdeeks.xyz';
  var projectId = script.getAttribute('data-project') || 'autopilot';
  var containerSel = script.getAttribute('data-container') || '#federation-tv';

  var container = document.querySelector(containerSel);
  if (!container) return;

  var rootEl = container.querySelector('#office-stage-root');
  if (!rootEl) {
    rootEl = document.createElement('div');
    rootEl.id = 'office-stage-root';
    container.appendChild(rootEl);
  }
  rootEl.setAttribute('data-gateway', gatewayUrl);
  rootEl.setAttribute('data-project', projectId);

  var base = script.src && script.src.indexOf('/office-stage.js') >= 0
    ? script.src.replace(/\/office-stage\.js.*$/, '')
    : window.location.origin;

  // The bundle is an ES module and must be loaded as one, or `export` is a
  // parse error and it never mounts.
  var mod = document.createElement('script');
  mod.type = 'module';
  mod.src = base + '/react-dist/assets/office-stage.js';
  mod.onerror = function () {
    console.warn('[OfficeStage] failed to load bundle:', mod.src);
  };
  document.head.appendChild(mod);
})();
