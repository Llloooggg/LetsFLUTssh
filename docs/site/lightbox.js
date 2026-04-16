// Simple vanilla lightbox for screenshot previews.
// Click a .screenshot-clickable img to open; click overlay or Esc to close.
(() => {
  const lightbox = document.getElementById('lightbox');
  if (!lightbox) return;

  const lightboxImg = lightbox.querySelector('.lightbox-image');
  const closeBtn = lightbox.querySelector('.lightbox-close');
  let lastFocused = null;

  function open(src, alt) {
    lastFocused = document.activeElement;
    lightboxImg.src = src;
    lightboxImg.alt = alt || '';
    lightbox.hidden = false;
    lightbox.setAttribute('aria-hidden', 'false');
    document.body.style.overflow = 'hidden';
    closeBtn.focus();
  }

  function close() {
    lightbox.hidden = true;
    lightbox.setAttribute('aria-hidden', 'true');
    lightboxImg.src = '';
    document.body.style.overflow = '';
    if (lastFocused && typeof lastFocused.focus === 'function') {
      lastFocused.focus();
    }
  }

  document.querySelectorAll('.screenshot-clickable img').forEach((img) => {
    img.style.cursor = 'zoom-in';
    img.addEventListener('click', () => open(img.src, img.alt));
  });

  lightbox.addEventListener('click', (e) => {
    if (e.target === lightbox || e.target === lightboxImg || e.target === closeBtn) {
      close();
    }
  });

  document.addEventListener('keydown', (e) => {
    if (!lightbox.hidden && e.key === 'Escape') {
      close();
    }
  });
})();
