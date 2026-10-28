// Paperclip landing page. One place to configure: the repository slug.
// Everything else (release links, version, DMG asset) is derived from it.
const REPO = "mhadikz/Paperclip";
const FALLBACK_VERSION = "1.3.0";

const repoURL = `https://github.com/${REPO}`;
const releasesURL = `${repoURL}/releases`;
const latestURL = `${releasesURL}/latest`;

// --- Links -----------------------------------------------------------------
for (const a of document.querySelectorAll("[data-repo-link]")) {
  const kind = a.getAttribute("data-repo-link");
  a.href = kind === "issues" ? `${repoURL}/issues` : kind === "releases" ? releasesURL : repoURL;
}
for (const a of document.querySelectorAll("[data-doc]")) {
  a.href = `${repoURL}/blob/main/${a.getAttribute("data-doc")}`;
}
for (const el of document.querySelectorAll("[data-clone-url]")) {
  el.textContent = `${repoURL}.git`;
}
// Stable GitHub URL for the newest release's DMG; upgraded below to the exact asset when the API answers.
for (const id of ["download", "download-inline"]) {
  const a = document.getElementById(id);
  if (a) a.href = `${latestURL}/download/Paperclip-${FALLBACK_VERSION}.dmg`;
}

// --- Latest release (best effort; the page is complete without it) ----------
async function loadRelease() {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!res.ok) return;
    const release = await res.json();
    const dmg = (release.assets || []).find((a) => a.name.endsWith(".dmg"));
    const version = (release.tag_name || "").replace(/^v/, "") || FALLBACK_VERSION;
    const meta = document.getElementById("release-meta");
    if (meta) {
      const size = dmg ? ` · ${(dmg.size / 1048576).toFixed(1)} MB` : "";
      meta.textContent = `Version ${version} · Universal (Apple Silicon & Intel) · DMG${size}`;
    }
    if (dmg) {
      for (const id of ["download", "download-inline"]) {
        const a = document.getElementById(id);
        if (a) a.href = dmg.browser_download_url;
      }
    }
  } catch {
    // Offline or rate-limited: links already point at the releases page.
  }
}
loadRelease();

// --- Appearance toggle (per-viewer convenience) -----------------------------
const root = document.documentElement;
const toggle = document.getElementById("theme");
function storedTheme() {
  try { return localStorage.getItem("paperclip-theme"); } catch { return null; }
}
function currentlyDark() {
  const explicit = root.getAttribute("data-theme");
  if (explicit) return explicit === "dark";
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}
const saved = storedTheme();
if (saved === "dark" || saved === "light") root.setAttribute("data-theme", saved);
if (toggle) {
  toggle.addEventListener("click", () => {
    const next = currentlyDark() ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("paperclip-theme", next); } catch { /* private mode */ }
  });
}
