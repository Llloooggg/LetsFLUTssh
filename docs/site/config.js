/* ═══════════════════════════════════════════════════════════
 *  LetsFLUTssh docs site — configuration.
 *  owner/repo are auto-detected from the GitHub Pages URL.
 * ═══════════════════════════════════════════════════════════ */
var CONFIG = {
  logo: 'https://raw.githubusercontent.com/Llloooggg/LetsFLUTssh/main/assets/icons/icon.png',

  tagline: 'Lightweight cross-platform SSH/SFTP client with GUI',
  subtitle: 'Open-source alternative to Xshell and Termius',

  badges: function (B) {
    return [
      [
        B.release(),
        B.shields('platform', 'Windows | Linux | macOS | Android | iOS'),
        B.license(),
        B.bestPractices(12283),
      ],
      [
        B.workflow('ci'),
        B.workflow('cfl-fuzz'),
        B.workflow('build-release', { event: 'push' }),
      ],
      [
        B.workflow('osv'),
        B.workflow('codeql'),
        B.workflow('semgrep'),
      ],
      [
        B.sonar('security_rating'),
        B.sonar('reliability_rating'),
        B.sonar('coverage'),
        B.scorecard(),
      ],
    ];
  },

  screenshots: [
    { src: 'https://raw.githubusercontent.com/Llloooggg/LetsFLUTssh/main/docs/screenshots/LetsFLUTssh_terminal.png',
      caption: 'SSH Terminal — session tree, tabbed terminal with htop' },
    { src: 'https://raw.githubusercontent.com/Llloooggg/LetsFLUTssh/main/docs/screenshots/LetsFLUTssh_files.png',
      caption: 'SFTP File Browser — dual-pane local/remote with transfer panel' },
  ],

  footerMuted: 'GPL-3.0 · Built with Flutter · OneDark theme',
};
