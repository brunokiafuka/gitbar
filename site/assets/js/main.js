// Install tab switcher
const tabs = document.querySelectorAll('.install-tab');
const cmd = document.getElementById('install-cmd');
const tabCmds = {
  brew: 'brew tap brunokiafuka/gitbar https://github.com/brunokiafuka/gitbar && brew install gitbar',
  source: 'git clone https://github.com/brunokiafuka/gitbar.git && cd gitbar && ./install',
  sh: 'curl -fsSL https://raw.githubusercontent.com/brunokiafuka/gitbar/main/install | bash',
};
tabs.forEach((t) =>
  t.addEventListener('click', () => {
    tabs.forEach((x) => x.classList.remove('active'));
    t.classList.add('active');
    if (cmd) cmd.textContent = tabCmds[t.dataset.tab];
  }),
);

// Scroll-triggered reveal
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
if ('IntersectionObserver' in window && !reduceMotion) {
  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      }
    },
    { rootMargin: '0px 0px -10% 0px', threshold: 0.05 },
  );
  document.querySelectorAll('.reveal').forEach((el) => io.observe(el));
} else {
  document.querySelectorAll('.reveal').forEach((el) => el.classList.add('in'));
}

// Copy buttons
document.querySelectorAll('.copy-btn').forEach((btn) => {
  btn.addEventListener('click', async () => {
    const target = btn.dataset.copy
      ? btn.dataset.copy
      : btn.parentElement.querySelector('code').textContent;
    try {
      await navigator.clipboard.writeText(target);
      const orig = btn.textContent;
      btn.textContent = 'copied ✓';
      btn.classList.add('done');
      setTimeout(() => {
        btn.textContent = orig;
        btn.classList.remove('done');
      }, 1400);
    } catch (e) {
      btn.textContent = 'press ⌘C';
    }
  });
});
