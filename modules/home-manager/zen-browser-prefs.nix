// Zen-specific preferences
user_pref("zen.theme.sidebar", "auto");
user_pref("zen.view.compact", true);
user_pref("zen.workspaces.vertical", true);
// DNS: treat single-word inputs (e.g. "sentry.lan") as navigations, not searches
user_pref("browser.fixup.dns_first_for_single_words", true);
// Dark mode - signal to websites that system prefers dark mode
// This enables native dark themes on supporting websites via CSS prefers-color-scheme
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("browser.in-content.dark-mode", true);
user_pref("layout.css.prefers-color-scheme.content-override", 2); // 2 = dark
// Zen theme mode - follow system dark/light preference
user_pref("zen.theme.mode", "system");
// Performance optimizations
user_pref("gfx.webrender.all", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
// TESTING: Re-enabled widget.dmabuf.force-enabled to test if NVIDIA + Wayland issues are resolved
// If WebGL/Canvas corruption occurs (e.g., Facebook Messenger), comment this out again
user_pref("widget.dmabuf.force-enabled", true);
// Privacy enhancements - ENABLED for normal browsing
user_pref("privacy.resistFingerprinting", false);  // Disabled - breaks banking
user_pref("network.http.referer.spoofSource", false);  // Disabled - breaks banking
user_pref("privacy.trackingprotection.enabled", true);  // ENABLED - normal security
// HTTPS-only mode - always use secure connections
user_pref("dom.security.https_only_mode", true);
user_pref("dom.security.https_only_mode_ever_enabled", true);
user_pref("dom.security.https_only_mode_send_http_background_request", false);
// Load OS root certificates (cluster CA for *.lan domains)
user_pref("security.enterprise_roots.enabled", true);
// Cookie behavior - BALANCED for normal use
// 0 = Allow all cookies
// 1 = Block third-party cookies
// 4 = Block third-party trackers
// 5 = Isolate all cookies (Firefox default)
user_pref("network.cookie.cookieBehavior", 5);  // Isolate all cookies - SECURE DEFAULT
// Network partitioning - ENABLED for privacy
user_pref("privacy.partition.network_state", true);
user_pref("privacy.partition.serviceWorkers", true);
// Referer headers - PRIVACY-RESPECTING DEFAULTS
user_pref("network.http.sendRefererHeader", 2);  // Send full URL (needed for banking)
user_pref("network.http.referer.trimmingPolicy", 2);  // Trim to origin (privacy)
user_pref("network.http.referer.XOriginPolicy", 1);  // Send full to same origin (privacy)
// Popup blocking - ENABLED for normal browsing
user_pref("dom.disable_open_during_load", true);  // Block unwanted popups
user_pref("privacy.popups.showBrowserMessage", true);  // Show when blocked
// Cross-origin opener policy - ENABLED for security
user_pref("dom.security.skip_cross_origin_opener_policy", false);
// SameSite cookie protection - ENABLED for security
user_pref("network.cookie.sameSite.laxByDefault", true);
user_pref("network.cookie.sameSite.noneRequiresSecure", true);
// State partitioning - ENABLED for privacy
user_pref("privacy.partition.always_partition_third_party_non_cookie_storage", true);
user_pref("privacy.partition.network_state.ocsp", true);
user_pref("privacy.partition.dynamic_pnames", true);
// CSP (Content Security Policy) - ENABLED for security
user_pref("security.csp.enable", true);
// OCSP/CRL checks - ENABLED for security
user_pref("security.OCSP.enabled", 1);
user_pref("security.CRL.enable", true);
// Enhanced Tracking Protection - ENABLED for normal browsing
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.pbmode.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
// =====================================================================
// SITE-SPECIFIC EXCEPTIONS FOR BANKING (CRA/Interac/RBC only)
// =====================================================================
// User-Agent spoofing ONLY for banking domains (avoids Linux detection)
user_pref("general.useragent.override.interac.ca", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0");
user_pref("general.useragent.override.sign-in.service.canada.ca", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0");
user_pref("general.useragent.override.securekey.com", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0");
user_pref("general.useragent.override.cra-agrc.gc.ca", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0");
user_pref("general.useragent.override.myaccount.rcbank.com", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0");
user_pref("general.useragent.override.www.cra.gc.ca", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0");
// Site-specific popup permissions for banking domains
// These allow popups ONLY from CRA/Interac/RBC, not globally
user_pref("permissions.default.popup", 2);  // Block popups globally (secure default)
// Allow popups from specific banking domains (whitelist approach)
user_pref("capability.policy.popup.Window.open", "allAccess");
user_pref("capability.policy.popup.sites", "https://cra.gc.ca https://www.cra.gc.ca https://sign-in.service.canada.ca https://interac.ca https://securekey.com https://myaccount.rcbank.com");
// Allow cookies for banking SAML flow across domains
user_pref("network.cookie.sameSite.schemes", "http,https");  // Allow cross-site for banking
// GPU acceleration for AI/ML web apps
user_pref("gfx.webrender.compositor", true);
user_pref("layers.gpu-process.enabled", true);
user_pref("media.hardware-video-decoding.enabled", true);
// Increase cache for large web apps
user_pref("browser.cache.disk.capacity", 1048576);  // 1GB
user_pref("browser.cache.memory.capacity", 65536);   // 64MB
// Tab grouping - auto-group by domain
user_pref("zen.tab.grouping.enabled", true);
// Web activity tracking - see time spent per site
user_pref("zen.web-activity.enabled", true);
user_pref("zen.web-activity.show-in-sidebar", true);
// Banking site exceptions - relax privacy for financial institutions
// NOTE: These preferences work globally. For per-site exceptions, use:
// 1. NoScript extension: Click NoScript icon → Options → Per-site permissions
// 2. uBlock Origin: Click uBlock icon → Disable on this site
// 3. Privacy Badger: Click PB icon → Disable for this site
// Alternative: Use the Banking container (id=8) which has relaxed settings
// Open banking sites in Banking workspace → they get container-level exceptions
// For automatic per-site exceptions, Firefox doesn't support domain-specific
// fingerprinting exemptions via prefs. Use extensions' UI or:
// 1. Click NoScript icon → Trust rbcroyalbank.com
// 2. Click uBlock icon → Turn off for www1.royalbank.com
// 3. Click Privacy Badger → Allow for rbcroyalbank.com
// Temporary workaround: Create a Banking profile/container with relaxed settings
// The Banking workspace (container 8) is designed for this purpose
