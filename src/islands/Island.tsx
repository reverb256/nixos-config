import { StrictMode, useEffect, useRef, useState, type ComponentType } from 'react';

/*
 * Module-level Landing promise cache.
 *
 * Astro's `client:only="react"` directive on the parent <Island /> already
 * dynamic-imports this file at the framework level. Without a cached promise,
 * React 19 StrictMode dev double-mount would schedule a SECOND inner
 * `import('./pages/Landing')`, producing two `setLanding()` calls and a
 * brief double-render. The static `let` below survives the
 * mount -> cleanup -> re-mount cycle so the resolver fires exactly once
 * per page lifetime. Falls back gracefully if the import rejects.
 */
let landingPromise: Promise<{ default: ComponentType }> | null = null;
function loadLanding() {
  if (!landingPromise) {
    landingPromise = import('./pages/Landing');
  }
  return landingPromise;
}

function IslandInner() {
  const [Landing, setLanding] = useState<ComponentType | null>(null);
  const cancelledRef = useRef(false);

  useEffect(() => {
    cancelledRef.current = false;
    loadLanding()
      .then((m) => {
        if (!cancelledRef.current) setLanding(() => m.default);
      })
      .catch((e) => {
        // eslint-disable-next-line no-console
        console.error('[astro-port] load failed:', e);
      });
    return () => {
      cancelledRef.current = true;
    };
  }, []);

  if (!Landing) {
    /*
     * No `min-h-screen` — canonical Landing.tsx hero height is variable,
     * and forcing 100vh here caused a visible page-height snap on hydration.
     * `py-32` padding + flex centering keeps the brand-word in view without
     * jarring layout shift when <Landing /> swaps in.
     *
     * `aria-busy="true"` (not `aria-live`) — sub-300ms transitions don't
     * reliably trigger screen-reader announcements; busy is the canonical
     * affordance for an in-flight async region.
     */
    return (
      <div
        className="flex items-center justify-center py-32 label-cap text-muted-foreground font-mono-num"
        role="status"
        aria-busy="true"
      >
        <span className="animate-pulse">loading</span>
      </div>
    );
  }
  return <Landing />;
}

export default function Island() {
  return (
    <StrictMode>
      <IslandInner />
    </StrictMode>
  );
}
