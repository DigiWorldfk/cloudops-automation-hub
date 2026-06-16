// shared.js — sidebar, auth guard, common utilities

const NAV_ITEMS = [
  { label: 'Dashboard',    href: 'dashboard.html',  icon: '📊', section: 'OVERVIEW' },
  { label: 'AI Agent',     href: 'agent.html',       icon: '🤖', section: 'OVERVIEW' },
  {
    label: 'Azure',
    icon: '🔵',
    section: 'CLOUD',
    children: [
      { label: 'Virtual Machines', href: 'azure.html',      icon: '🖥️' },
      { label: 'AKS',              href: 'kubernetes.html',  icon: '☸️' },
      { label: 'Containers',       href: 'docker.html',      icon: '🐳' },
    ],
  },
  { label: 'AWS EC2',      href: 'aws.html',         icon: '🟠', section: 'CLOUD' },
  { label: 'Terraform',    href: 'terraform.html',   icon: '🏗️',  section: 'IaC' },
  { label: 'Activity Log', href: 'activity.html',    icon: '📋', section: 'OPS' },
];

function buildSidebar(activeHref) {
  const currentUser = JSON.parse(sessionStorage.getItem('currentUser') || '{}');
  const openGroups  = JSON.parse(localStorage.getItem('sidebarOpen') || '{}');

  let lastSection = null;
  let html = '';

  for (const item of NAV_ITEMS) {
    if (item.section !== lastSection) {
      if (lastSection !== null) html += '</div>';
      html += `<div class="nav-section-group"><div class="nav-section">${item.section}</div>`;
      lastSection = item.section;
    }

    if (item.children) {
      const childActive = item.children.some(c => location.pathname.endsWith(c.href));
      const isOpen = childActive || !!openGroups[item.label];
      const gid = 'navgroup-' + item.label.replace(/\s+/g, '_');

      html += `<div class="nav-group" id="${gid}">
        <div class="nav-group-header${childActive ? ' child-active' : ''}" onclick="toggleNavGroup('${item.label}')">
          <span class="icon">${item.icon}</span>
          <span class="nav-group-label">${item.label}</span>
          <span class="nav-group-arrow">${isOpen ? '▾' : '▸'}</span>
        </div>
        <div class="nav-group-children" style="display:${isOpen ? 'block' : 'none'}">`;

      for (const child of item.children) {
        const active = location.pathname.endsWith(child.href) ? 'active' : '';
        html += `<a class="nav-sub-item ${active}" href="${child.href}"><span class="icon">${child.icon}</span>${child.label}</a>`;
      }
      html += `</div></div>`;
    } else {
      const active = location.pathname.endsWith(item.href) ? 'active' : '';
      html += `<a class="nav-item ${active}" href="${item.href}"><span class="icon">${item.icon}</span>${item.label}</a>`;
    }
  }
  if (lastSection !== null) html += '</div>';

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

function toggleNavGroup(label) {
  const openGroups = JSON.parse(localStorage.getItem('sidebarOpen') || '{}');
  openGroups[label] = !openGroups[label];
  localStorage.setItem('sidebarOpen', JSON.stringify(openGroups));
  const group = document.getElementById('navgroup-' + label.replace(/\s+/g, '_'));
  if (!group) return;
  const children = group.querySelector('.nav-group-children');
  const arrow    = group.querySelector('.nav-group-arrow');
  children.style.display = openGroups[label] ? 'block' : 'none';
  arrow.textContent      = openGroups[label] ? '▾' : '▸';
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
    credentials: 'include',
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
