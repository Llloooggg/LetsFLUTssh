/* ═══════════════════════════════════════════════════════════
 *  Project site renderer.
 *
 *  - Auto-detects owner/repo from the page URL
 *  - Fetches repo metadata from GitHub API
 *  - Renders hero, screenshots (from CONFIG), README
 *  - Latest release drives the Download button
 * ═══════════════════════════════════════════════════════════ */
(function () {
  var cfg = (typeof CONFIG !== 'undefined') ? CONFIG : {};

  /* ── Resolve owner/repo ─────────────────────────────── */
  var owner = cfg.owner;
  var repo = cfg.repo;

  if (!owner || !repo) {
    /* GitHub Pages serves at either:
     *   https://{owner}.github.io/{repo}/...   ← project page
     *   https://{owner}.github.io/...          ← user/org page */
    var host = window.location.hostname.match(/^([^.]+)\.github\.io$/i);
    if (host) {
      owner = owner || host[1];
      var parts = window.location.pathname.split('/').filter(Boolean);
      if (parts.length > 0 && parts[0] !== 'index.html') {
        repo = repo || parts[0];
      }
    }
  }

  if (!owner || !repo) {
    document.getElementById('hero-title').textContent = 'Configuration required';
    document.getElementById('readme-content').innerHTML =
      '<p class="loading">Could not detect repository from URL. ' +
      'Set <code>owner</code> and <code>repo</code> in <code>config.js</code>.</p>';
    return;
  }

  var repoUrl = 'https://github.com/' + owner + '/' + repo;
  var rawBase = 'https://raw.githubusercontent.com/' + owner + '/' + repo + '/main/';

  /* ── Helpers ────────────────────────────────────────── */
  function esc(s) {
    var el = document.createElement('span');
    el.textContent = s;
    return el.innerHTML;
  }

  /* ── Main ───────────────────────────────────────────── */
  (async function () {
    var repoData = null;
    var release = null;

    /* Kick off all API discoveries in parallel.
     * Auto-detect fills in anything the user didn't configure. */
    var apiCalls = [
      fetch('https://api.github.com/repos/' + owner + '/' + repo),
      fetch('https://api.github.com/repos/' + owner + '/' + repo + '/releases/latest')
        .catch(function () { return null; }),
      (cfg.logo ? Promise.resolve(cfg.logo) : autoDetectLogo()),
      (cfg.screenshots ? Promise.resolve(cfg.screenshots) : autoDetectScreenshots()),
      (cfg.badges ? Promise.resolve(null) : autoDetectWorkflows()),
    ];

    var results;
    try { results = await Promise.all(apiCalls); }
    catch (e) { results = [null, null, null, null, null]; }

    if (results[0] && results[0].ok) repoData = await results[0].json();
    if (results[1] && results[1].ok) release = await results[1].json();

    /* Canonicalize owner/repo from the API response.
     * GitHub accepts case-insensitive slugs on its own endpoints,
     * but third-party services pinned to shields.io / scorecard.dev /
     * sonarcloud.io index under the exact case that was registered —
     * e.g. SonarCloud's project id is "Llloooggg_LetsFLUTssh", not
     * "llloooggg_LetsFLUTssh". Use whatever case the API returns. */
    if (repoData) {
      if (repoData.owner && repoData.owner.login) owner = repoData.owner.login;
      if (repoData.name) repo = repoData.name;
      repoUrl = 'https://github.com/' + owner + '/' + repo;
      rawBase = 'https://raw.githubusercontent.com/' + owner + '/' + repo + '/main/';
    }

    var detectedLogo = results[2];
    var detectedScreenshots = results[3] || [];
    var detectedWorkflows = results[4] || [];

    renderHero(repoData, release, detectedLogo, detectedWorkflows);
    renderScreenshots(detectedScreenshots);
    renderReadme(repoData);
    renderFooter(repoData);
  })();

  /* ── Auto-detect helpers ────────────────────────────── */
  async function autoDetectLogo() {
    var paths = [
      'assets/icons/icon.png',
      'assets/icon.png',
      'assets/logo.png',
      'icon.png',
      'logo.png',
    ];
    for (var i = 0; i < paths.length; i++) {
      try {
        var res = await fetch(rawBase + paths[i], { method: 'HEAD' });
        if (res.ok) return rawBase + paths[i];
      } catch (e) { /* try next */ }
    }
    return null;
  }

  async function autoDetectScreenshots() {
    var dirs = ['docs/screenshots', 'docs/images', 'screenshots'];
    for (var i = 0; i < dirs.length; i++) {
      try {
        var res = await fetch('https://api.github.com/repos/'
          + owner + '/' + repo + '/contents/' + dirs[i]);
        if (!res.ok) continue;
        var files = await res.json();
        if (!Array.isArray(files)) continue;
        var images = files
          .filter(function (f) { return /\.(png|jpe?g|gif|webp)$/i.test(f.name); })
          .map(function (f) {
            return {
              src: rawBase + dirs[i] + '/' + f.name,
              caption: f.name.replace(/\.[^.]+$/, '').replace(/[_-]/g, ' '),
            };
          });
        if (images.length > 0) return images;
      } catch (e) { /* try next */ }
    }
    return [];
  }

  async function autoDetectWorkflows() {
    try {
      var res = await fetch('https://api.github.com/repos/'
        + owner + '/' + repo + '/contents/.github/workflows');
      if (!res.ok) return [];
      var files = await res.json();
      if (!Array.isArray(files)) return [];
      return files
        .filter(function (f) { return /\.ya?ml$/i.test(f.name); })
        .map(function (f) { return f.name.replace(/\.ya?ml$/i, ''); });
    } catch (e) { return []; }
  }

  /* ── Hero ───────────────────────────────────────────── */
  function renderHero(repoData, release, detectedLogo, detectedWorkflows) {
    var name = repoData ? repoData.name : repo;
    var tagline = cfg.tagline || (repoData && repoData.description) || '';

    /* Tab title */
    document.title = name + (tagline ? ' — ' + tagline : '');

    /* OG tags */
    setMeta('og:title', name);
    if (tagline) setMeta('og:description', tagline);
    setMeta('description', tagline);

    /* Title + logo (cfg override, else auto-detected) */
    var titleEl = document.getElementById('hero-title');
    titleEl.textContent = name;
    titleEl.classList.remove('hero-title-skeleton');
    var logo = cfg.logo || detectedLogo;
    if (logo) {
      var logoEl = document.getElementById('hero-logo');
      logoEl.alt = name + ' logo';
      /* Only reveal once the image has actually loaded — avoids a
       * flash of broken-image icon between src-set and load. */
      logoEl.onload = function () { logoEl.style.display = ''; };
      logoEl.src = logo;
      /* Favicon */
      var fav = document.createElement('link');
      fav.rel = 'icon';
      fav.href = logo;
      document.head.appendChild(fav);
    }

    /* Tagline & subtitle */
    if (tagline) {
      var tl = document.getElementById('hero-tagline');
      tl.textContent = tagline;
      tl.style.display = '';
    }
    if (cfg.subtitle) {
      var st = document.getElementById('hero-subtitle');
      st.textContent = cfg.subtitle;
      st.style.display = '';
    }

    /* Badges — three forms (in order of precedence):
     *   1. Flat array of objects [{alt,img,link}, ...]             → one row
     *   2. Array of arrays [[{...},{...}], [{...}]]                → multiple rows
     *   3. Function (B) => [[B.release(), ...], [...]]             → use builders
     *
     * If nothing is configured and the repo has workflows or a release,
     * the template auto-generates a sensible default:
     *   Row 1: [Release, License]
     *   Row 2: [<every workflow in .github/workflows/>]
     */
    var B = buildBadgeBuilders(repoData, release);

    var badgeSource;
    if (typeof cfg.badges === 'function') {
      badgeSource = cfg.badges(B);
    } else if (cfg.badges) {
      badgeSource = cfg.badges;
    } else {
      /* Auto-default */
      badgeSource = [];
      var topRow = [B.release(), B.license()].filter(Boolean);
      if (topRow.length > 0) badgeSource.push(topRow);
      if (detectedWorkflows && detectedWorkflows.length > 0) {
        badgeSource.push(detectedWorkflows.map(function (w) { return B.workflow(w); }));
      }
    }

    if (badgeSource && badgeSource.length > 0) {
      var rows = Array.isArray(badgeSource[0]) ? badgeSource : [badgeSource];
      var badges = document.getElementById('hero-badges');
      badges.innerHTML = rows.map(function (row) {
        return '<div class="badge-row">' + row.filter(Boolean).map(function (b) {
          var img = '<img src="' + esc(b.img) + '" alt="' + esc(b.alt || '')
            + '" onload="this.classList.add(\'loaded\')">';
          return b.link
            ? '<a href="' + esc(b.link) + '" target="_blank" rel="noopener">' + img + '</a>'
            : img;
        }).join('') + '</div>';
      }).join('');
      badges.style.display = '';
    }

    /* CTA buttons */
    var ctaHtml = '';
    if (release && release.html_url) {
      ctaHtml += '<a href="' + esc(release.html_url) + '" class="btn btn-primary">'
        + '<span class="icon">&darr;</span> Download</a>';
    }
    ctaHtml += '<a href="' + esc(repoUrl) + '" class="btn '
      + (release ? 'btn-secondary' : 'btn-primary') + '" target="_blank" rel="noopener">'
      + '<span class="icon">&#9881;</span> View on GitHub</a>';
    if (cfg.extraCta) {
      cfg.extraCta.forEach(function (c) {
        ctaHtml += '<a href="' + esc(c.url) + '" class="btn '
          + (c.primary ? 'btn-primary' : 'btn-secondary') + '" target="_blank" rel="noopener">'
          + esc(c.label) + '</a>';
      });
    }
    if (release && release.tag_name) {
      ctaHtml += '<div class="release-tag-row">'
        + '<a href="' + esc(release.html_url)
        + '" class="release-tag" target="_blank" rel="noopener">'
        + '&#9660; ' + esc(release.tag_name) + '</a>'
        + '</div>';
    }
    document.getElementById('hero-cta').innerHTML = ctaHtml;
  }

  /* ── Screenshots ─────────────────────────────────────── */
  function renderScreenshots(detectedScreenshots) {
    var shots = cfg.screenshots || detectedScreenshots || [];
    if (shots.length === 0) return;

    document.getElementById('screenshots-section').style.display = '';
    document.getElementById('screenshot-grid').innerHTML = shots.map(function (s) {
      return '<figure class="screenshot-clickable">'
        + '<img src="' + esc(s.src) + '" alt="' + esc(s.caption || 'Screenshot')
        + '" onload="this.classList.add(\'loaded\')">'
        + (s.caption ? '<figcaption>' + esc(s.caption) + '</figcaption>' : '')
        + '</figure>';
    }).join('');
  }

  /* ── README ──────────────────────────────────────────── */
  async function renderReadme(repoData) {
    var target = document.getElementById('readme-content');
    try {
      var res = await fetch(rawBase + 'README.md', { cache: 'no-cache' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      var md = await res.text();

      /* Strip the first H1 (repo name — already shown in hero) */
      md = md.replace(/^#\s+.+$/m, '');

      /* Everything before the first H2 is preamble. Keep only blockquote
       * blocks (e.g. "> Disclaimer: …") so notices survive; drop badges,
       * tagline paragraphs, and inline screenshots — those already live
       * in the hero and the screenshots section. */
      var h2Idx = md.search(/^##\s+/m);
      if (h2Idx !== -1) {
        var head = md.slice(0, h2Idx);
        var rest = md.slice(h2Idx);
        var kept = head.split(/\n\s*\n/).filter(function (b) {
          return /^\s*>/m.test(b);
        });
        md = (kept.length ? kept.join('\n\n') + '\n\n' : '') + rest;
      }

      /* Strip screenshot images already shown in the screenshots section */
      if (cfg.screenshots && cfg.screenshots.length > 0) {
        md = md.replace(/^!\[.*?\]\(.*?\)\s*$/gim, '');
      }

      marked.setOptions({ gfm: true, breaks: false, headerIds: true, mangle: false });
      target.innerHTML = marked.parse(md);

      /* Rewrite relative links and images to absolute GitHub URLs */
      var blobBase = 'https://github.com/' + owner + '/' + repo + '/blob/main/';
      target.querySelectorAll('a[href]').forEach(function (a) {
        var href = a.getAttribute('href');
        if (!href) return;
        if (href.startsWith('http') || href.startsWith('#') || href.startsWith('mailto:')) return;
        a.setAttribute('href', blobBase + href);
      });
      target.querySelectorAll('img[src]').forEach(function (img) {
        var src = img.getAttribute('src');
        if (!src || src.startsWith('http') || src.startsWith('data:')) return;
        img.setAttribute('src', rawBase + src);
      });
      target.querySelectorAll('a[href^="http"]').forEach(function (a) {
        a.target = '_blank';
        a.rel = 'noopener';
      });
    } catch (e) {
      target.innerHTML = '<p class="loading">Failed to load README: ' + esc(e.message)
        + '.<br>See it on <a href="' + esc(repoUrl) + '#readme">GitHub</a>.</p>';
    }
  }

  /* ── Footer ──────────────────────────────────────────── */
  function renderFooter(repoData) {
    var userSite = 'https://' + owner.toLowerCase() + '.github.io';
    document.getElementById('footer-links').innerHTML =
      '<a href="' + esc(repoUrl) + '">GitHub</a>'
      + '<span class="sep">&middot;</span>'
      + '<a href="' + esc(repoUrl) + '/issues">Issues</a>'
      + '<span class="sep">&middot;</span>'
      + '<a href="' + esc(repoUrl) + '/releases">Releases</a>'
      + '<span class="sep">&middot;</span>'
      + '<a href="' + esc(userSite) + '">All Projects</a>';

    /* Muted line: custom override, or auto-composed from license + theme */
    var muted = document.querySelector('footer .muted');
    if (!muted) return;
    if (cfg.footerMuted) {
      muted.textContent = cfg.footerMuted;
    } else if (repoData && repoData.license && repoData.license.spdx_id
               && repoData.license.spdx_id !== 'NOASSERTION') {
      muted.textContent = repoData.license.spdx_id + ' · OneDark theme';
    }
  }

  function setMeta(name, content) {
    var attr = name.startsWith('og:') ? 'property' : 'name';
    var el = document.querySelector('meta[' + attr + '="' + name + '"]');
    if (!el) {
      el = document.createElement('meta');
      el.setAttribute(attr, name);
      document.head.appendChild(el);
    }
    el.setAttribute('content', content);
  }

  /* ═══════════════════════════════════════════════════════════
   *  Badge builders — used when CONFIG.badges is a function.
   *  Each helper returns {alt, img, link} ready for rendering,
   *  or null (filtered out) when the data isn't available.
   * ═══════════════════════════════════════════════════════════ */
  function buildBadgeBuilders(repoData, release) {
    /* shields.io text escaping: '-' → '--', '_' → '__', space → '%20' */
    function shieldsEsc(s) {
      return String(s)
        .replace(/-/g, '--')
        .replace(/_/g, '__')
        .replace(/ /g, '%20');
    }

    return {
      /* Release — returns null when the repo has no releases */
      release: function () {
        if (!release) return null;
        return {
          alt: 'Release',
          img: 'https://img.shields.io/github/v/release/' + owner + '/' + repo + '?include_prereleases',
          link: repoUrl + '/releases',
        };
      },

      /* License — auto-reads SPDX from repo API; override with arg */
      license: function (spdxOverride) {
        var spdx = spdxOverride
          || (repoData && repoData.license && repoData.license.spdx_id);
        if (!spdx || spdx === 'NOASSERTION') return null;
        return {
          alt: 'License: ' + spdx,
          img: 'https://img.shields.io/badge/License-' + shieldsEsc(spdx) + '-blue.svg',
          link: repoUrl + '/blob/main/LICENSE',
        };
      },

      /* Generic static shields.io badge */
      shields: function (label, message, color, link) {
        return {
          alt: label,
          img: 'https://img.shields.io/badge/' + shieldsEsc(label)
            + '-' + shieldsEsc(message) + '-' + (color || 'blue'),
          link: link || repoUrl,
        };
      },

      /* GitHub Actions workflow badge — file name without .yml
       * opts: { event: 'push' } to filter to a specific trigger */
      workflow: function (name, opts) {
        var qs = '';
        if (opts && opts.event) qs = '?event=' + encodeURIComponent(opts.event);
        return {
          alt: name,
          img: 'https://github.com/' + owner + '/' + repo
            + '/actions/workflows/' + name + '.yml/badge.svg' + qs,
          link: 'https://github.com/' + owner + '/' + repo
            + '/actions/workflows/' + name + '.yml',
        };
      },

      /* OpenSSF Best Practices — id is the project ID from bestpractices.dev */
      bestPractices: function (id) {
        return {
          alt: 'OpenSSF Best Practices',
          img: 'https://www.bestpractices.dev/projects/' + id + '/badge',
          link: 'https://www.bestpractices.dev/projects/' + id,
        };
      },

      /* SonarCloud metric. Project id defaults to "owner_repo"
       * (SonarCloud default for GitHub-imported projects). */
      sonar: function (metric, projectOverride) {
        var project = projectOverride || (owner + '_' + repo);
        var metricLabel = metric.replace(/_/g, ' ')
          .replace(/\b\w/g, function (c) { return c.toUpperCase(); });
        return {
          alt: 'SonarCloud ' + metricLabel,
          img: 'https://sonarcloud.io/api/project_badges/measure?project='
            + encodeURIComponent(project) + '&metric=' + encodeURIComponent(metric),
          link: 'https://sonarcloud.io/summary/new_code?id=' + encodeURIComponent(project),
        };
      },

      /* OpenSSF Scorecard — auto from repo URL */
      scorecard: function () {
        var slug = 'github.com/' + owner + '/' + repo;
        return {
          alt: 'OpenSSF Scorecard',
          img: 'https://api.scorecard.dev/projects/' + slug + '/badge',
          link: 'https://scorecard.dev/viewer/?uri=' + slug,
        };
      },

      /* Escape hatch — full manual control */
      custom: function (opts) {
        return {
          alt: opts.alt || '',
          img: opts.img,
          link: opts.link || repoUrl,
        };
      },
    };
  }
})();
