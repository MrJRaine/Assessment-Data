/* screens.js — builds screen markup for the assessment-platform concepts.
   Theming is done entirely in CSS via [data-dir]; markup is identical
   across directions so the comparison is apples-to-apples.
   All names are placeholder/dummy data. */
(function () {
  const ic = {
    back:  '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5l-5 5 5 5"/></svg>',
    chevR: '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3l5 5-5 5"/></svg>',
    chevD: '<svg width="13" height="13" viewBox="0 0 13 13" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 5l3.5 3.5L10 5"/></svg>',
    check: '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8.5l3 3 7-7.5"/></svg>',
    trash: '<svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 4h10M6.5 4V2.5h3V4M5 4l.6 9h4.8L11 4"/></svg>',
    save:  '<svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 2.5h8L13.5 5v8.5h-11z"/><path d="M5 2.5v3.5h5M5 13.5V9h6v4.5"/></svg>',
    lock:  '<svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3.5" y="7" width="9" height="6.5" rx="1.2"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/></svg>',
    data:  '<svg width="26" height="26" viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 21V11M10 21V5M16 21v-7M22 21V8"/></svg>',
    edit:  '<svg width="26" height="26" viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 21h16M5 16l9.5-9.5 4 4L9 21H5z"/><path d="M13 7.5l4 4"/></svg>',
    clip:  '<svg width="26" height="26" viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="4" width="16" height="19" rx="2"/><path d="M9 4V2.5h8V4M9.5 13l2.5 2.5L17 10"/></svg>',
    plus:  '<svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M7 2v10M2 7h10"/></svg>',
  };

  const achName = ['Not Yet Meeting', 'Approaching', 'Meeting', 'Exceeding'];
  function pill(level) {
    if (!level) return '<span class="mut" style="font-size:12px">—</span>';
    return `<span class="pa-pill ach${level}"><span class="dot"></span>${achName[level - 1]}</span>`;
  }
  function delta(d) {
    if (d === null || d === undefined) return '<span class="delta delta--zero">—</span>';
    if (d > 0) return `<span class="delta delta--pos">+${d}</span>`;
    if (d < 0) return `<span class="delta delta--neg">${d}</span>`;
    return '<span class="delta delta--zero">0</span>';
  }
  function achText(level) {
    if (!level) return '<span class="mut">—</span>';
    return `<span class="ach-text">${achName[level - 1]}</span>`;
  }
  const tint = ['', 'var(--ach1-tint)', 'var(--ach2-tint)', 'var(--ach3-tint)', 'var(--ach4-tint)'];

  /* ---------- shell ---------- */
  function shell(opts) {
    const back = opts.back === false ? '' : `<div class="pa-back">${ic.back}</div>`;
    return `<div class="pa-app">
      <div class="pa-topbar">
        ${back}
        <div class="pa-title">${opts.title}${opts.sub ? ` <span class="pa-title-sub">${opts.sub}</span>` : ''}</div>
        <div class="pa-topbar-spacer"></div>
        ${opts.actions || ''}
      </div>
      <div class="pa-surface"><div class="pa-pad">${opts.body}</div></div>
    </div>`;
  }

  /* ====================================================================
     LANDING / HUB
     ==================================================================== */
  function landing() {
    const card = (icon, h, p, meta) => `<div class="hub-card">
      <span class="edge"></span>
      <div class="ic">${icon}</div>
      <h3>${h}</h3>
      <p>${p}</p>
      <div class="go">${meta} ${ic.chevR}</div>
    </div>`;
    const body = `
      <div style="margin-bottom:22px">
        <div class="t-screen" style="font-size:22px">Reading Assessment</div>
        <div class="t-hint" style="font-style:normal;font-size:13px;margin-top:4px">Welcome back, J. Arsenault · Teacher · Riverbank Elementary</div>
      </div>
      <div class="hub">
        ${card(ic.data, 'Student Data', 'Browse your students with summary charts, then open any student for their full assessment history and progress trend.', 'View &amp; analyze')}
        ${card(ic.edit, 'Data Entry', 'Record reading levels for a class during an open assessment window. The roster grid lets you enter a whole class at once.', '2 windows open')}
        ${card(ic.clip, 'Student IPPs', 'Confirm which students have an Individual Program Plan by subject, so assessment data is interpreted correctly.', '7 to confirm')}
      </div>`;
    return shell({ title: '', back: false, body });
  }

  /* ====================================================================
     STUDENT DATA (COHORT) — priority screen
     ==================================================================== */
  function field(label, value, ph) {
    return `<div class="pa-field">
      <span class="t-cap">${label}</span>
      <div class="pa-combo"><span class="v ${ph ? 'ph' : ''}">${value}</span><span class="chev">${ic.chevD}</span></div>
    </div>`;
  }
  const cohortRows = [
    ['Léa Bouchard', '3', 'French Immersion', 'RVB', 4],
    ['Owen Tremblay', '3', 'English', 'RVB', 3],
    ['Amara Okeke', '4', 'English', 'RVB', 3],
    ['Mathéo Arsenault', '4', 'French Immersion', 'RVB', 2],
    ['Sofia Nguyen', '2', 'English', 'RVB', 4],
    ['Liam Doucet', '5', 'French Immersion', 'MTC', 1],
    ['Chloé Gaudet', '3', 'French Immersion', 'RVB', 3],
    ['Noah Williams', '4', 'English', 'MTC', 2],
    ['Aaliyah Brooks', '2', 'English', 'RVB', 3],
    ['Émile Comeau', '5', 'French Immersion', 'MTC', 4],
    ['Hannah Singh', '3', 'English', 'RVB', null],
    ['Jack Robichaud', '4', 'French Immersion', 'RVB', 2],
    ['Maya Thompson', '2', 'English', 'MTC', 3],
    ['Félix LeBlanc', '5', 'French Immersion', 'RVB', 3],
  ];
  function cohort() {
    const toolbar = `<div class="pa-toolbar">
      <div class="filters">
        ${field('School Year', '2025–2026')}
        ${field('Grade min', 'Primary')}
        ${field('Grade max', '12')}
        ${field('Gender', 'All')}
        ${field('Self-ID<br>African', 'All')}
        ${field('Self-ID<br>Indigenous', 'All')}
      </div>
      <button class="pa-btn pa-btn--ghost">Reset filters</button>
    </div>`;

    const rows = cohortRows.map(r => `<div class="pa-row" style="background:${tint[r[4] || 0]}">
        <div class="pa-cell" style="flex:1 1 auto;min-width:150px"><span class="pa-link">${r[0]}</span></div>
        <div class="pa-cell t-num" style="width:54px">${r[1]}</div>
        <div class="pa-cell" style="width:128px">${r[2]}</div>
        <div class="pa-cell" style="width:60px">${r[3]}</div>
        <div class="pa-cell" style="width:24px;color:var(--brand-ink)">${ic.chevR}</div>
      </div>`).join('');

    const list = `<div class="pa-card" style="flex:1.15 1 0;min-width:0;padding:14px 8px 4px">
      <div class="pa-thead" style="padding:0 12px 8px">
        <div class="pa-th" style="flex:1 1 auto;min-width:150px">Student</div>
        <div class="pa-th" style="width:54px">Grade</div>
        <div class="pa-th" style="width:128px">Program</div>
        <div class="pa-th" style="width:60px">School</div>
        <div class="pa-th" style="width:24px"></div>
      </div>
      <div class="pa-tbody">${rows}</div>
    </div>`;

    const donut = `<div class="pa-card" style="flex:1 1 0;min-width:0">
      <div class="chart-title">Current achievement distribution</div>
      <div class="donut-row">
        <div class="pa-donut" style="background:conic-gradient(var(--ach1) 0 12%,var(--ach2) 12% 35%,var(--ach3) 35% 76%,var(--ach4) 76% 100%)"><div class="hole"></div><div class="ctr"><div class="big">312</div><div class="sub">assessed</div></div></div>
        <div class="legend">
          <div class="li"><span class="pct">24%</span><span class="sw" style="background:var(--ach4)"></span><span class="nm">Exceeding</span><span class="cnt">· 74</span></div>
          <div class="li"><span class="pct">41%</span><span class="sw" style="background:var(--ach3)"></span><span class="nm">Meeting</span><span class="cnt">· 128</span></div>
          <div class="li"><span class="pct">23%</span><span class="sw" style="background:var(--ach2)"></span><span class="nm">Approaching</span><span class="cnt">· 72</span></div>
          <div class="li"><span class="pct">12%</span><span class="sw" style="background:var(--ach1)"></span><span class="nm">Not Yet Meeting</span><span class="cnt">· 38</span></div>
        </div>
      </div>
    </div>`;

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
    const series = [[6,9,18,9],[7,11,19,10],[5,10,22,11],[6,12,24,13],[4,11,26,14],[5,13,27,16]];
    const maxv = 30;
    const bars = months.map((m, i) => {
      const cl = series[i].map((v, s) => `<div class="bar" style="height:${(v / maxv) * 100}%;background:var(--ach${s + 1})"></div>`).join('');
      return `<div class="group">${cl}</div>`;
    }).join('');
    const gl = '<div class="gl" style="top:0"></div><div class="gl" style="top:33.33%"></div><div class="gl" style="top:66.66%"></div>';
    const xrow = months.map(m => `<span>${m}</span>`).join('');
    const barChart = `<div class="pa-card" style="margin-top:16px">
      <div style="display:flex;align-items:baseline;justify-content:space-between;margin-bottom:14px">
        <div class="chart-title">Achievement by month — students assessed, last 6 months</div>
        <div class="legend" style="flex-direction:row;gap:16px">
          <div class="li"><span class="sw" style="background:var(--ach1)"></span>Not Yet</div>
          <div class="li"><span class="sw" style="background:var(--ach2)"></span>Approaching</div>
          <div class="li"><span class="sw" style="background:var(--ach3)"></span>Meeting</div>
          <div class="li"><span class="sw" style="background:var(--ach4)"></span>Exceeding</div>
        </div>
      </div>
      <div class="barchart">
        <div class="yaxis"><span>30</span><span>20</span><span>10</span><span>0</span></div>
        <div class="plotwrap"><div class="plot">${gl}<div class="bars">${bars}</div></div><div class="xrow">${xrow}</div></div>
      </div>
    </div>`;

    const body = `${toolbar}
      <div class="t-hint" style="margin:14px 0 12px">Tap a student's name to view their assessment history.</div>
      <div style="display:flex;gap:16px;flex:1 1 auto;min-height:0">${list}${donut}</div>
      ${barChart}`;
    return shell({ title: 'Student Data', body });
  }

  /* ====================================================================
     ROSTER GRID — data entry workhorse
     ==================================================================== */
  // name, expectedBand, existing, newLevelValue(null=placeholder), achievement(1-4|null), state
  const rosterRows = [
    ['Bouchard, Léa', 'L–N', 'M', 'N', 4, 'dirty'],
    ['Arsenault, Mathéo', 'L–N', 'K', null, null, 'open'],
    ['Comeau, Émile', 'L–N', 'L', 'M', 3, 'dirty'],
    ['Doucet, Liam', 'L–N', 'J', 'J', 1, 'set'],
    ['Gaudet, Chloé', 'L–N', 'N', 'N', 3, 'set'],
    ['LeBlanc, Félix', 'L–N', 'I', null, null, 'open'],
    ['Robichaud, Jack', 'L–N', 'H', null, null, 'ipp-confirm'],
    ['Maillet, Anaïs', 'IPP', 'J', null, null, 'ipp'],
    ['Thériault, Noé', 'L–N', 'K', 'K', 2, 'set'],
    ['Boudreau, Camille', 'L–N', 'O', 'O', 4, 'set'],
    ['Aucoin, Gabriel', 'L–N', 'J', null, null, 'open'],
    ['Cormier, Juliette', 'L–N', 'L', null, null, 'open'],
  ];
  function rosterRow(r) {
    const [name, exp, existing, nl, ach, state] = r;
    const rowTint = (state === 'ipp' || state === 'ipp-confirm') ? 'transparent' : tint[ach || 0];
    let expCell, newCell, achCell, action;
    if (state === 'ipp') {
      expCell = '<span class="pa-pill pill-ipp">IPP</span>';
      newCell = `<div class="pa-combo pa-combo--inline" style="width:150px"><span class="v ${existing !== '—' ? '' : 'ph'}">${existing !== '—' ? 'Level ' + existing : 'Select level'}</span><span class="chev">${ic.chevD}</span></div>`;
      achCell = '<span class="mut">Not measured</span>';
      action = existing !== '—' ? `<div class="pa-icobtn pa-icobtn--del">${ic.trash}</div>` : '';
    } else if (state === 'ipp-confirm') {
      expCell = '<span class="pa-pill pill-warn">Confirm IPP</span>';
      newCell = `<div style="display:flex;gap:6px"><button class="pa-btn pa-btn--sm">Yes (IPP)</button><button class="pa-btn pa-btn--ghost pa-btn--sm">No</button></div>`;
      achCell = '';
      action = '';
    } else {
      expCell = `<span class="mut2">Expected ${exp}</span>`;
      const comboTxt = nl ? `Level ${nl}` : 'Select level';
      newCell = `<div class="pa-combo pa-combo--inline${state === 'dirty' ? ' is-focus' : ''}" style="width:150px"><span class="v ${nl ? '' : 'ph'}">${comboTxt}</span><span class="chev">${ic.chevD}</span></div>`;
      achCell = achText(ach);
      action = state === 'dirty'
        ? `<div class="pa-icobtn pa-icobtn--ok">${ic.check}</div>`
        : (existing !== '—' ? `<div class="pa-icobtn pa-icobtn--del">${ic.trash}</div>` : '');
    }
    const d = state === 'dirty' ? (nl && exp !== 'IPP' ? 1 : null)
      : (ach === 3 ? 0 : ach === 4 ? 2 : ach === 2 ? -1 : ach === 1 ? -2 : null);
    return `<div class="pa-row" style="background:${rowTint}">
      <div class="pa-cell t-strong" style="width:170px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${name}</div>
      <div class="pa-cell" style="width:150px">${expCell}</div>
      <div class="pa-cell" style="width:96px"><span class="mut">${existing === '—' ? '—' : 'Now ' + existing}</span></div>
      <div class="pa-cell" style="width:64px">${state === 'ipp' || state === 'ipp-confirm' ? '<span class="mut">—</span>' : delta(d)}</div>
      <div class="pa-cell" style="width:170px">${newCell}</div>
      <div class="pa-cell" style="flex:1 1 auto;min-width:130px">${achCell}</div>
      <div class="pa-cell" style="width:40px;justify-content:flex-end">${action}</div>
    </div>`;
  }
  function roster() {
    const head = `<div class="pa-thead">
      <div class="pa-th" style="width:170px">Student</div>
      <div class="pa-th" style="width:150px">Expected</div>
      <div class="pa-th" style="width:96px">Existing</div>
      <div class="pa-th" style="width:64px">Diff</div>
      <div class="pa-th" style="width:170px">New level</div>
      <div class="pa-th" style="flex:1 1 auto;min-width:130px">Achievement</div>
      <div class="pa-th" style="width:40px"></div>
    </div>`;
    const body = `
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:14px">
        <span class="pa-pill pill-ipp"><span class="dot" style="background:var(--brand)"></span>Window open · closes Jun 13</span>
        <span class="t-hint" style="margin-left:auto">26 students · 3 unsaved changes</span>
      </div>
      <div class="pa-table" style="flex:1 1 auto;min-height:0">
        ${head}
        <div class="pa-tbody">${rosterRows.map(rosterRow).join('')}</div>
      </div>
      <div style="display:flex;align-items:center;gap:12px;padding-top:14px;border-top:1px solid var(--line);margin-top:6px">
        <span class="t-hint" style="font-style:normal">Changes save together. You can keep editing after saving.</span>
        <div class="pa-topbar-spacer"></div>
        <button class="pa-btn pa-btn--ghost">Discard</button>
        <button class="pa-btn">${ic.save} Save 3 changes</button>
      </div>`;
    return shell({
      title: 'Grade 3B', sub: '· Spring Reading P–6',
      actions: `<button class="pa-btn pa-btn--invert">${ic.save} Save 3 changes</button>`,
      body,
    });
  }

  /* ====================================================================
     FOUNDATIONS SHEET
     ==================================================================== */
  function foundations() {
    const swatch = (bg, name, hex, lt) => `<div><div class="sw ${lt ? 'lt' : ''}" style="background:${bg}">${name}</div><div class="sw-meta">${hex}</div></div>`;
    const palette = `<div>
      <div class="t-cap" style="margin-bottom:10px">Brand &amp; neutrals</div>
      <div class="fs-grid" style="grid-template-columns:repeat(6,1fr)">
        ${swatch('var(--brand)', 'Primary', '#0092C9')}
        ${swatch('var(--brand-ink)', 'Primary ink', '#036C92')}
        ${swatch('var(--ink)', 'Ink', '#182B34')}
        ${swatch('var(--ink-3)', 'Muted', '#6E7E86')}
        ${swatch('var(--surface-2)', 'Surface', '#F4F7F9', true)}
        ${swatch('#fff', 'White', '#FFFFFF', true)}
      </div>
    </div>`;
    const ach = `<div>
      <div class="t-cap" style="margin-bottom:10px">Achievement scale — semantic, accessible, also chart series</div>
      <div class="fs-grid" style="grid-template-columns:repeat(4,1fr)">
        ${swatch('var(--ach1)', 'Not Yet Meeting', '#D1495B')}
        ${swatch('var(--ach2)', 'Approaching', '#E8A33D')}
        ${swatch('var(--ach3)', 'Meeting', '#8FB339')}
        ${swatch('var(--ach4)', 'Exceeding', '#2E7D5B')}
      </div>
      <div style="margin-top:12px;border-radius:8px;overflow:hidden;box-shadow:inset 0 0 0 1px var(--line)">
        ${[4, 3, 2, 1].map(l => `<div class="pa-row" style="background:${tint[l]}">
            <div class="pa-cell" style="width:170px"><span class="ach-text">${achName[l - 1]}</span></div>
            <div class="pa-cell mut" style="width:200px;font-size:12px">subtle row tint + plain label</div>
            <div class="pa-cell" style="width:60px">${delta(l === 4 ? 2 : l === 3 ? 0 : l === 2 ? -1 : -3)}</div>
          </div>`).join('')}
      </div>
      <div class="t-hint" style="margin-top:8px">Color is a redundant cue — the text label carries meaning on its own (WCAG 1.4.1).</div>
    </div>`;
    const type = `<div>
      <div class="t-cap" style="margin-bottom:10px">Type scale — Lato, tabular figures for data</div>
      <div style="display:flex;flex-direction:column;gap:7px">
        <div class="t-screen" style="font-size:22px">Screen title · Lato Black 22</div>
        <div class="t-section">Section heading · Lato Bold 14</div>
        <div class="t-row">Row text and body copy · Lato Regular 13</div>
        <div class="t-cap">Column label / caption · Lato Black 11 uppercase</div>
        <div class="t-hint">Helper &amp; hint text · Lato Italic 12</div>
      </div>
    </div>`;
    const comps = `<div>
      <div class="t-cap" style="margin-bottom:10px">Components</div>
      <div style="display:flex;gap:14px;align-items:flex-end;flex-wrap:wrap">
        <button class="pa-btn">${ic.save} Primary</button>
        <button class="pa-btn pa-btn--ghost">Secondary</button>
        <button class="pa-btn is-disabled">Disabled</button>
        <button class="pa-btn pa-btn--danger">${ic.trash} Remove</button>
        ${field('Filter', 'All')}
        <div class="pa-field"><span class="t-cap">Reading level</span><div class="pa-combo" style="width:160px"><span class="v ph">Select level</span><span class="chev">${ic.chevD}</span></div></div>
      </div>
    </div>`;
    const states = `<div style="display:flex;gap:16px">
      <div class="pa-card" style="flex:1 1 0;height:140px"><div class="t-cap" style="margin-bottom:4px">Loading state</div><div class="pa-loading"><div class="spinner"></div><div class="msg">Loading roster…</div></div></div>
      <div class="pa-card" style="flex:1 1 0;height:140px"><div class="t-cap" style="margin-bottom:4px">Empty state</div><div class="pa-empty"><div class="glyph">${ic.clip}</div><div class="msg">No assessment windows currently apply to your students.</div></div></div>
      <div class="modal-mini"><div class="t-strong" style="margin-bottom:6px">Discard changes?</div><div class="t-row mut2" style="margin-bottom:14px">You have 3 unsaved changes.</div><div style="display:flex;gap:8px;justify-content:flex-end"><button class="pa-btn pa-btn--ghost pa-btn--sm">Keep editing</button><button class="pa-btn pa-btn--sm">Discard</button></div></div>
    </div>`;
    const extras = `<div>
      <div class="t-cap" style="margin-bottom:10px">Chrome, status &amp; progress</div>
      <div style="display:flex;gap:28px;flex-wrap:wrap;align-items:flex-start">
        <div>
          <div class="mut" style="font-size:11px;margin-bottom:8px">Header bar — inverted Save + student paging</div>
          <div style="background:var(--brand);padding:12px 16px;border-radius:8px;display:flex;align-items:center;gap:12px">
            <button class="pa-btn pa-btn--invert">${ic.save} Save 3 changes</button>
            <div class="pa-navbtn">${ic.back}</div>
            <span style="color:#fff;font-size:12px;font-weight:700">Student 1 of 28</span>
            <div class="pa-navbtn">${ic.chevR}</div>
          </div>
        </div>
        <div>
          <div class="mut" style="font-size:11px;margin-bottom:8px">Status pills</div>
          <div style="display:flex;gap:8px;flex-wrap:wrap;max-width:430px">
            <span class="pa-pill" style="background:var(--ach4-tint);color:var(--ach4-ink)"><span class="dot" style="background:var(--ach4)"></span>Open</span>
            <span class="pa-pill" style="background:var(--ach2-tint);color:var(--ach2-ink)"><span class="dot" style="background:var(--ach2)"></span>Closes today</span>
            <span class="pa-pill pill-lock">Closed</span>
            <span class="pa-pill" style="background:var(--ach4-tint);color:var(--ach4-ink)"><span class="dot" style="background:var(--ach4)"></span>Yes (IPP)</span>
            <span class="pa-pill pill-warn"><span class="dot" style="background:var(--ach1)"></span>Needs confirmation</span>
            <span class="pa-pill pill-ipp">IPP</span>
          </div>
        </div>
        <div style="width:220px">
          <div class="mut" style="font-size:11px;margin-bottom:8px">Progress</div>
          <div style="display:flex;flex-direction:column;gap:12px">
            <div><div class="mut" style="font-size:11px;font-weight:700;margin-bottom:5px">◐ 18 of 24 entered</div><div class="pa-prog"><span style="width:75%;background:var(--brand)"></span></div></div>
            <div><div class="mut" style="font-size:11px;font-weight:700;margin-bottom:5px">✓ 25 of 25 entered</div><div class="pa-prog"><span style="width:100%;background:var(--ach4)"></span></div></div>
          </div>
        </div>
      </div>
      <div class="t-hint" style="margin-top:10px">Gallery row divider #D4DDE2 (reinforced). Pie / bar chart series use the solid achievement colors; row washes use the tints.</div>
    </div>`;
    const body = `<div class="fs">
      ${palette}${ach}${type}${comps}${extras}${states}
    </div>`;
    return shell({ title: 'Design System', sub: '· tokens, type & components', back: false, body });
  }

  /* ====================================================================
     WINDOW SELECT
     ==================================================================== */
  function windowSelect() {
    const statusPill = (s) => {
      if (s === 'open') return '<span class="pa-pill" style="background:var(--ach4-tint);color:var(--ach4-ink)"><span class="dot" style="background:var(--ach4)"></span>Open</span>';
      if (s === 'today') return '<span class="pa-pill" style="background:var(--ach2-tint);color:var(--ach2-ink)"><span class="dot" style="background:var(--ach2)"></span>Closes today</span>';
      return '<span class="pa-pill pill-lock">Closed</span>';
    };
    const rows = [
      ['Spring Reading', 'Reading · Grades P–6 · Apr 1 – Jun 13', 'open'],
      ['Spring Reading', 'Reading · Grades 7–9 · Apr 1 – Jun 9', 'today'],
      ['Winter Reading', 'Reading · Grades P–6 · Jan 6 – Feb 14', 'closed'],
      ['Fall Reading', 'Reading · Grades P–6 · Oct 1 – Nov 15', 'closed'],
    ];
    const list = rows.map(r => `<div class="pa-listrow">
        <div style="flex:0 0 270px;min-width:0;overflow:hidden">
          <div class="t-strong" style="font-size:14px;white-space:nowrap">${r[0]}</div>
          <div class="mut" style="font-size:12px;margin-top:2px;white-space:nowrap">${r[1]}</div>
        </div>
        <div style="flex:0 0 auto;margin-left:18px">${statusPill(r[2])}</div>
        <div style="width:22px;color:var(--brand-ink);margin-left:auto;display:flex;flex:0 0 auto">${ic.chevR}</div>
      </div>`).join('');
    const body = `
      <div class="t-section" style="margin-bottom:4px">Choose an assessment window</div>
      <div class="t-hint" style="font-style:normal;margin-bottom:16px">Windows open for entry, or closed ones you can still review.</div>
      <div class="pa-listgroup">${list}</div>`;
    return shell({ title: 'Data Entry', sub: '· assessment windows', body });
  }

  /* ====================================================================
     GROUP / CLASS SELECT
     ==================================================================== */
  function groupSelect() {
    const rows = [
      ['3B', 'Grade 3 · 24 applicable students', 18, 24],
      ['3F', 'Grade 3 · French Immersion · 22 applicable students', 22, 22],
      ['4A', 'Grade 4 · 26 applicable students', 0, 26],
      ['4F', 'Grade 4 · French Immersion · 23 applicable students', 11, 23],
      ['5A', 'Grade 5 · 25 applicable students', 25, 25],
    ];
    const prog = (e, t) => {
      const pct = Math.round((e / t) * 100), done = e === t, none = e === 0;
      const mark = done ? '✓' : none ? '○' : '◐';
      return `<div style="width:172px;display:flex;flex-direction:column;gap:6px">
          <div class="mut" style="font-size:11.5px;font-weight:700">${mark} ${e} of ${t} entered</div>
          <div class="pa-prog"><span style="width:${pct}%;background:${done ? 'var(--ach4)' : 'var(--brand)'}"></span></div>
        </div>`;
    };
    const list = rows.map(r => `<div class="pa-listrow">
        <div style="flex:0 0 320px;min-width:0;overflow:hidden">
          <div class="t-strong" style="font-size:14px;white-space:nowrap">${r[0]}</div>
          <div class="mut" style="font-size:12px;margin-top:2px;white-space:nowrap">${r[1]}</div>
        </div>
        <div style="flex:0 0 auto;margin-left:18px">${prog(r[2], r[3])}</div>
        <div style="width:22px;color:var(--brand-ink);margin-left:auto;display:flex;flex:0 0 auto">${ic.chevR}</div>
      </div>`).join('');
    const body = `
      <div class="t-section" style="margin-bottom:4px">Spring Reading — Grades P–6</div>
      <div class="t-hint" style="font-style:normal;margin-bottom:16px">Choose a class</div>
      <div class="pa-listgroup">${list}</div>`;
    return shell({ title: 'Spring Reading', sub: '· choose a class', body });
  }

  /* ====================================================================
     STUDENT IPPs
     ==================================================================== */
  function studentIPP() {
    const rows = [
      ['Maillet, Anaïs', '3', '3B', 'French Reading', 'yes'],
      ['Robichaud, Jack', '3', '3B', 'English Reading', 'confirm'],
      ['Comeau, Émile', '5', '5A', 'French Reading', 'confirm'],
      ['Doucet, Liam', '5', '5A', 'French Mathematics', 'no'],
      ['Boudreau, Camille', '3', '3B', 'English Writing', 'yes'],
      ['Thériault, Noé', '3', '3B', 'French Reading', 'confirm'],
      ['Bouchard, Léa', '3', '3F', 'French Reading', 'yes'],
    ];
    const status = (s) => {
      if (s === 'yes') return '<span class="pa-pill" style="background:var(--ach4-tint);color:var(--ach4-ink)"><span class="dot" style="background:var(--ach4)"></span>Yes (IPP)</span>';
      if (s === 'no') return '<span class="mut" style="font-weight:700">No</span>';
      return '<span class="pa-pill pill-warn"><span class="dot" style="background:var(--ach1)"></span>Needs confirmation</span>';
    };
    const action = (s) => s === 'confirm'
      ? `<div style="display:flex;gap:6px"><button class="pa-btn pa-btn--sm">Yes (IPP)</button><button class="pa-btn pa-btn--ghost pa-btn--sm">No</button></div>`
      : `<div class="pa-icobtn pa-icobtn--ok">${ic.check}</div>`;
    const head = `<div class="pa-thead">
      <div class="pa-th" style="width:180px">Student</div>
      <div class="pa-th" style="width:64px">Grade</div>
      <div class="pa-th" style="width:110px">Homeroom</div>
      <div class="pa-th" style="width:180px">IPP Subject</div>
      <div class="pa-th" style="width:180px">Status</div>
      <div class="pa-th" style="width:210px">Action</div>
    </div>`;
    const tbody = rows.map(r => `<div class="pa-row">
        <div class="pa-cell t-strong" style="width:180px">${r[0]}</div>
        <div class="pa-cell t-num" style="width:64px">${r[1]}</div>
        <div class="pa-cell" style="width:110px">${r[2]}</div>
        <div class="pa-cell" style="width:180px">${r[3]}</div>
        <div class="pa-cell" style="width:180px">${status(r[4])}</div>
        <div class="pa-cell" style="width:210px">${action(r[4])}</div>
      </div>`).join('');
    const body = `
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px">
        <span class="pa-pill pill-warn"><span class="dot" style="background:var(--ach1)"></span>3 of 7 still need confirmation</span>
        <span class="t-hint" style="margin-left:auto">Confirm each IPP subject so assessment data is interpreted correctly.</span>
      </div>
      <div class="pa-table" style="flex:1 1 auto;min-height:0">${head}<div class="pa-tbody">${tbody}</div></div>
      <div style="display:flex;align-items:center;padding-top:14px;border-top:1px solid var(--line);margin-top:6px">
        <span class="t-hint" style="font-style:normal">Changes save together. You can keep editing after saving.</span>
        <div class="pa-topbar-spacer"></div>
        <button class="pa-btn">${ic.save} Save 3 changes</button>
      </div>`;
    return shell({
      title: 'Student IPPs', sub: '· subject confirmation',
      actions: `<button class="pa-btn pa-btn--invert">${ic.save} Save 3 changes</button>`,
      body,
    });
  }

  /* ====================================================================
     STUDENT DETAIL
     ==================================================================== */
  function studentDetail() {
    const lvl = { 'Not Yet Meeting': 1, 'Approaching': 2, 'Meeting': 3, 'Exceeding': 4 };
    const tl = [
      ['Spring Reading', '2025–2026', 'Apr 12, 2026', 'N', 2, 'Exceeding'],
      ['Winter Reading', '2025–2026', 'Jan 18, 2026', 'M', 1, 'Meeting'],
      ['Fall Reading', '2025–2026', 'Oct 9, 2025', 'L', 0, 'Meeting'],
      ['Spring Reading', '2024–2025', 'Apr 15, 2025', 'K', -1, 'Approaching'],
      ['Fall Reading', '2024–2025', 'Oct 11, 2024', 'I', null, 'Approaching'],
    ];
    const head = `<div class="pa-thead">
      <div class="pa-th" style="width:300px">Assessment window</div>
      <div class="pa-th" style="width:140px">Date</div>
      <div class="pa-th" style="width:70px">Level</div>
      <div class="pa-th" style="width:90px">Diff</div>
      <div class="pa-th" style="flex:1 1 auto;min-width:140px">Achievement</div>
    </div>`;
    const rows = tl.map(r => `<div class="pa-row" style="background:${tint[lvl[r[5]]]}">
        <div class="pa-cell t-strong" style="width:300px">${r[0]} <span class="mut" style="font-weight:400">· ${r[1]}</span></div>
        <div class="pa-cell" style="width:140px">${r[2]}</div>
        <div class="pa-cell t-strong" style="width:70px">${r[3]}</div>
        <div class="pa-cell" style="width:90px">${delta(r[4])}</div>
        <div class="pa-cell" style="flex:1 1 auto;min-width:140px"><span class="ach-text">${r[5]}</span></div>
      </div>`).join('');

    // line chart: reading level (LevelOrder) over time, oldest → newest
    const data = [['Oct \u201924', 9], ['Apr \u201925', 11], ['Oct \u201925', 12], ['Jan \u201926', 13], ['Apr \u201926', 14]];
    const L = 34, R = 44, T = 12, Bm = 28, W = 1000, H = 200, pw = W - L - R, ph = H - T - Bm, yMin = 0, yMax = 31;
    const X = i => L + pw * (i / (data.length - 1));
    const Y = o => T + ph * (1 - (o - yMin) / (yMax - yMin));
    const pts = data.map((d, i) => `${X(i).toFixed(1)},${Y(d[1]).toFixed(1)}`).join(' ');
    const dots = data.map((d, i) => `<circle class="dot" cx="${X(i).toFixed(1)}" cy="${Y(d[1]).toFixed(1)}" r="4.5"/>`).join('');
    const xlabs = data.map((d, i) => `<text class="xlab" x="${X(i).toFixed(1)}" y="${H - 8}">${d[0]}</text>`).join('');
    const yt = [['30', 30], ['20', 20], ['10', 10], ['0', 0]];
    const grid = yt.map(t => `<line class="grid" x1="${L}" y1="${Y(t[1]).toFixed(1)}" x2="${W - R}" y2="${Y(t[1]).toFixed(1)}"/><text class="ylab" x="${L - 8}" y="${(Y(t[1]) + 4).toFixed(1)}">${t[0]}</text>`).join('');
    const svg = `<svg class="linechart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" style="width:100%;height:100%;display:block">
        ${grid}
        <line class="axis" x1="${L}" y1="${T}" x2="${L}" y2="${H - Bm}"/>
        <line class="axis" x1="${L}" y1="${H - Bm}" x2="${W - R}" y2="${H - Bm}"/>
        <polyline class="ln" points="${pts}"/>${dots}${xlabs}
      </svg>`;

    const body = `
      <div class="detail-meta">
        <span class="m">Grade <b>3</b></span><span class="m">Program <b>French Immersion</b></span>
        <span class="m">School <b>RVB</b></span><span class="m">Homeroom <b>3F</b></span>
        <span class="m">IPP (Reading) <b>No</b></span>
      </div>
      <div style="flex:1 1 auto;min-height:0;display:flex;flex-direction:column;gap:16px">
        <div style="flex:1 1 0;min-height:0;display:flex;flex-direction:column">
          <div class="t-section" style="margin-bottom:8px">Assessment history</div>
          <div class="pa-table">${head}<div class="pa-tbody">${rows}</div></div>
        </div>
        <div class="pa-card" style="flex:1 1 0;min-height:0">
          <div class="chart-title" style="margin-bottom:6px">Reading level over time <span class="mut" style="font-weight:400">· reading-level scale (0–31)</span></div>
          <div style="flex:1 1 auto;min-height:0">${svg}</div>
        </div>
      </div>`;
    return shell({
      title: 'Bouchard, Léa', sub: '· student detail',
      actions: `<div style="display:flex;align-items:center;gap:9px">
          <div class="pa-navbtn">${ic.back}</div>
          <span style="font-size:12px;font-weight:700;color:#fff;white-space:nowrap">Student 1 of 28</span>
          <div class="pa-navbtn">${ic.chevR}</div>
        </div>`,
      body,
    });
  }

  window.SCREENS = { landing, windowSelect, groupSelect, roster, studentIPP, cohort, studentDetail, foundations };
})();
