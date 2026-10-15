import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

mermaid.initialize({
  startOnLoad: false,
  theme: 'neutral',
  securityLevel: 'loose',
});

function renderMermaid() {
  document.querySelectorAll('pre code.language-mermaid').forEach((code, i) => {
    const pre = code.parentElement;
    const source = code.textContent.trim();
    if (!source) return;
    mermaid
      .render(`mermaid-${i}-${Math.random().toString(36).slice(2)}`, source)
      .then(({ svg }) => {
        const wrapper = document.createElement('div');
        wrapper.className = 'mermaid';
        wrapper.innerHTML = svg;
        pre.replaceWith(wrapper);
      })
      .catch((err) => console.error('Mermaid render failed:', err));
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', renderMermaid);
} else {
  renderMermaid();
}
