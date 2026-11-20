// dsh-crystal 宿主半侧：给浏览器面板提供只读状态与受校验的开关写入。
// 真实能力全在 PowerShell/计划任务里；这里只做窄接口：
//   GET  /dsh-crystal/status      → doctor 只读摘要 + 开关快照
//   GET  /dsh-crystal/config      → crystal.json 的开关子集（只读）
//   POST /dsh-crystal/config      → 校验后写回（仅白名单键，先备份+留痕）
//   POST /dsh-crystal/doctor      → 跑 doctor -Auto 并返回末行
//   POST /dsh-crystal/backup      → 跑 crystal-backup.ps1 并返回末行
//   GET  /dsh-crystal/snapshots   → rollback.ps1 -List 摘要
//   POST /dsh-crystal/rollback-dryrun → rollback.ps1 -DryRun 摘要（真回滚仍走 CLI）
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const NS = 'dsh-crystal';
const ROUTE = '/dsh-crystal';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PLUGIN_HOME = path.dirname(__dirname);
const CRYSTAL_JSON = path.join(PLUGIN_HOME, 'crystal.json');
const DATA_HOME = 'F:\\crystal'; // 缺省；优先读 crystal.json paths（下同）

let dataHome = DATA_HOME;
try {
  const cj = JSON.parse(fs.readFileSync(CRYSTAL_JSON, 'utf8'));
  // [fix-20261120-11] 优先 paths.dataHome（crystal.json 明写的那个），再退 queue 的上两级；
  // 旧写法只认 queue，算出来是 F:\crystal，和脚本真正落盘的目录对不上。
  if (typeof cj?.paths?.dataHome === 'string') dataHome = cj.paths.dataHome;
  else {
    const q = cj?.paths?.queue;
    if (q && typeof q === 'string') dataHome = path.dirname(path.dirname(q));
  }
} catch { /* 保持缺省 */ }

function sendJson(res, code, payload) {
  const body = Buffer.from(JSON.stringify(payload), 'utf8');
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': String(body.length)
  });
  res.end(body);
}

function rejected(ctx, req, res) {
  try {
    const conn = (typeof ctx.get === 'function' ? ctx.get('connection') : undefined) || ctx.connection;
    if (!conn || typeof conn.requestRejection !== 'function') return false;
    const code = conn.requestRejection(req);
    if (code === undefined || code === null || code === false) return false;
    sendJson(res, typeof code === 'number' ? code : 403, { ok: false, error: 'request rejected', status: typeof code === 'number' ? code : 403 });
    return true;
  } catch { return false; }
}

function runPs(args, quiet) {
  return new Promise((resolve) => {
    execFile('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', ...args,
      ...(quiet ? ['-Quiet'] : [])
    ], { timeout: 180000, windowsHide: true, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) => {
      resolve({ code: err && typeof err.code === 'number' ? err.code : 0, stdout: String(stdout || '').trim(), stderr: String(stderr || '').trim() });
    });
  });
}

function readCrystal() {
  const cj = JSON.parse(fs.readFileSync(CRYSTAL_JSON, 'utf8'));
  return cj;
}

function writeCrystal(cj) {
  // 无 BOM、UTF-8、2 空格缩进（crystal.json 全 JSON 属 PS5.1 宽松 JSON）
  const txt = JSON.stringify(cj, null, 2) + '\n';
  fs.writeFileSync(CRYSTAL_JSON, Buffer.from(txt, 'utf8'));
  // 面板编辑留痕（不写 alerts.log，避免污染体检；单独一条 jsonl）
  const trace = path.join(dataHome, 'data', 'panel-edits.jsonl');
  try {
    fs.appendFileSync(trace, JSON.stringify({ at: new Date().toISOString(), editedBy: 'panel' }) + '\n', 'utf8');
  } catch { /* 留痕失败不拦主流程 */ }
}

// 允许面板改的白名单键（按路径模式匹配，写回前逐项校验）
function getPath(o, p) {
  try {
    let cur = o;
    for (const k of p) cur = cur == null ? undefined : cur[k];
    if (typeof cur === 'string') return cur;
    if (cur === undefined || cur === null) return cur;
    try { return JSON.stringify(cur); } catch { return String(cur); }
  } catch { return undefined; }
}
function matchEdit(path) {
  if (!Array.isArray(path)) return null;
  if (path.length === 4 && path[0] === 'rules' && ['chat', 'work'].includes(path[1]) && path[3] === 'enabled') return { kind: 'rule-toggle', group: path[1], id: path[2] };
  if (path.length === 4 && path[0] === 'rules' && ['chat', 'work'].includes(path[1]) && path[3] === 'text') return { kind: 'rule-text', group: path[1], id: path[2] };
  if (path.length === 2 && path[0] === 'rule-add' && ['chat', 'work'].includes(path[1])) return { kind: 'rule-add', group: path[1] };
  if (path.length === 3 && path[0] === 'rule-del' && ['chat', 'work'].includes(path[1])) return { kind: 'rule-del', group: path[1], id: path[2] };
  if (path.length === 3 && path[0] === 'plugins' && path[2] === 'demand') return { kind: 'plugin-demand', id: path[1] };
  if (path.length === 3 && path[0] === 'checks' && path[1] === 'budget' && path[2] === 'warnCnyDaily') return { kind: 'budget-line' };
  if (path.length === 3 && path[0] === 'checks' && path[1] === 'dailyPush' && path[2] === 'enabled') return { kind: 'daily-push' };
  if (path.length === 2 && path[0] === 'autonomy' && ['askDelete', 'askOutbound', 'askRoots', 'silentVerify'].includes(path[1])) return { kind: 'autonomy-bool' };
  if (path.length === 3 && path[0] === 'autonomy' && path[1] === 'reportMoney' && ['perTurn', 'daily'].includes(path[2])) return { kind: 'money-line' };
  if (path.length === 2 && path[0] === 'pet' && ['enabled', 'voice', 'greetingAm', 'greetingPm'].includes(path[1])) return { kind: 'pet-bool' };
  if (path.length === 2 && path[0] === 'pet' && path[1] === 'intervalMin') return { kind: 'pet-interval' };
  return null;
}

function applyPatch(cj, path, value, kind) {
  if (kind === 'rule-toggle') {
    if (typeof value !== 'boolean') return { ok: false, error: '开关必须是 true/false' };
    const group = (cj.rules || {})[path[1]];
    const rule = Array.isArray(group) ? group.find((r) => r.id === path[2]) : null;
    if (!rule) return { ok: false, error: '规则不存在：' + path[1] + '/' + path[2] };
    rule.enabled = value;
    return { ok: true };
  }
  if (kind === 'plugin-demand') {
    if (!['always', 'on-demand', 'off'].includes(String(value))) return { ok: false, error: '档位只允许 always/on-demand/off' };
    const p = (cj.plugins || []).find((x) => x.id === path[1]);
    if (!p) return { ok: false, error: '插件不存在：' + path[1] };
    p.demand = String(value);
    return { ok: true };
  }
  if (kind === 'budget-line') {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return { ok: false, error: '预算线必须是正数' };
    cj.checks = cj.checks || {};
    cj.checks.budget = cj.checks.budget || {};
    cj.checks.budget.warnCnyDaily = value;
    return { ok: true };
  }
  if (kind === 'daily-push') {
    if (typeof value !== 'boolean') return { ok: false, error: '开关必须是 true/false' };
    cj.checks = cj.checks || {};
    cj.checks.dailyPush = cj.checks.dailyPush || {};
    cj.checks.dailyPush.enabled = value;
    return { ok: true };
  }
  if (kind === 'rule-text') {
    if (typeof value !== 'string' || value.length === 0 || value.length > 240) return { ok: false, error: '规则文本 1-240 字' };
    const group = (cj.rules || {})[path[1]];
    const rText = Array.isArray(group) ? group.find((x) => x.id === path[2]) : null;
    if (!rText) return { ok: false, error: '规则不存在：' + path[1] + '/' + path[2] };
    rText.text = value;
    return { ok: true };
  }
  if (kind === 'rule-add') {
    if (!value || typeof value !== 'object') return { ok: false, error: '新增规则需 {text}' };
    if (typeof value.text !== 'string' || value.text.length === 0 || value.text.length > 240) return { ok: false, error: '规则文本 1-240 字' };
    const g = path[1];
    cj.rules = cj.rules || {};
    const grp = Array.isArray(cj.rules[g]) ? cj.rules[g] : [];
    cj.rules[g] = grp;
    if (grp.length >= 10) return { ok: false, error: g + ' 档 10 槽已满，先清掉一条再填' };
    const slot = grp.find((x) => !x.text);
    if (slot) { slot.text = value.text; slot.enabled = true; return { ok: true }; }
    grp.push({ id: g + (grp.length + 1), text: value.text, enabled: true });
    return { ok: true };
  }
  if (kind === 'rule-del') {
    const g = path[1];
    const grp = Array.isArray((cj.rules || {})[g]) ? cj.rules[g] : [];
    const target = grp.find((x) => x.id === path[2]);
    if (target) { target.text = ''; target.enabled = true; }
    return { ok: true };
  }
  if (kind === 'autonomy-bool') {
    if (typeof value !== 'boolean') return { ok: false, error: '开关必须是 true/false' };
    cj.autonomy = cj.autonomy || {};
    cj.autonomy[path[1]] = value;
    return { ok: true };
  }
  if (kind === 'money-line') {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return { ok: false, error: '金额必须是正数' };
    cj.autonomy = cj.autonomy || {};
    cj.autonomy.reportMoney = cj.autonomy.reportMoney || {};
    cj.autonomy.reportMoney[path[2]] = value;
    return { ok: true };
  }
  if (kind === 'pet-bool') {
    if (typeof value !== 'boolean') return { ok: false, error: '开关必须是 true/false' };
    cj.pet = cj.pet || {};
    cj.pet[path[1]] = value;
    return { ok: true };
  }
  if (kind === 'pet-interval') {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 1 || value > 240) return { ok: false, error: '间隔必须是 1-240 分钟' };
    cj.pet = cj.pet || {};
    cj.pet.intervalMin = value;
    return { ok: true };
  }
  return { ok: false, error: '不支持的编辑路径' };
}

export function apply(ctx) {
  let webServer;
  try { webServer = typeof ctx.get === 'function' ? ctx.get('webServer') : undefined; } catch { /* 忽略 */ }
  webServer = webServer || ctx.webServer;
  if (!webServer || typeof webServer.register !== 'function') {
    ctx.logger?.warn?.(`[${NS}] 没有可用的 webServer，设置面板不可用`);
    return;
  }

  const disposers = [];
  const wrap = (route) => Object.assign({}, route, {
    handler: async (req, res) => {
      try {
        if (rejected(ctx, req, res)) return;
        await route.handler(req, res);
      } catch (err) {
        try {
          if (!res.headersSent) sendJson(res, 500, { ok: false, error: String((err && err.message) || err) });
          else res.end();
        } catch { try { res.end(); } catch { /* 忽略 */ } }
      }
    }
  });

  const pluginHome = PLUGIN_HOME;
  const doctorPath = path.join(pluginHome, 'scripts', 'doctor.ps1');
  const backupPath = path.join(pluginHome, 'scripts', 'crystal-backup.ps1');
  const rollbackPath = path.join(pluginHome, 'scripts', 'rollback.ps1');
  const buildPath = path.join(pluginHome, 'scripts', 'crystal-build.ps1');
  const abilityPath = path.join(pluginHome, 'scripts', 'crystal-ability.ps1');
  const costPath = path.join(pluginHome, 'scripts', 'crystal-cost.ps1');
  const billPath = path.join(pluginHome, 'scripts', 'crystal-bill.ps1');
  const duesPath = path.join(pluginHome, 'scripts', 'crystal-dues.ps1');
  const fortunePath = path.join(pluginHome, 'scripts', 'crystal-fortune.ps1');
  const interceptsPath = path.join(pluginHome, 'scripts', 'crystal-intercepts.ps1');
  const keywordsPath = path.join(pluginHome, 'scripts', 'crystal-keywords.ps1');
  const timelinePath = path.join(pluginHome, 'scripts', 'crystal-timeline.ps1');
  const memPath = path.join(pluginHome, 'scripts', 'crystal-mem.ps1');
  const upgradePath = path.join(pluginHome, 'scripts', 'crystal-upgrade.ps1');
  const endpointsPath = path.join(pluginHome, 'scripts', 'crystal-endpoints.ps1');
  const petPath = path.join(pluginHome, 'scripts', 'crystal-pet.ps1');

  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/status',
    handler: async (req, res) => {
      const r = await runPs([doctorPath], false);
      // [fix-20261120-3] 抓红黄绿灰：只依赖数字与斜杠，不依赖中文（PS 输出编码可能是 GBK，中文会乱码）
      const sumRe = /doctor:\s*(\d+)[^\d/]*\/\s*(\d+)[^\d/]*\/\s*(\d+)[^\d/]*\/\s*(\d+)/;
      const m = sumRe.exec(r.stdout + '\n' + r.stderr);
      const pricing = /\[PRICING\][^\r\n]*/.exec(r.stdout + '\n' + r.stderr);
      sendJson(res, 200, {
        ok: true,
        red: m ? Number(m[1]) : null, yellow: m ? Number(m[2]) : null,
        green: m ? Number(m[3]) : null, gray: m ? Number(m[4]) : null,
        pricing: pricing ? pricing[0] : '',
        exit: r.code
      });
    }
  })));

  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/config',
    handler: async (req, res) => {
      if (req.method === 'POST') {
        const chunks = [];
        for await (const c of req) chunks.push(c);
        let body = {};
        try { body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch { sendJson(res, 400, { ok: false, error: 'JSON 解析失败' }); return; }
        const dryRun = body.dryRun === true;
        const cj = readCrystal();
        // expectVersion 校验：版本不符 409（防覆盖别人刚改的配置）
        if (body.expectVersion !== undefined && body.expectVersion !== null && String(body.expectVersion) !== String(cj?.writtenAt || '')) {
          sendJson(res, 409, { ok: false, error: '配置刚被改过，请刷新后重试', expectVersion: body.expectVersion, actual: cj?.writtenAt || '' });
          return;
        }
        const list = Array.isArray(body.patches) ? body.patches : (Array.isArray(body.edits) ? body.edits : []);
        let bak = null;
        if (!dryRun) {
          // 备份（先备份再动，铁律）
          bak = CRYSTAL_JSON + '.bak-panel-' + new Date().toISOString().replace(/[:.]/g, '-');
          try { fs.copyFileSync(CRYSTAL_JSON, bak); } catch { sendJson(res, 500, { ok: false, error: '备份失败，未改动' }); return; }
        }
        const edits = [];
        const applied = [];
        const diff = [];
        for (const e of list) {
          const hit = matchEdit(e.path);
          if (!hit) { edits.push({ ok: false, error: '键不在白名单：' + JSON.stringify(e.path) }); continue; }
          const before = getPath(cj, e.path);
          const r = applyPatch(cj, e.path, e.value, hit.kind);
          const after = getPath(cj, e.path);
          edits.push({ ok: r.ok, error: r.error || '', path: e.path, before, after });
          if (r.ok) {
            applied.push({ path: e.path, value: e.value });
            diff.push({ path: e.path, before, after });
          }
        }
        if (!dryRun && applied.length) writeCrystal(cj);
        try { fs.appendFileSync(trace, JSON.stringify({ at: new Date().toISOString(), editedBy: 'panel', dryRun, expectVersion: body.expectVersion ?? null, diff }) + '\n', 'utf8'); } catch { }
        sendJson(res, 200, { ok: true, dryRun, backup: bak, edits, diff, applied: applied.length });
        return;
      }
      const cj = readCrystal();
      const rulesObj = cj.rules || {};
      const mapGroup = (g) => (Array.isArray(rulesObj[g]) ? rulesObj[g].map((r) => ({ id: r.id, enabled: r.enabled !== false, text: String(r.text || '') })) : []);
      sendJson(res, 200, {
        ok: true,
        rules: { chat: mapGroup('chat'), work: mapGroup('work') },
        budgetWarnCnyDaily: cj?.checks?.budget?.warnCnyDaily ?? 12,
        dailyPush: cj?.checks?.dailyPush?.enabled !== false,
        autonomy: {
          askDelete: cj?.autonomy?.askDelete !== false,
          askOutbound: cj?.autonomy?.askOutbound !== false,
          askRoots: cj?.autonomy?.askRoots !== false,
          silentVerify: cj?.autonomy?.silentVerify !== false,
          reportMoney: {
            perTurn: cj?.autonomy?.reportMoney?.perTurn ?? 3,
            daily: cj?.autonomy?.reportMoney?.daily ?? 12
          }
        },
        pet: {
          enabled: cj?.pet?.enabled === true,
          voice: cj?.pet?.voice !== false,
          intervalMin: cj?.pet?.intervalMin ?? 15,
          greetingAm: cj?.pet?.greetingAm !== false,
          greetingPm: cj?.pet?.greetingPm !== false
        },
        plugins: (cj.plugins || []).map((p) => ({ id: p.id, demand: p.demand || 'on-demand' }))
      });
    }
  })));

  // GET /dsh-crystal/overview —— 面板一屏看全：体检明细/规则全文/插件台账/管家数据（全只读）
  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/overview',
    handler: async (req, res) => {
      const cj = readCrystal();
      const paths = cj.paths || {};
      const alertsLog = paths.alerts || path.join(PLUGIN_HOME, 'data', 'crystal', 'alerts.log');
      const dsFile = path.join(PLUGIN_HOME, 'data', 'crystal', 'doctor-state.json');
      const usageFile = paths.usage || path.join(dataHome, 'usage.jsonl');
      const duesFile = paths.dues || path.join(dataHome, 'dues.json');
      const intFile = paths.intercepts || path.join(dataHome, 'intercepts.jsonl');
      const epFile = paths.endpoints || path.join(dataHome, 'endpoints.json');
      const capFile = paths.capability || path.join(dataHome, 'plugin-capability.json');
      const out = { ok: true };

      // 体检明细：alerts.log 最近的检查行，按 fault 取最新状态
      out.checks = [];
      out.state = {};
      try {
        const st = JSON.parse(fs.readFileSync(dsFile, 'utf8'));
        out.state = { lastGreenAt: st?.lastGreenAt || '', lastRedAt: st?.lastRedAt || '', lastChecked: st?.lastChecked || '' };
      } catch { }
      try {
        const lines = fs.readFileSync(alertsLog, 'utf8').split(/\r?\n/).slice(-600);
        const seen = new Map();
        for (const ln of lines) {
          const m = /^\[(GREEN|YELLOW|RED|GRAY)\]\s+(\S+ \S+)\s+module=(\S+)\s+fault=(\S+)\s+msg=(.*)$/.exec(ln);
          if (!m) continue;
          seen.set(m[4], { fault: m[4], module: m[3], status: m[1].toLowerCase(), at: m[2], msg: (m[5] || '').replace(/ 上次红：.*$/, '') });
        }
        out.checks = Array.from(seen.values()).sort((a, b) => (a.fault < b.fault ? -1 : 1));
      } catch { }

      // 规则全文 + 开关子集（chat/work 各 10 槽）
      const rrObj = cj.rules || {};
      const mg = (g) => (Array.isArray(rrObj[g]) ? rrObj[g].map((r) => ({ id: r.id, enabled: r.enabled !== false, text: String(r.text || '') })) : []);
      out.rules = { chat: mg('chat'), work: mg('work') };
      // 全部能力台账（跑一次走 /action itemId）
      try {
        const abj = JSON.parse(fs.readFileSync(path.join(pluginHome, 'data', 'crystal', 'ability.json'), 'utf8'));
        out.ability = {
          generatedAt: abj.generatedAt,
          counts: abj.counts || {},
          items: (abj.items || []).map((it) => ({ id: it.id, group: it.group, name: it.name, desc: it.desc, kind: (it.run || {}).kind, cmd: (it.run || {}).cmd }))
        };
      } catch { out.ability = { items: [] }; }
      // [fix-20261120-12] 台账「上次跑过没」：runs.json 并入每条能力
      try {
        const rj = JSON.parse(fs.readFileSync(path.join(pluginHome, 'data', 'crystal', 'runs.json'), 'utf8')) || {};
        (out.ability.items || []).forEach((it) => { const r = rj[it.id]; if (r) { it.lastRunAt = r.at; it.runCount = r.n; } });
      } catch { }
      out.autonomy = {
        askDelete: cj?.autonomy?.askDelete !== false, askOutbound: cj?.autonomy?.askOutbound !== false,
        askRoots: cj?.autonomy?.askRoots !== false, silentVerify: cj?.autonomy?.silentVerify !== false,
        perTurn: cj?.autonomy?.reportMoney?.perTurn ?? 3, daily: cj?.autonomy?.reportMoney?.daily ?? 12
      };
      out.pet = { enabled: cj?.pet?.enabled === true, voice: cj?.pet?.voice !== false, intervalMin: cj?.pet?.intervalMin ?? 15 };
      out.budgetWarnCnyDaily = cj?.checks?.budget?.warnCnyDaily ?? 12;
      out.dailyPush = cj?.checks?.dailyPush?.enabled !== false;

      // [fix-20261120-1] 模式与档位：读桥写的 state\work-mode.json，给出「当前档 + 判定词 + 双档限制 + 生效范围」
      out.mode = { mode: 'chat', source: 'none', keys: [], triggers: {}, tools: {}, inject: {}, scope: '', expireNote: '' };
      try {
        const bridgeState = cj?.paths?.bridgeHome ? path.join(cj.paths.bridgeHome, 'state') : '';
        const wmFile = bridgeState ? path.join(bridgeState, 'work-mode.json') : '';
        const table = wmFile ? (JSON.parse(fs.readFileSync(wmFile, 'utf8')) || {}) : {};
        const fresh = (at) => Number(at) > 0 && Number(at) < 4102444800000;
        const keys = Object.entries(table)
          .filter(([, v]) => fresh(v && v.at))
          .map(([k, v]) => ({ key: k, at: new Date(Number(v.at)).toISOString().slice(0, 19).replace('T', ' '), tool: (v && v.tool) || '' }));
        const isWork = keys.length > 0;
        const injOf = (g) => (Array.isArray(cj?.modes?.[g]?.inject) ? cj.modes[g].inject.map((e) => (e && (e.file || e.kind)) || '') : []);
        out.mode = {
          mode: isWork ? 'work' : 'chat',
          source: isWork ? (keys[0] && keys[0].tool) || 'stamp' : 'none',
          keys,
          workModeFile: wmFile,
          triggers: {
            work: { head: (cj?.triggers?.work?.head || []), denyAfter: (cj?.triggers?.work?.denyAfter || []) },
            chat: { head: (cj?.triggers?.chat?.head || []), denyAfter: (cj?.triggers?.chat?.denyAfter || []) }
          },
          tools: {
            chatAllowExact: (cj?.modes?.chat?.tools?.chatOnlyExact || []),
            workDenyExact: (cj?.modes?.work?.tools?.denyExact || [])
          },
          inject: { chat: injOf('chat'), work: injOf('work') },
          scope: '桥按 QQ 原话判档、写进 state\\work-mode.json；插件读它决定注入哪套规则卡、拦哪些工具。DSH 整机所有会话共用同一份状态，QQ 只是切换入口。',
          expireNote: '不按时间过期：只有说「聊天模式」才把戳清零；说「工作」立即可动。'
        };
      } catch (e) {
        out.mode.error = String((e && e.message) || e);
      }

      // 插件台账：总表 plugins + 能力地图用途
      out.plugins = [];
      try {
        const cap = JSON.parse(fs.readFileSync(capFile, 'utf8'));
        const byName = new Map();
        for (const e of (cap?.entries || [])) {
          const nm = String(e?.plugin || e?.id || '').toLowerCase();
          if (nm) byName.set(nm, String((e?.tasks && e.tasks[0]) || e?.summary || ''));
        }
        out.plugins = (cj.plugins || []).map((p) => ({
          id: p.id, demand: p.demand || 'on-demand',
          use: byName.get(String(p.name || p.id || '').toLowerCase()) || String(p.note || '')
        }));
      } catch { out.plugins = (cj.plugins || []).map((p) => ({ id: p.id, demand: p.demand || 'on-demand', use: String(p.note || '') })); }

      // 缺失插件检测（主人 m06283「人家电脑没有这些插件的时候怎么办」）：能力地图里有、bundles 里没有的 = 缺失
      out.missingPlugins = [];
      try {
        const profHome = paths.profileHome || path.join(process.env.USERPROFILE || process.env.HOME || '.', '.dsh', 'profiles', 'desktop');
        const pkg = JSON.parse(fs.readFileSync(path.join(profHome, 'package.json'), 'utf8'));
        const installed = new Set(((pkg && pkg.dsh && pkg.dsh.profile && pkg.dsh.profile.bundles) || []).map((s) => String(s).toLowerCase()));
        const cap = JSON.parse(fs.readFileSync(capFile, 'utf8'));
        for (const e of (cap?.entries || [])) {
          const nm = String(e?.plugin || e?.id || '').toLowerCase();
          if (!nm || installed.has(nm)) continue;
          out.missingPlugins.push({
            plugin: String(e?.plugin || e?.id || ''),
            use: String((e?.tasks && e.tasks[0]) || e?.summary || ''),
            hint: 'DSH 插件市场搜「' + String(e?.plugin || '') + '」安装，或命令行：dsh plugin --profile desktop add <包名>'
          });
        }
      } catch { }

      // 管家数据：今日用量 + 欠债 + 拦截账 + 端点
      out.usage = { rows: 0, okRows: 0, inputTokens: 0, outputTokens: 0, lastBridgeStart: '' };
      try {
        const d0 = new Date(); d0.setHours(0, 0, 0, 0);
        for (const ln of fs.readFileSync(usageFile, 'utf8').split(/\r?\n/)) {
          if (!ln) continue;
          try {
            const r = JSON.parse(ln);
            if (r?.module === 'bridge-start') out.usage.lastBridgeStart = r.ts || '';
            const t = new Date(r?.ts || 0);
            if (Number.isFinite(t.getTime()) && t >= d0 && r?.module === 'ds-chat') {
              out.usage.rows++; if (r.ok) out.usage.okRows++;
              out.usage.inputTokens += Number(r.inputTokens || 0);
              out.usage.outputTokens += Number(r.outputTokens || 0);
            }
          } catch { }
        }
      } catch { }
      out.dues = { pending: 0, overdue: 0, lines: [] };
      try {
        const du = JSON.parse(fs.readFileSync(duesFile, 'utf8'));
        out.dues = { pending: Number(du?.pending || 0), overdue: Number(du?.overdue || 0), lines: Array.isArray(du?.lines) ? du.lines.slice(0, 5) : [] };
      } catch { }
      out.intercepts = 0;
      try { out.intercepts = fs.readFileSync(intFile, 'utf8').split(/\r?\n/).filter(Boolean).length; } catch { }
      out.endpoints = { guiPort: null, mismatch: null };
      try {
        const ep = JSON.parse(fs.readFileSync(epFile, 'utf8'));
        out.endpoints = { guiPort: ep?.gui?.port ?? null, bridgeBaseUrl: ep?.bridgeBaseUrl ?? '', mismatch: ep?.mismatch ?? null, onebot3000: ep?.onebot?.http3000 ?? null, onebot3001: ep?.onebot?.ws3001 ?? null };
      } catch { }

      // 命令速查（与 crystal.ps1 usage 行同步）
      out.verbs = [
        ['status', '家底一眼看完（红黄绿灰+账本+队列+快照+花费）'],
        ['doctor', '22 项体检（-Auto 自动修小毛病）'],
        ['check', '总表/六处标记/三锁配置/端口 四检只读'],
        ['bill', '按插件分账汇总（只汇总不改账）'],
        ['dues', '欠债清单（待办里没做完的）'],
        ['fortune', '今日黄历（宜/忌 + 体检彩头）'],
        ['intercepts', '拦截账（谁乱动手被挡了）'],
        ['plugins', '插件三源对账（目录/依赖/bundles/总表）'],
        ['keywords', '关键词→插件接管表'],
        ['pluginctl', '插件开关台账（temp/off/soft-off 等）'],
        ['receipts', '已读凭证（读过谁的消息）'],
        ['backup', '一键备份到 F:\\备份\\现行-*'],
        ['rollback', '回滚（-List 看回滚点 / -DryRun 预演）'],
        ['timeline', '大事记（最近 20 件）'],
        ['upgrade', '升级参谋（五检：版本/快照/台账/备份/体检）'],
        ['pet', '桌宠（start 开窗 / stop 停 / status 看配置）'],
        ['count', '计数器（账本行数/队列/快照/花费）']
      ];
      // [fix-20261120-4] 能力台账里有 24 个动词时用它覆盖内置 17 条，面板速查和台账永远同源
      try {
        const ab = JSON.parse(fs.readFileSync(path.join(pluginHome, 'data', 'crystal', 'ability.json'), 'utf8'));
        const cliItems = (ab.items || []).filter((it) => it.group === '命令');
        if (cliItems.length) out.verbs = cliItems.map((it) => [String(it.id || '').replace(/^cli\./, ''), (it.name || it.desc || '').trim()]);
      } catch { }

      // [fix-20261120-9] 记忆三件数据：读 crystal-mem.ps1 的 3 天体检缓存 + 建议箱
      // [fix-20261120-11] 缓存文件有三个可能落点（插件 data / paths.dataHome / dataHome\crystal），
      // 旧写法只试一个，脚本写在插件 data 下就永远读到 0，面板显示「0 件 / 0KB」。
      out.memory = { checkedAt: '', windowDays: 3, files: 0, bytes: 0, active: 0, stale: 0, suggestions: 0, staleList: [] };
      try {
        const cands = [
          path.join(pluginHome, 'data', 'mem-check.json'),
          path.join(dataHome, 'mem-check.json'),
          path.join(dataHome, 'crystal', 'mem-check.json')
        ];
        const hit = cands.find((p) => { try { return fs.existsSync(p); } catch { return false; } });
        const mc = JSON.parse(fs.readFileSync(hit || cands[0], 'utf8'));
        out.memory = {
          checkedAt: mc?.checkedAt || '', windowDays: Number(mc?.windowDays || 3),
          files: Number(mc?.files || 0), bytes: Number(mc?.bytes || 0),
          active: Number(mc?.active || 0), stale: Number(mc?.stale || 0),
          suggestions: Number(mc?.suggestions || 0),
          staleList: Array.isArray(mc?.staleList) ? mc.staleList.slice(0, 8) : []
        };
      } catch { }

      sendJson(res, 200, out);
    }
  })));

  // ===== 交接包第一步：/ability /schema /detect /action /render-check =====
  const ABILITY_FILE = path.join(PLUGIN_HOME, 'data', 'crystal', 'ability.json');
  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/ability',
    handler: async (req, res) => {
      let ab = null;
      try { ab = JSON.parse(fs.readFileSync(ABILITY_FILE, 'utf8')); } catch { }
      sendJson(res, 200, { ok: true, ability: ab, hint: ab ? null : '跑一次 crystal ability 生成台账' });
    }
  })));
  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/schema',
    handler: async (req, res) => {
      const cj = readCrystal();
      sendJson(res, 200, {
        ok: true,
        rules: { shape: 'groups', groups: ['chat', 'work'], slotsPerGroup: 10 },
        pluginDemand: ['always', 'on-demand', 'off'],
        autonomyKeys: ['askDelete', 'askOutbound', 'askRoots', 'silentVerify', 'reportMoney.perTurn', 'reportMoney.daily'],
        petKeys: ['enabled', 'voice', 'intervalMin', 'greetingAm', 'greetingPm'],
        budgetKeys: ['warnTokensDaily', 'warnCnyDaily', 'rates.inputPerM', 'rates.outputPerM', 'rates.cacheReadPerM'],
        modePlugins: cj?.modePlugins || { work: [], chat: [] },
        writtenAt: cj?.writtenAt || ''
      });
    }
  })));
  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/detect',
    handler: async (req, res) => {
      const cj = readCrystal();
      const paths = cj.paths || {};
      const capFile = paths.capability || path.join(dataHome, 'plugin-capability.json');
      let caps = [];
      try { caps = JSON.parse(fs.readFileSync(capFile, 'utf8')).plugins || []; } catch { }
      let bundles = [];
      const profPkg = paths.profileHome ? path.join(paths.profileHome, 'package.json') : path.join(PLUGIN_HOME, '..', '..', '..', 'profiles', 'desktop', 'package.json');
      try {
        const pp = JSON.parse(fs.readFileSync(profPkg, 'utf8'));
        bundles = (pp?.dsh?.profile?.bundles || pp?.bundles || []);
      } catch { }
      const missing = caps.filter((c) => !bundles.includes(c.name) && !bundles.includes(c.id)).map((c) => ({ plugin: c.name || c.id, use: c.use || '', hint: (c.tasks || []).slice(0, 3).join('、') }));
      sendJson(res, 200, {
        ok: true,
        env: {
          powershell: fs.existsSync('C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'),
          node: fs.existsSync('F:\\新建文件夹\\resources\\runtime\\node.exe') || process.execPath,
          pluginHome: PLUGIN_HOME,
          dataHome
        },
        bundlesCount: bundles.length,
        missing
      });
    }
  })));
  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/action',
    method: 'POST',
    handler: async (req, res) => {
      const chunks = [];
      for await (const c of req) chunks.push(c);
      let body = {};
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch { sendJson(res, 400, { ok: false, error: 'JSON 解析失败' }); return; }
      const actId = String(body.id || body.itemId || '')
      const dry = !!body.dryRun
      // [fix-20261120-6] 面板真能切档（主人 #598 N-3）：写 state\work-mode.json 的 global 戳
      if (actId === 'set-mode') {
        try {
          const want = String(body.mode || '').toLowerCase() === 'work' ? 'work' : 'chat'
          const cjMode = readCrystal()
          const bridgeHome = (cjMode && cjMode.paths && cjMode.paths.bridgeHome) || 'F:\\qq-dsh-bridge\\qq-bridge'
          const wmFile = path.join(bridgeHome, 'state', 'work-mode.json')
          let table = {}
          try { table = JSON.parse(fs.readFileSync(wmFile, 'utf8')) || {} } catch { table = {} }
          const before = Object.keys(table).length
          if (!dry) { try { fs.copyFileSync(wmFile, wmFile + '.bak-' + new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)) } catch { } }
          if (want === 'work') table.global = { at: Date.now(), tool: 'panel' }
          else table = {}
          if (!dry) fs.writeFileSync(wmFile, JSON.stringify(table, null, 2), 'utf8')
          sendJson(res, 200, { ok: true, mode: want, file: wmFile, keysBefore: before, keysAfter: Object.keys(table).length, dryRun: !!dry })
          return
        } catch (err) {
          sendJson(res, 500, { ok: false, error: String((err && err.message) || err) })
          return
        }
      }

      const actions = {
        'doctor': [doctorPath],
        'doctor-auto': [doctorPath, '-Auto'],
        'backup': [backupPath],
        'snapshots': [rollbackPath, '-List'],
        'rollback-dryrun': [rollbackPath, '-DryRun'],
        'baseline': [buildPath, '-Baseline'],
        'check': [buildPath, '-Check'],
        'checkpatches': [buildPath, '-CheckPatches'],
        'ability': [abilityPath],
        'cost': [costPath],
        'bill': [billPath],
        'dues': [duesPath],
        'fortune': [fortunePath],
        'intercepts': [interceptsPath],
        'keywords': [keywordsPath],
        'timeline': [timelinePath],
        'upgrade': [upgradePath],
        'probe': [endpointsPath, '-Probe'],
        'pet-start': [petPath],
        'pet-stop': [petPath, 'stop'],
        'mem-check': [memPath, '-Verb', 'check'],
        'mem-month': [memPath, '-Verb', 'month'],
        'mem-inbox': [memPath, '-Verb', 'inbox'],
        'restart-bridge': [path.join(dataHome, '..', 'scripts', 'tmp-kill-bridge.ps1')]
      };
      let act = actions[String(body.id || '')];
      if (!act && body.itemId) {
        // 能力台账条目：按 run.cmd 的脚本名映射到白名单动作（白名单仍然封闭）
        try {
          const ab = JSON.parse(fs.readFileSync(path.join(pluginHome, 'data', 'crystal', 'ability.json'), 'utf8'));
          const it = (ab.items || []).find((x) => x.id === body.itemId);
          if (it && it.run && ['ps1', 'cli'].includes(it.run.kind)) {
            // [fix-20261120-10] 脚本名取 run.cmd 里 *.ps1 那段（首位是 powershell 不是脚本名，旧逻辑永远映射不上）
            const toks = String(it.run.cmd || '').trim().split(/\s+/);
            let scriptName = '';
            for (const t of toks) { if (/\.ps1$/i.test(t)) { scriptName = t.replace(/\.ps1$/i, ''); break; } }
            if (!scriptName) scriptName = toks[0].replace(/\.ps1$/i, '');
            scriptName = scriptName.split(/[\\/]/).pop();
            const mapped = {
              'doctor': 'doctor', 'crystal-backup': 'backup', 'rollback': 'snapshots',
              'crystal-build': 'check', 'crystal-cost': 'cost', 'crystal-bill': 'bill',
              'crystal-dues': 'dues', 'crystal-fortune': 'fortune', 'crystal-intercepts': 'intercepts',
              'crystal-keywords': 'keywords', 'crystal-timeline': 'timeline', 'crystal-upgrade': 'upgrade',
              'crystal-endpoints': 'probe', 'crystal-ability': 'ability', 'crystal-pet': 'pet-start',
              'crystal-mem': 'mem-check'
            };
            if (mapped[scriptName] && actions[mapped[scriptName]]) { act = actions[mapped[scriptName]]; }
            else if (it.id.indexOf('cli.') === 0) {
              // [fix-20261120-10] CLI 动词（cmd 尾段是动词）：白名单内才放行
              const verbMap = { 'doctor': 'doctor', 'backup': 'backup', 'rollback': 'snapshots', 'pet': 'pet-start', 'cost': 'cost', 'bill': 'bill', 'dues': 'dues', 'fortune': 'fortune', 'intercepts': 'intercepts', 'keywords': 'keywords', 'timeline': 'timeline', 'upgrade': 'upgrade', 'check': 'check', 'ability': 'ability', 'mem': 'mem-check' };
              const verb = toks[toks.length - 1];
              if (verbMap[verb] && actions[verbMap[verb]]) act = actions[verbMap[verb]];
            }
          }
        } catch { }
      }
      // [fix-20261120-13] 记账助手：能力台账「跑过没」统一入口（replay 分支也要记）
      const bumpRuns = (rid) => {
        try {
          const runsFile = path.join(pluginHome, 'data', 'crystal', 'runs.json');
          let runs = {};
          try { runs = JSON.parse(fs.readFileSync(runsFile, 'utf8')) || {}; } catch { }
          const k = String(rid || '');
          if (!k) return;
          runs[k] = { n: ((runs[k] && runs[k].n) || 0) + 1, at: new Date().toISOString() };
          fs.writeFileSync(runsFile, JSON.stringify(runs));
        } catch { }
      };
      // [fix-20261120-12] 一键复演：安全序列 doctor → set-mode work → chat → work（写盘前备份）
      if (actId === 'replay') {
        const steps = [];
        const note = (name, code, tail) => steps.push({ name, code, tail: String(tail || '').split(/\r?\n/).filter(Boolean).slice(-2).join(' | ') });
        try {
          const d = await runPs([doctorPath], true);
          note('doctor', d.code, (d.stdout || d.stderr || ''));
        } catch (e) { note('doctor', -1, String(e && e.message || e)); }
        try {
          const cjMode = readCrystal();
          const bridgeHome = (cjMode && cjMode.paths && cjMode.paths.bridgeHome) || 'F:\\qq-dsh-bridge\\qq-bridge';
          const wmFile = path.join(bridgeHome, 'state', 'work-mode.json');
          let table = {};
          try { table = JSON.parse(fs.readFileSync(wmFile, 'utf8')) || {}; } catch { table = {}; }
          fs.copyFileSync(wmFile, wmFile + '.bak-replay-' + Date.now());
          const stamp = { at: Date.now(), tool: 'panel' };
          let okChain = true;
          for (const m of ['work', 'chat', 'work']) {
            if (m === 'work') { table.global = stamp; } else { table = {}; }
            fs.writeFileSync(wmFile, JSON.stringify(table));
          }
          note('set-mode', okChain ? 0 : -1, 'work→chat→work');
          bumpRuns('set-mode');
        } catch (e) { note('set-mode', -1, String(e && e.message || e)); }
        bumpRuns('doctor');
        bumpRuns('replay');
        sendJson(res, 200, { ok: steps.every((s) => s.code === 0), steps });
        return;
      }
      if (!act) { sendJson(res, 400, { ok: false, error: '动作不在白名单：' + String(body.id || body.itemId || '') }); return; }
      const r = await runPs(act, true);
      // [fix-20261120-12] 跑过一次就记账（runs.json：id → {n, at}）
      bumpRuns(String(body.id || body.itemId || ''));
      sendJson(res, 200, { ok: r.code === 0, exit: r.code, tail: String(r.stdout || r.stderr || '').trim().split(/\r?\n/).filter(Boolean).slice(-6).join('\n') });
    }
  })));
  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/ability/render-check',
    handler: async (req, res) => {
      let ab = null;
      try { ab = JSON.parse(fs.readFileSync(ABILITY_FILE, 'utf8')); } catch { }
      sendJson(res, 200, { ok: !!ab, generatedAt: ab?.generatedAt || null, counts: ab?.counts || null, items: ab?.items?.length || 0 });
    }
  })));

  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/doctor',
    method: 'POST',
    handler: async (req, res) => {
      const r = await runPs([doctorPath, '-Auto'], true);
      const m = /doctor:\s*(\d+)\s*未解决红\s*\/\s*(\d+)\s*黄\s*\/\s*(\d+)\s*绿\s*\/\s*(\d+)\s*灰/.exec(r.stdout + '\n' + r.stderr);
      sendJson(res, 200, { ok: true, exit: r.code, red: m ? Number(m[1]) : null, yellow: m ? Number(m[2]) : null, green: m ? Number(m[3]) : null, gray: m ? Number(m[4]) : null });
    }
  })));

  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/backup',
    method: 'POST',
    handler: async (req, res) => {
      const r = await runPs([backupPath], true);
      const last = r.stdout.split(/\r?\n/).filter(Boolean).pop() || '';
      sendJson(res, 200, { ok: true, exit: r.code, last });
    }
  })));

  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/snapshots',
    handler: async (req, res) => {
      const r = await runPs([rollbackPath, '-List'], true);
      sendJson(res, 200, { ok: true, exit: r.code, lines: r.stdout.split(/\r?\n/).filter(Boolean).slice(-12) });
    }
  })));

  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/rollback-dryrun',
    method: 'POST',
    handler: async (req, res) => {
      const r = await runPs([rollbackPath, '-DryRun'], true);
      const last = r.stdout.split(/\r?\n/).filter(Boolean).pop() || '';
      sendJson(res, 200, { ok: true, exit: r.code, last });
    }
  })));

  ctx.effect?.(() => () => { for (const d of disposers) { try { d?.(); } catch { /* 忽略 */ } } });
}

export const inject = ['webServer', 'connection'];

// 供本地自测（node 直接 import 断言白名单与补丁行为）
export { matchEdit, applyPatch, readCrystal };
