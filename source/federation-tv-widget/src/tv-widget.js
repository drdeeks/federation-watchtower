/**
 * Federation TV Widget loader.
 *
 * Primary presentation: the React OfficeStage diorama (self-mounting ES-module
 * bundle at /react-dist/assets/office-stage.js).
 * Fallback presentation: the legacy vanilla widget (tv-widget-vanilla.js) when
 * the React bundle fails to load or fails to render.
 *
 * The authoritative roster + event feed (delivered to host pages via the
 * onAgentsUpdate / onFeedUpdate / onAgentSelect callbacks) is driven by a small
 * data layer here in the React path, and by the vanilla engine in the fallback
 * path — so a host page's operations panels work regardless of which visual is
 * live. Presentation is ambient; the callbacks carry the real operational data.
 *
 * Usage:
 *   <script src="/tv-widget.js" data-gateway="https://fapi.drdeeks.xyz" data-project="autopilot"></script>
 *   <div id="federation-tv"></div>
 * or:
 *   new FederationTV({ projectId, container, gatewayUrl, onAgentsUpdate, onFeedUpdate, onAgentSelect })
 */
(function () {
  'use strict';

  var DEFAULT_GATEWAY = 'https://fapi.drdeeks.xyz';
  var LOADER_SCRIPT = document.currentScript;
  var activeInstances = 0;

  // ------------------------------------------------------------------
  // Asset resolution
  // ------------------------------------------------------------------
  // Static assets (react bundle, vanilla widget) are served as siblings of this
  // loader on the watch host. Prefer the loader's own origin/path so an embed on
  // a third-party page still resolves them correctly.
  function assetBase() {
    var src = LOADER_SCRIPT && LOADER_SCRIPT.src;
    if (src && src.indexOf('/tv-widget.js') >= 0) {
      return src.replace(/\/tv-widget\.js.*$/, '');
    }
    return window.location.origin;
  }

  function resolveContainer(container) {
    if (!container) return document.querySelector('#federation-tv');
    return typeof container === 'string' ? document.querySelector(container) : container;
  }

  // ------------------------------------------------------------------
  // Vanilla legacy engine loader (singleton)
  // ------------------------------------------------------------------
  var vanillaPromise = null;
  function loadVanilla() {
    if (window.FederationTVVanilla) return Promise.resolve(window.FederationTVVanilla);
    if (vanillaPromise) return vanillaPromise;
    vanillaPromise = new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = assetBase() + '/tv-widget-vanilla.js';
      s.onload = function () {
        if (window.FederationTVVanilla) resolve(window.FederationTVVanilla);
        else reject(new Error('[FederationTV] vanilla loaded but FederationTVVanilla missing'));
      };
      s.onerror = function () { reject(new Error('[FederationTV] failed to load vanilla widget')); };
      document.head.appendChild(s);
    });
    return vanillaPromise;
  }

  // ------------------------------------------------------------------
  // React OfficeStage loader
  // ------------------------------------------------------------------
  // Loads the self-mounting module bundle into rootEl. Resolves true when the
  // bundle produced DOM (mounted), false on load error / empty render.
  function mountReactStage(rootEl, gatewayUrl, projectId, roomId) {
    return new Promise(function (resolve) {
      rootEl.setAttribute('data-gateway', gatewayUrl);
      rootEl.setAttribute('data-project', projectId);
      if (roomId && roomId !== 'all') rootEl.setAttribute('data-room', roomId);
      else rootEl.removeAttribute('data-room');
      window.__federationOfficeStageMounted = false;

      var moduleUrl = assetBase() + '/react-dist/assets/office-stage.js';
      var s = document.createElement('script');
      // The bundle is an ES module (uses `export`); it must be loaded as a
      // module or it is a parse error and never self-mounts.
      s.type = 'module';
      s.src = moduleUrl;

      var settled = false;
      function done(ok) { if (!settled) { settled = true; resolve(ok); } }

      s.onerror = function () {
        console.warn('[FederationTV] React bundle failed to load:', moduleUrl);
        done(false);
      };
      s.onload = function () {
        // The module self-mounts synchronously on import; confirm on the next
        // tick that it actually rendered before committing to the React path.
        setTimeout(function () {
          done(!!window.__federationOfficeStageMounted && rootEl.childElementCount > 0);
        }, 250);
      };
      document.head.appendChild(s);

      // Safety net in case neither event fires (e.g. CSP-blocked module).
      setTimeout(function () { done(rootEl.childElementCount > 0); }, 4000);
    });
  }

  // ------------------------------------------------------------------
  // Data layer (React path): drives the roster + feed callbacks.
  // Mirrors the public API shapes the vanilla engine consumes so host pages
  // behave identically no matter which visual is live.
  // ------------------------------------------------------------------
  function startDataFeed(opts) {
    var gatewayUrl = opts.gatewayUrl || DEFAULT_GATEWAY;
    var projectId = opts.projectId || 'all';
    var roomId = opts.roomId || 'all';
    var interval = opts.refreshInterval || 15000;
    var timer = null;
    var stopped = false;

    function inRoom(agent) { return roomId === 'all' || agent.roomId === roomId; }

    function fetchAgents() {
      var url = projectId === 'all'
        ? gatewayUrl + '/api/projects'
        : gatewayUrl + '/api/projects/' + encodeURIComponent(projectId) + '/agents';
      return fetch(url).then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      }).then(function (data) {
        if (projectId === 'all') {
          var projects = Array.isArray(data) ? data : (data.projects || []);
          return Promise.all(projects.map(function (proj) {
            return fetch(gatewayUrl + '/api/projects/' + encodeURIComponent(proj.projectId) + '/agents')
              .then(function (r) { return r.ok ? r.json() : { agents: [] }; })
              .then(function (d) {
                return (d.agents || []).filter(inRoom).map(function (a) {
                  return Object.assign({}, a, { projectId: proj.projectId });
                });
              })
              .catch(function () { return []; });
          })).then(function (groups) {
            return groups.reduce(function (all, g) { return all.concat(g); }, []);
          });
        }
        return (data.agents || []).filter(inRoom).map(function (a) {
          return Object.assign({}, a, { projectId: projectId });
        });
      }).then(function (agents) {
        if (!stopped && opts.onAgentsUpdate) opts.onAgentsUpdate(agents);
      }).catch(function (e) {
        console.warn('[FederationTV] agent fetch failed:', e && e.message);
      });
    }

    function fetchFeed() {
      var url = projectId === 'all'
        ? gatewayUrl + '/api/feed?limit=20'
        : gatewayUrl + '/api/projects/' + encodeURIComponent(projectId) + '/feed?limit=20';
      return fetch(url).then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      }).then(function (data) {
        var events = Array.isArray(data) ? data : (data.events || data.feed || []);
        if (!stopped && opts.onFeedUpdate) opts.onFeedUpdate(events);
      }).catch(function (e) {
        console.warn('[FederationTV] feed fetch failed:', e && e.message);
      });
    }

    function tick() { if (!stopped) { fetchAgents(); fetchFeed(); } }
    tick();
    timer = setInterval(tick, interval);

    return {
      stop: function () { stopped = true; if (timer) clearInterval(timer); },
      setProject: function (nextProjectId, nextRoomId) {
        if (nextProjectId) projectId = nextProjectId;
        if (nextRoomId) roomId = nextRoomId;
        tick();
      }
    };
  }

  // ------------------------------------------------------------------
  // Public FederationTV controller
  // ------------------------------------------------------------------
  function FederationTV(opts) {
    if (!(this instanceof FederationTV)) return new FederationTV(opts);
    opts = opts || {};
    activeInstances++;

    var self = this;
    var container = resolveContainer(opts.container);
    var gatewayUrl = opts.gatewayUrl || DEFAULT_GATEWAY;
    var projectId = opts.projectId || 'all';
    var roomId = opts.roomId || 'all';

    // Vanilla internals some host/test pages read; kept defined so they never
    // throw before (or without) the fallback engine attaching.
    this.agents = new Map();
    this.speechLines = [];
    this.activeBubbles = new Map();

    this._dataFeed = null;
    this._vanilla = null;
    this._stopped = false;

    if (!container) {
      console.warn('[FederationTV] No container found for', opts.container);
      return;
    }

    function useVanilla() {
      loadVanilla().then(function (Vanilla) {
        if (self._stopped) return;
        self._vanilla = new Vanilla(Object.assign({}, opts, { container: container }));
        self.agents = self._vanilla.agents;
        self.speechLines = self._vanilla.speechLines;
        self.activeBubbles = self._vanilla.activeBubbles;
      }).catch(function (e) {
        console.error('[FederationTV] vanilla engine failed:', e && e.message);
        container.innerHTML =
          '<p style="padding:16px;font:13px system-ui;color:#d6b984;text-align:center">' +
          'Watchtower presentation is temporarily unavailable.</p>';
      });
    }

    // engine:'vanilla' — the host page wants the real-data legacy engine as the
    // PRIMARY presentation (e.g. the public Watchtower, which must render the
    // real registered roster and authoritative room scene, never the React
    // stage's fictional cast). Skip React entirely.
    if (opts.engine === 'vanilla') {
      useVanilla();
      return;
    }

    // React presentation mounts into a dedicated root so the fallback engine can
    // cleanly take over the container if needed.
    var rootEl = container.querySelector('#office-stage-root');
    if (!rootEl) {
      rootEl = document.createElement('div');
      rootEl.id = 'office-stage-root';
      container.appendChild(rootEl);
    }

    mountReactStage(rootEl, gatewayUrl, projectId, roomId).then(function (ok) {
      if (self._stopped) return;
      if (ok) {
        // React visual is live; run the lightweight data layer for callbacks.
        self._dataFeed = startDataFeed(opts);
        return;
      }
      // Fall back to the vanilla legacy widget for BOTH visual and data.
      console.warn('[FederationTV] React monitor unavailable — using vanilla fallback');
      useVanilla();
    });
  }

  FederationTV.prototype.setRoom = function (roomId, nextProjectId) {
    if (this._vanilla && typeof this._vanilla.setRoom === 'function') {
      this._vanilla.setRoom(roomId, nextProjectId);
    } else if (this._dataFeed) {
      // React diorama is ambient; the authoritative roster/feed follow the room.
      this._dataFeed.setProject(nextProjectId, roomId);
    }
  };

  FederationTV.prototype.stop = function () {
    this._stopped = true;
    if (this._dataFeed) this._dataFeed.stop();
    if (this._vanilla && typeof this._vanilla.stop === 'function') this._vanilla.stop();
  };

  // Expose (do not clobber a host page's own stub if one already exists).
  if (!window.FederationTV) window.FederationTV = FederationTV;

  // ------------------------------------------------------------------
  // Auto-mount for pages that only drop in the script tag + container
  // (e.g. demo.html) and never call `new FederationTV(...)`.
  // ------------------------------------------------------------------
  function autoMount() {
    if (activeInstances > 0) return; // host constructed its own instance
    var container = document.querySelector('#federation-tv');
    if (!container) return;
    var gatewayUrl = (LOADER_SCRIPT && LOADER_SCRIPT.getAttribute('data-gateway')) || DEFAULT_GATEWAY;
    var projectId = (LOADER_SCRIPT && LOADER_SCRIPT.getAttribute('data-project')) || 'autopilot';
    var roomId = (LOADER_SCRIPT && LOADER_SCRIPT.getAttribute('data-room')) || 'all';
    var containerSel = (LOADER_SCRIPT && LOADER_SCRIPT.getAttribute('data-container')) || '#federation-tv';
    new FederationTV({ gatewayUrl: gatewayUrl, projectId: projectId, roomId: roomId, container: containerSel });
  }

  // Defer so a following inline script that constructs FederationTV wins first.
  function scheduleAutoMount() { setTimeout(autoMount, 0); }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scheduleAutoMount);
  } else {
    scheduleAutoMount();
  }
})();
