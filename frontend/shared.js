// shared.js — sidebar, auth guard, common utilities

const NAV_ITEMS = [
  { label: 'Dashboard',   href: 'dashboard.html',    icon: '📊', section: 'OVERVIEW' },
  { label: 'AI Agent',    href: 'agent.html',         icon: '🤖', section: 'OVERVIEW' },
  { label: 'Azure VMs',   href: 'azure.html',         icon: '🔵', section: 'CLOUD' },
  { label: 'AWS EC2',     href: 'aws.html',           icon: '🟠', section: 'CLOUD' },
  { label: 'Docker',      href: 'docker.html',        icon: '🐳', section: 'COMPUTE' },
  { label: 'Kubernetes',  href: 'kubernetes.html',    icon: '☸️',  section: 'COMPUTE' },
  { label: 'Terraform',   href: 'terraform.html',     icon: '🏗️',  section: 'IaC' },
  { label: 'Activity Log',href: 'activity.html',      icon: '📋', section: 'OPS' },
];

function buildSidebar(activeHref) {
  const currentUser = JSON.parse(sessionStorage.getItem('currentUser') || '{}');
  let sections = [];
  let lastSection = null;
  let html = '';

  for (const item of NAV_ITEMS) {
    if (item.section !== lastSection) {
      if (lastSection !== null) html += '</div>';
      html += `<div class="nav-section">${item.section}</div>`;
      lastSection = item.section;
    }
    const active = location.pathname.endsWith(item.href) ? 'active' : '';
    html += `<a class="nav-item ${active}" href="${item.href}"><span class="icon">${item.icon}</span>${item.label}</a>`;
  }

  return `
    <div class="sidebar" id="sidebar">
      <div class="sidebar-logo">☁️ CloudOps Hub<span>Platform Engineering Portal</span></div>
      <nav class="sidebar-nav">${html}</nav>
      <div class="sidebar-footer">
        <div class="sidebar-user">
          <strong>${currentUser.username || 'user'}</strong>
          ${currentUser.role || ''}
        </div>
        <button class="btn btn-ghost btn-sm" style="margin-top:.5rem;width:100%" onclick="logout()">Sign out</button>
      </div>
    </div>`;
}

async function authGuard() {
  try {
    const res = await fetch('/api/auth/me');
    if (!res.ok) throw new Error('not authenticated');
    const user = await res.json();
    sessionStorage.setItem('currentUser', JSON.stringify(user));
    return user;
  } catch {
    window.location.href = '/login.html';
    return null;
  }
}

async function logout() {
  await fetch('/api/auth/logout', { method: 'POST' });
  sessionStorage.clear();
  window.location.href = '/login.html';
}

function badge(status) {
  if (!status) return '';
  const s = status.toLowerCase();
  let cls = 'badge-pending';
  if (['running','ok','started','created','healthy','available'].some(v => s.includes(v))) cls = 'badge-running';
  else if (['stopped','fail','exited','error','deallocated','terminated'].some(v => s.includes(v))) cls = 'badge-stopped';
  return `<span class="badge ${cls}">${status}</span>`;
}

function fmtBytes(b) {
  if (b > 1e9) return (b/1e9).toFixed(1) + ' GB';
  if (b > 1e6) return (b/1e6).toFixed(1) + ' MB';
  return (b/1e3).toFixed(0) + ' KB';
}

function showAlert(id, msg, type = 'danger') {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = msg;
  el.className = `alert alert-${type} show`;
  setTimeout(() => el.classList.remove('show'), 6000);
}

async function api(path, opts = {}) {
  const res = await fetch('/api' + path, {
    headers: { 'Content-Type': 'application/json', ...opts.headers },
    ...opts,
  });
  if (res.status === 401) { window.location.href = '/login.html'; return null; }
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || res.statusText);
  }
  return res.json();
}
