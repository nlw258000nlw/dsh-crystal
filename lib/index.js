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
  const q = cj?.paths?.queue;
  if (q && typeof q === 'string') dataHome = path.dirname(path.dirname(q));
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
function matchEdit(path) {
  if (!Array.isArray(path)) return null;
  if (path.length === 3 && path[0] === 'rules' && path[2] === 'enabled') return { kind: 'rule-toggle', id: path[1] };
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
    const rule = (cj.rules || []).find((r) => r.id === path[1]);
    if (!rule) return { ok: false, error: '规则不存在：' + path[1] };
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

  disposers.push(webServer.register(wrap({
    kind: 'exact', path: ROUTE + '/status',
    handler: async (req, res) => {
      const r = await runPs([doctorPath], true);
      // 抓 doctor 输出里的红黄绿灰汇总与 PRICING 行
      const sumRe = /doctor:\s*(\d+)\s*未解决红\s*\/\s*(\d+)\s*黄\s*\/\s*(\d+)\s*绿\s*\/\s*(\d+)\s*灰/;
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
        const cj = readCrystal();
        // 备份（先备份再动，铁律）
        const bak = CRYSTAL_JSON + '.bak-panel-' + new Date().toISOString().replace(/[:.]/g, '-');
        try { fs.copyFileSync(CRYSTAL_JSON, bak); } catch { sendJson(res, 500, { ok: false, error: '备份失败，未改动' }); return; }
        const edits = [];
        const applied = [];
        for (const e of (Array.isArray(body.edits) ? body.edits : [])) {
          const hit = matchEdit(e.path);
          if (!hit) { edits.push({ ok: false, error: '键不在白名单：' + JSON.stringify(e.path) }); continue; }
          const r = applyPatch(cj, e.path, e.value, hit.kind);
          edits.push({ ok: r.ok, error: r.error || '', path: e.path });
          if (r.ok) applied.push({ path: e.path, value: e.value });
        }
        if (applied.length) writeCrystal(cj);
        sendJson(res, 200, { ok: true, backup: bak, edits, applied: applied.length });
        return;
      }
      const cj = readCrystal();
      sendJson(res, 200, {
        ok: true,
        rules: (cj.rules || []).map((r) => ({ id: r.id, enabled: r.enabled !== false, text: r.text })),
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

      // 规则全文 + 开关子集
      out.rules = (cj.rules || []).map((r) => ({ id: r.id, enabled: r.enabled !== false, text: String(r.text || '') }));
      out.autonomy = {
        askDelete: cj?.autonomy?.askDelete !== false, askOutbound: cj?.autonomy?.askOutbound !== false,
        askRoots: cj?.autonomy?.askRoots !== false, silentVerify: cj?.autonomy?.silentVerify !== false,
        perTurn: cj?.autonomy?.reportMoney?.perTurn ?? 3, daily: cj?.autonomy?.reportMoney?.daily ?? 12
      };
      out.pet = { enabled: cj?.pet?.enabled === true, voice: cj?.pet?.voice !== false, intervalMin: cj?.pet?.intervalMin ?? 15 };
      out.budgetWarnCnyDaily = cj?.checks?.budget?.warnCnyDaily ?? 12;
      out.dailyPush = cj?.checks?.dailyPush?.enabled !== false;

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

      sendJson(res, 200, out);
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
