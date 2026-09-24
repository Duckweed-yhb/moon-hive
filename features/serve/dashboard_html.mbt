///|
/// 仪表盘 HTML 模板。
///
/// 设计：单文件、内联 CSS/JS、零外部依赖——浏览器打开即用，
/// 数据通过两个只读 API 从本地 HTTP 服务取：
///   /api/reports     报告列表
///   /api/report/<n>  单个报告 JSON
/// 用 `#|` 原始多行字符串保存，`#` 前不要加空格。
pub fn template() -> String {
  let t =
#|<!DOCTYPE html>
#|<html lang="zh-CN">
#|<head>
#|<meta charset="utf-8">
#|<meta name="viewport" content="width=device-width,initial-scale=1">
#|<title>MoonHive 生态验证仪表盘</title>
#|<style>
#|body{font-family:system-ui,-apple-system,'Segoe UI',sans-serif;max-width:1000px;margin:0 auto;padding:20px;line-height:1.6;color:#1a1a1a;background:#fff}
#|h1{font-size:1.5rem;margin:0 0 4px}
#|h2{font-size:1.05rem;margin:22px 0 10px;border-bottom:1px solid #e5e5e5;padding-bottom:6px}
#|.sub{color:#666;font-size:.9rem;margin-bottom:14px}
#|.toolbar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:12px 0}
#|select,button{font-size:.9rem;padding:6px 10px;border:1px solid #d0d7de;border-radius:6px;background:#fff}
#|button{cursor:pointer}
#|button:hover{background:#f3f4f6}
#|.env{background:#f7f7f8;border:1px solid #e5e5e5;border-radius:8px;padding:10px 14px;margin:10px 0;font-size:.88rem}
#|.env div{margin:2px 0}
#|.env code{background:#fff;padding:1px 6px;border-radius:3px;border:1px solid #e5e5e5}
#|.stats{display:flex;flex-wrap:wrap;gap:10px;margin:14px 0}
#|.stat{border:1px solid #e5e5e5;border-radius:8px;padding:10px 16px;min-width:100px;flex:1 1 130px}
#|.stat .n{font-size:1.35rem;font-weight:600}
#|.stat .l{font-size:.78rem;color:#666}
#|.chips{display:flex;flex-wrap:wrap;gap:6px;margin:10px 0}
#|.chip{font-size:.8rem;padding:4px 12px;border-radius:999px;border:1px solid #d0d7de;cursor:pointer;user-select:none;background:#fff}
#|.chip:hover{border-color:#1a1a1a}
#|.chip.on{border-color:#1a1a1a;background:#f3f4f6;font-weight:600}
#|table{border-collapse:collapse;width:100%;font-size:.88rem}
#|th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #eee;vertical-align:top}
#|th{background:#fafafa;font-weight:600;cursor:pointer;white-space:nowrap}
#|th:hover{background:#f0f0f0}
#|code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.85em}
#|.slug{word-break:break-all}
#|.ev{color:#666;font-size:.82em;word-break:break-all;white-space:pre-wrap}
#|.ok{color:#1a7f37}.warn{color:#9a6700}.bad{color:#cf222e}.other{color:#57606a}
#|.row-detail{display:none;background:#fafafa;font-size:.85rem;padding:8px 12px;border-radius:6px;margin:4px 0}
#|.row-detail.show{display:block}
#|.empty{color:#888;padding:16px;text-align:center}
#|footer{margin-top:28px;padding-top:12px;border-top:1px solid #e5e5e5;color:#666;font-size:.82rem}
#|@media(max-width:640px){body{padding:12px}th,td{padding:6px 8px}.stat{flex:1 1 100%}}
#|</style>
#|</head>
#|<body>
#|<header>
#|  <h1>MoonHive 生态验证仪表盘</h1>
#|  <div class="sub">用真实 MoonBit 工具链逐个验证生态包：能不能编译、测试过不过、失败属于哪一类。</div>
#|  <div class="toolbar">
#|    <select id="report-select" title="选择报告"><option value="">（加载中…）</option></select>
#|    <button id="refresh" title="重新加载">刷新</button>
#|  </div>
#|</header>
#|
#|<section id="env" class="env"></section>
#|
#|<section>
#|  <h2>概览</h2>
#|  <div id="stats" class="stats"></div>
#|</section>
#|
#|<section>
#|  <h2>结论分布（点击筛选）</h2>
#|  <div id="chips" class="chips"></div>
#|</section>
#|
#|<section>
#|  <h2>逐个结果 <span id="count"></span></h2>
#|  <table>
#|    <thead><tr>
#|      <th data-key="slug">项目</th>
#|      <th data-key="diagnosis">结论</th>
#|      <th data-key="sourceLines">规模</th>
#|      <th data-key="checkMs">耗时</th>
#|      <th>证据</th>
#|    </tr></thead>
#|    <tbody id="tbody"></tbody>
#|  </table>
#|  <div id="empty" class="empty" style="display:none">（无数据）</div>
#|</section>
#|
#|<footer>由 <code>moonhive survey</code> 生成 · <code>moonhive serve</code> 展示 · MoonHive · MIT</footer>
#|
#|<script>
#|(function () {
#|  'use strict';
#|  var state = { report: null, filter: null, sortKey: 'slug', sortAsc: true };
#|  var DIAG = {
#|    'Verified':          { cls: 'ok',    mark: '✅' },
#|    'TestFailing':       { cls: 'warn',  mark: '⚠️' },
#|    'DoesNotCompile':    { cls: 'bad',   mark: '❌' },
#|    'ToolchainMismatch': { cls: 'warn',  mark: '🚫' },
#|    'MissingDependency': { cls: 'warn',  mark: '📦' },
#|    'NoManifest':        { cls: 'other', mark: '📄' },
#|    'TimedOut':          { cls: 'other', mark: '⏱️' },
#|    'Unsafe':            { cls: 'other', mark: '🔒' },
#|    'FetchFailed':       { cls: 'bad',   mark: '🌐' }
#|  };
#|  function esc(s) {
#|    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
#|      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
#|  }
#|  function api(path) {
#|    return fetch(path).then(function (r) {
#|      if (!r.ok) throw new Error('HTTP ' + r.status);
#|      return r.json();
#|    });
#|  }
#|  function fmtBytes(n) {
#|    if (n == null || n <= 0) return '—';
#|    if (n < 1024) return n + ' B';
#|    if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
#|    return (n / 1048576).toFixed(1) + ' MB';
#|  }
#|  function fmtMs(n) {
#|    if (n == null || n <= 0) return '—';
#|    return n < 1000 ? n + ' ms' : (n / 1000).toFixed(1) + ' s';
#|  }
#|  function nameOf(p) {
#|    return p ? p.split('/').pop() : '';
#|  }
#|
#|  function refreshReports() {
#|    return api('/api/reports').then(function (data) {
#|      var sel = document.getElementById('report-select');
#|      /* 兼容两种返回：{reports:[...]} 或纯数组 [...] */
#|      var names = (data && data.reports) ? data.reports : (Array.isArray(data) ? data : []);
#|      sel.innerHTML = '';
#|      if (names.length === 0) {
#|        sel.innerHTML = '<option value="">（目录下没有 .json 报告，先运行 moonhive survey --json reports/xxx.json …）</option>';
#|        return;
#|      }
#|      names.forEach(function (n) {
#|        var o = document.createElement('option');
#|        o.value = n;
#|        o.textContent = n;
#|        sel.appendChild(o);
#|      });
#|      sel.value = names[0];
#|      return loadReport(names[0]);
#|    });
#|  }
#|
#|  function loadReport(name) {
#|    return api('/api/report/' + encodeURIComponent(name)).then(function (data) {
#|      state.report = data;
#|      state.filter = null;
#|      state.sortKey = 'slug';
#|      state.sortAsc = true;
#|      render();
#|    }).catch(function (e) {
#|      document.getElementById('empty').style.display = 'block';
#|      document.getElementById('empty').textContent = '加载失败：' + e.message;
#|    });
#|  }
#|
#|  function render() {
#|    var m = state.report;
#|    if (!m) return;
#|    document.getElementById('env').innerHTML =
#|      '<div><strong>验证环境</strong>（结论只在此环境下成立）</div>' +
#|      '<div>MoonBit 工具链：<code>' + esc(m.toolchain) + '</code></div>' +
#|      '<div>目标后端：<code>' + esc(m.target) + '</code></div>' +
#|      '<div>生成时间戳（毫秒）：<code>' + esc(m.generatedAt) + '</code></div>';
#|    var rows = m.results || [];
#|    var usable = (m.summary && m.summary.usable != null) ? m.summary.usable : 0;
#|    var ratio = (m.summary && m.summary.usableRatio) ? m.summary.usableRatio : '0.0%';
#|    var lines = (m.summary && m.summary.totalSourceLines) ? m.summary.totalSourceLines : 0;
#|    document.getElementById('stats').innerHTML =
#|      statCard(rows.length, '验证总数') + statCard(usable, '可直接使用') +
#|      statCard(ratio, '可用率') + statCard(lines, '源码总行数');
#|    renderChips(rows);
#|    renderRows(rows);
#|  }
#|
#|  function statCard(n, l) {
#|    return '<div class="stat"><div class="n">' + esc(n) + '</div><div class="l">' + esc(l) + '</div></div>';
#|  }
#|
#|  function renderChips(rows) {
#|    var counts = {};
#|    rows.forEach(function (r) { counts[r.diagnosis] = (counts[r.diagnosis] || 0) + 1; });
#|    var names = Object.keys(counts).sort();
#|    var box = document.getElementById('chips');
#|    var html = '<span class="chip' + (state.filter === null ? ' on' : '') + '" data-d="__all__">全部 (' + rows.length + ')</span>';
#|    names.forEach(function (d) {
#|      var info = DIAG[d] || { cls: 'other', mark: '' };
#|      html += '<span class="chip' + (state.filter === d ? ' on' : '') + '" data-d="' + esc(d) + '">' +
#|        info.mark + ' ' + esc(d) + ' (' + counts[d] + ')</span>';
#|    });
#|    box.innerHTML = html;
#|  }
#|
#|  function sortedRows(rows) {
#|    var arr = rows.slice();
#|    var k = state.sortKey, asc = state.sortAsc ? 1 : -1;
#|    arr.sort(function (a, b) {
#|      var va = a[k], vb = b[k];
#|      if (k === 'slug' || k === 'diagnosis') {
#|        va = String(va == null ? '' : va);
#|        vb = String(vb == null ? '' : vb);
#|        return va < vb ? -asc : (va > vb ? asc : 0);
#|      }
#|      va = va == null ? 0 : va;
#|      vb = vb == null ? 0 : vb;
#|      return (va - vb) * asc;
#|    });
#|    return arr;
#|  }
#|
#|  function renderRows(rows) {
#|    var view = state.filter ? rows.filter(function (r) { return r.diagnosis === state.filter; }) : rows;
#|    view = sortedRows(view);
#|    document.getElementById('count').textContent = '(' + view.length + '/' + rows.length + ')';
#|    var tb = document.getElementById('tbody');
#|    if (view.length === 0) {
#|      document.getElementById('empty').style.display = 'block';
#|      tb.innerHTML = '';
#|      return;
#|    }
#|    document.getElementById('empty').style.display = 'none';
#|    var html = '';
#|    view.forEach(function (r) {
#|      var info = DIAG[r.diagnosis] || { cls: 'other', mark: '' };
#|      var size = r.fetched ? (r.mbtFiles + ' 文件 / ' + r.sourceLines + ' 行') : '—';
#|      var time = r.fetched ? ('check ' + fmtMs(r.checkMs) + (r.testMs > 0 ? ' / test ' + fmtMs(r.testMs) : '')) : '—';
#|      var ev = r.evidence ? esc(r.evidence) : '—';
#|      html += '<tr data-slug="' + esc(r.slug) + '">' +
#|        '<td class="slug"><code>' + esc(r.slug) + '</code></td>' +
#|        '<td class="' + info.cls + '">' + info.mark + ' <code>' + esc(r.diagnosis) + '</code></td>' +
#|        '<td>' + esc(size) + '</td><td>' + esc(time) + '</td>' +
#|        '<td><span class="ev">' + ev + '</span>' +
#|        '<div class="row-detail" id="d-' + esc(r.slug.replace(/[^A-Za-z0-9_-]/g, '_')) + '">' +
#|        '<div><strong>说明：</strong>' + esc(r.explain) + '</div>' +
#|        '<div><strong>证据：</strong>' + ev + '</div></div></td></tr>';
#|    });
#|    tb.innerHTML = html;
#|  }
#|
#|  function init() {
#|    document.getElementById('report-select').addEventListener('change', function () {
#|      if (this.value) loadReport(this.value);
#|    });
#|    document.getElementById('refresh').addEventListener('click', function () {
#|      var sel = document.getElementById('report-select');
#|      if (sel.value) loadReport(sel.value); else refreshReports();
#|    });
#|    document.getElementById('chips').addEventListener('click', function (e) {
#|      var el = e.target;
#|      if (!el.classList || !el.classList.contains('chip')) return;
#|      var d = el.getAttribute('data-d');
#|      state.filter = (d === '__all__') ? null : d;
#|      renderChips((state.report && state.report.results) || []);
#|      renderRows((state.report && state.report.results) || []);
#|    });
#|    document.querySelectorAll('th[data-key]').forEach(function (th) {
#|      th.addEventListener('click', function () {
#|        var k = th.getAttribute('data-key');
#|        if (state.sortKey === k) state.sortAsc = !state.sortAsc;
#|        else { state.sortKey = k; state.sortAsc = true; }
#|        renderRows((state.report && state.report.results) || []);
#|      });
#|    });
#|    refreshReports().catch(function (e) {
#|      document.getElementById('empty').style.display = 'block';
#|      document.getElementById('empty').textContent = '连接失败：' + e.message + '（确认已运行 moonhive serve）';
#|    });
#|  }
#|  document.addEventListener('DOMContentLoaded', init);
#|})();
#|</script>
#|</body>
#|</html>
  t
}
