// Fetches README from main, renders to HTML, strips the hero section
// (already shown in the page header).
(async () => {
  const url = 'https://raw.githubusercontent.com/Llloooggg/LetsFLUTssh/main/README.md';
  const target = document.getElementById('readme-content');

  try {
    const res = await fetch(url, { cache: 'no-cache' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    let md = await res.text();

    // Strip the title (first H1) since the page already has it.
    md = md.replace(/^#\s+LetsFLUTssh\s*$/m, '');

    // Strip the leading badge block (everything before the first H2).
    const h2Match = md.match(/^##\s+/m);
    if (h2Match) {
      md = md.slice(h2Match.index);
    }

    // Strip the screenshot images (already shown above).
    md = md.replace(/^!\[.*?screenshot.*?\]\(.*?\)\s*$/gim, '');
    md = md.replace(/^!\[SSH Terminal.*?\]\(.*?\)\s*$/gim, '');
    md = md.replace(/^!\[SFTP File Browser.*?\]\(.*?\)\s*$/gim, '');

    // Configure marked: GFM, breaks
    marked.setOptions({
      gfm: true,
      breaks: false,
      headerIds: true,
      mangle: false,
    });

    target.innerHTML = marked.parse(md);

    // Make external links open in new tab.
    target.querySelectorAll('a[href^="http"]').forEach(a => {
      a.target = '_blank';
      a.rel = 'noopener';
    });
  } catch (e) {
    target.innerHTML = `<p class="loading">Failed to load README: ${e.message}.<br>See it on <a href="https://github.com/Llloooggg/LetsFLUTssh#readme">GitHub</a>.</p>`;
  }
})();
