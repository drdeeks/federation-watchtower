import { createElement } from 'react';
import { createRoot } from 'react-dom/client';
import OfficeStage from './OfficeStage';

// Self-mounting entry: the loader (tv-widget.js) creates a #office-stage-root
// element carrying data-gateway / data-project, then imports this bundle.
(function () {
  var container =
    document.getElementById('office-stage-root') ||
    document.querySelector('[data-office-stage]');
  if (!container) return;

  var gatewayUrl = container.getAttribute('data-gateway') || 'https://fapi.drdeeks.xyz';
  var projectId = container.getAttribute('data-project') || 'autopilot';
  var roomId = container.getAttribute('data-room') || undefined;

  // OfficeStage is a React function component. It MUST be handed to React via
  // createElement so its hooks run inside the render phase — calling
  // OfficeStage() directly throws "Invalid hook call" and mounts nothing,
  // which is what previously broke the React monitor.
  var root = createRoot(container);
  function renderStage(nextProjectId: string, nextRoomId: string | undefined) {
    root.render(createElement(OfficeStage, { gatewayUrl: gatewayUrl, projectId: nextProjectId, roomId: nextRoomId }));
  }
  renderStage(projectId, roomId);

  (window as any).__federationTVRoot = root;
  // Signal to the loader that the React monitor mounted, so it does not fall
  // back to the vanilla legacy widget.
  (window as any).__federationOfficeStageMounted = true;
  // The loader (tv-widget.js) calls this on a room switch instead of remounting
  // the module (ES modules are cached by URL, so a fresh <script> tag would not
  // re-run this IIFE) — without it the diorama kept showing whatever roster it
  // mounted with while the roster/count panels moved on to the newly selected
  // room, which is what produced a mismatched agent count next to the camera.
  (window as any).__federationOfficeStageSetRoom = function (nextProjectId: string, nextRoomId: string | undefined) {
    renderStage(nextProjectId, nextRoomId);
  };
})();
