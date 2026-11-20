/* ============================================================================
 * dsh-crystal — 浏览器半侧：侧栏「结晶」面板（v2 全景版）
 * 总览卡 / 体检明细 / 规则全文 / 插件台账 / 管家数据 / 命令速查 / 设置开关
 * 手写 ModuleLoader bundle，不用构建；数据来自宿主路由 /dsh-crystal/*
 * ========================================================================== */
window.__ModuleLoader__.load({
  id: 'dsh-crystal',
  factory: (require) => {
    var module = { exports: {} }
    var exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })

    var react = require('react')
    var h = react.createElement
    var useState = react.useState
    var useEffect = react.useEffect

    var API = '/dsh-crystal'

    function fetchJson(url, opts) {
      return fetch(url, Object.assign({ cache: 'no-store' }, opts || {})).then(function (res) {
        return res.text().then(function (t) {
          var data = null
          try { data = t ? JSON.parse(t) : {} } catch (e) { throw new Error('返回不是 JSON（HTTP ' + res.status + '）：' + String(t).slice(0, 80)) }
          if (!res.ok) throw new Error((data && data.error) || ('HTTP ' + res.status))
          return data
        })
      })
    }

    var CSS = [
      '.cr-root{padding:14px 16px 22px;font-size:13px;color:#1f2328;line-height:1.5;height:100%;box-sizing:border-box;overflow-y:auto;max-width:760px;margin:0 auto}',
      '.cr-h1{font-size:17px;margin:0 0 2px;font-weight:700}',
      '.cr-sub{color:#888;font-size:12px;margin:0 0 12px}',
      '.cr-cards{display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap}',
      '.cr-card{flex:1;min-width:58px;border:1px solid #e4e8ee;border-radius:8px;padding:8px 6px;text-align:center;background:#fafbfd}',
      '.cr-num{font-size:20px;font-weight:700}',
      '.cr-red{color:#d33c3c}.cr-yellow{color:#c98a00}.cr-green{color:#1a9e4b}.cr-gray{color:#9aa3ad}',
      '.cr-chip{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;border:1px solid #e4e8ee;color:#666;margin-right:6px;background:#fff}',
      '.cr-chip.on{border-color:#1a9e4b;color:#1a9e4b;background:#eefaf2}',
      '.cr-chip.bad{border-color:#d33c3c;color:#d33c3c;background:#fdf0f0}',
      '.cr-sec{border:1px solid #e4e8ee;border-radius:10px;padding:10px 12px;margin-bottom:10px;background:#fff;transition:border-color .15s,box-shadow .15s}',
      '.cr-sec:hover{border-color:#bcd4f0;box-shadow:0 1px 6px rgba(60,110,180,.07)}',
      '.cr-sec summary{cursor:pointer;font-weight:700;outline:none}',
      '.cr-badge{display:inline-block;margin-left:6px;padding:0 6px;border-radius:9px;font-size:10px;line-height:16px;color:#8a6d3b;background:#fdf6e3;border:1px solid #f0e2b6}',
      '.cr-row{display:flex;align-items:center;gap:8px;padding:3px 0}',
      '.cr-row label{flex:1;cursor:pointer}',
      '.cr-msg{margin:8px 0;white-space:pre-wrap;font-family:ui-monospace,Consolas,monospace;font-size:12px;color:#666;max-height:120px;overflow:auto;background:#f6f8fa;border-radius:6px;padding:8px}',
      '.cr-note{color:#999;font-size:12px;margin-top:10px}',
      '.cr-btn{background:#2f6fed;color:#fff;border:none;border-radius:6px;padding:6px 12px;font-size:12px;cursor:pointer;margin-right:8px}',
      '.cr-btn:disabled{opacity:.5;cursor:not-allowed}',
      '.cr-check{border-top:1px solid #f0f2f5;padding:5px 0;font-size:12px;display:flex;gap:6px;align-items:baseline}',
      '.cr-dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex:0 0 8px;margin-top:5px}',
      '.cr-dot.green{background:#1a9e4b}.cr-dot.yellow{background:#e0a41c}.cr-dot.red{background:#d33c3c}.cr-dot.gray{background:#9aa3ad}',
      '.cr-check .id{font-family:ui-monospace,Consolas,monospace;flex:0 0 190px;color:#333}',
      '.cr-check .msg{color:#777;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
      '.cr-rule{border:1px solid #eef0f4;border-radius:8px;padding:8px 10px;margin-bottom:6px;background:#fcfdff}',
      '.cr-rule .head{font-weight:700;display:flex;align-items:center;gap:8px}',
      '.cr-rule .txt{white-space:pre-wrap;color:#555;margin-top:4px;font-size:12px}',
      '.cr-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:8px}',
      '.cr-pcard{border:1px solid #eef0f4;border-radius:8px;padding:8px;background:#fcfdff}',
      '.cr-pcard .pn{font-family:ui-monospace,Consolas,monospace;font-size:12px;font-weight:700;word-break:break-all}',
      '.cr-pcard .pu{color:#888;font-size:11px;margin:3px 0 5px;min-height:28px}',
      '.cr-pcard select{width:100%;font-size:11px;border:1px solid #e4e8ee;border-radius:5px;padding:2px}',
      '.cr-kv{display:flex;justify-content:space-between;padding:3px 0;font-size:12px;border-bottom:1px dashed #f0f2f5}',
      '.cr-kv b{font-weight:600}',
      '.cr-table{width:100%;border-collapse:collapse;font-size:12px}',
      '.cr-table td{padding:4px 6px;border-bottom:1px solid #f0f2f5}',
      '.cr-table td:first-child{font-family:ui-monospace,Consolas,monospace;color:#2f6fed;width:110px}'
    ].join('\n')

    function StatusCard(props) {
      return h('div', { className: 'cr-card' }, [
        h('div', { className: 'cr-num ' + props.cls }, String(props.value === null || props.value === undefined ? '—' : props.value)),
        h('div', { style: { fontSize: 12, color: '#888' } }, props.label)
      ])
    }

    function fmt(n) {
      if (n === null || n === undefined) return '—'
      if (n >= 1e9) return (n / 1e9).toFixed(2) + ' G'
      if (n >= 1e6) return (n / 1e6).toFixed(1) + ' M'
      if (n >= 1e3) return (n / 1e3).toFixed(1) + ' K'
      return String(n)
    }

    function Panel() {
      var status0 = { red: null, yellow: null, green: null, gray: null, pricing: '' }
      var config0 = {
        rules: { chat: [], work: [] }, plugins: [], budgetWarnCnyDaily: 12, dailyPush: true,
        autonomy: { askDelete: true, askOutbound: true, askRoots: true, silentVerify: true, perTurn: 3, daily: 12 },
        pet: { enabled: false, voice: true, intervalMin: 15 }
      }
      var ov0 = { checks: [], state: {}, usage: {}, dues: {}, endpoints: {}, intercepts: 0, verbs: [] }
      var sState = useState(status0)
      var cState = useState(config0)
      var oState = useState(ov0)
      var busyState = useState(false)
      var actBusyState = useState(false)
      var msgState = useState('')
      var status = sState[0], setStatus = sState[1]
      var config = cState[0], setConfig = cState[1]
      var ov = oState[0], setOv = oState[1]
      var busy = busyState[0], setBusy = busyState[1]
      var actBusy = actBusyState[0], setActBusy = actBusyState[1]
      var msg = msgState[0], setMsg = msgState[1]

      function refresh() {
        return fetchJson(API + '/status').then(function (d) { setStatus(d) }).catch(function (e) { setMsg('状态读取失败：' + e.message) })
      }
      function loadOverview() {
        return fetchJson(API + '/overview').then(function (d) {
          setOv(d)
          setConfig({
            rules: d.rules || { chat: [], work: [] }, plugins: d.plugins || [],
            budgetWarnCnyDaily: d.budgetWarnCnyDaily, dailyPush: d.dailyPush,
            autonomy: d.autonomy, pet: d.pet
          })
        }).catch(function (e) { setMsg('总览读取失败：' + e.message) })
      }
      useEffect(function () { refresh(); loadOverview() }, [])

      function act(path) {
        setActBusy(true); setMsg('')
        return fetchJson(API + path, { method: 'POST' }).then(function (d) {
          setMsg(d.last || ('exit=' + d.exit + ' 红' + d.red + ' 黄' + d.yellow + ' 绿' + d.green + ' 灰' + d.gray))
          return refresh()
        }).catch(function (e) { setMsg('失败：' + e.message) }).finally(function () { setActBusy(false) })
      }

      function actAction(id) {
        setActBusy(true); setMsg('')
        return fetchJson(API + '/action', { method: 'POST', body: JSON.stringify(id.indexOf('restart') === 0 ? { id: id } : { itemId: id }) }).then(function (d) {
          setMsg(d.ok ? ('完成 exit=' + d.exit + '；' + (d.tail || '').split('\n').pop()) : ('失败：' + (d.error || '未知')))
          return refresh()
        }).catch(function (e) { setMsg('失败：' + e.message) }).finally(function () { setActBusy(false) })
      }

      function edit(path, value) {
        setBusy(true); setMsg('')
        // 先 dryRun 拿 before/after 预览 → 用户确认 → 真保存（panel-edits.jsonl 留痕由服务端做）
        fetchJson(API + '/config', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ edits: [{ path: path, value: value }], dryRun: true })
        }).then(function (d) {
          if (!d || !d.ok) { setMsg('改动被拒：' + ((d && d.error) || '未知')); return null }
          var e = (d.edits && d.edits[0]) || {}
          var t = '改动预览：\n' + path.join('.') + '\n旧值：' + String(e.before) + '\n新值：' + String(e.after)
          if (!window.confirm(t)) { setMsg('已取消，未改动'); return null }
          return fetchJson(API + '/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ edits: [{ path: path, value: value }] })
          }).then(function (d2) {
            setMsg(d2 && d2.ok ? '已保存，备份：' + (d2.backup || '').split(/[\\/]/).pop() : '保存失败：' + ((d2 && d2.error) || '未知'))
            return loadOverview()
          })
        }).catch(function (e) { setMsg('保存失败：' + (e && e.message)) }).finally(function () { setBusy(false) })
      }

      var checkRows = (ov.checks || []).map(function (c) {
        return h('div', { className: 'cr-check', key: c.fault },
          h('span', { className: 'cr-dot ' + (c.status || 'gray') }),
          h('span', { className: 'id' }, c.fault),
          h('span', { className: 'msg' }, c.module + ' · ' + c.msg),
          h('span', { style: { color: '#bbb', fontSize: 11 } }, c.at))
      })

      var ruleGroups = [['chat', '聊天档'], ['work', '工作档']].map(function (g) {
        var slots = ((config.rules || {})[g[0]]) || []
        var slotCards = slots.map(function (r) {
          return h('div', { className: 'cr-rule', key: g[0] + ':' + r.id + ':' + (r.text || '') },
            h('div', { className: 'head' }, [
              h('input', {
                type: 'checkbox', checked: r.enabled, disabled: busy || !r.text,
                onChange: function (ev) { edit(['rules', g[0], r.id, 'enabled'], !!ev.target.checked) }
              }),
              h('span', null, r.id),
              h('span', { style: { flex: 1, fontSize: 11, color: '#999' } }, r.text ? (r.enabled ? '启用中' : '已停用') : '空槽（自由填写）'),
              h('button', { className: 'cr-btn cr-mini', disabled: busy || !r.text, onClick: function () { edit(['rule-del', g[0], r.id], null) } }, '清空')
            ]),
            h('textarea', {
              className: 'cr-input', rows: 2, defaultValue: r.text || '',
              placeholder: '自由填写，留空则这条不生效；填写后失焦自动保存',
              style: { width: '100%', marginTop: 4, fontSize: 12 },
              onBlur: function (ev) {
                var v = String(ev.target.value || '').trim()
                if (v !== (r.text || '')) edit(['rules', g[0], r.id, 'text'], v)
              }
            }))
        })
        return h('div', { key: 'rg-' + g[0], style: { marginBottom: 10 } }, [
          h('div', { style: { fontWeight: 600, marginBottom: 4 } }, g[1] + '规则（' + g[0] + '，10 条自由填写自由开关）'),
          h('div', null, slotCards)
        ])
      })

      var pluginCards = (config.plugins || []).map(function (p) {
        return h('div', { className: 'cr-pcard', key: p.id }, [
          h('div', { className: 'pn' }, p.id),
          h('div', { className: 'pu' }, p.use || ''),
          h('select', {
            value: p.demand, disabled: busy,
            onChange: function (ev) { edit(['plugins', p.id, 'demand'], ev.target.value) }
          }, [
            h('option', { value: 'always' }, '常驻'),
            h('option', { value: 'on-demand' }, '按需'),
            h('option', { value: 'off' }, '停用')
          ])
        ])
      })

      var verbRows = (ov.verbs || []).map(function (v) {
        return h('tr', { key: v[0] },
          h('td', null, 'crystal ' + v[0]),
          h('td', null, v[1]))
      })

      var state = ov.state || {}
      var usage = ov.usage || {}
      var dues = ov.dues || {}
      var ep = ov.endpoints || {}
      var redChecks = (ov.checks || []).filter(function (c) { return c.status === 'red' })

      return h('div', { className: 'cr-root' }, [
        h('style', null, CSS),
        h('h1', { className: 'cr-h1' }, '💎 结晶 · dsh-crystal'),
        h('p', { className: 'cr-sub' }, 'DSH 大管家：体检 · 账本 · 插件调度 · 桌宠 · QQ 联动'),
        h('div', { className: 'cr-cards' }, [
          h(StatusCard, { cls: 'cr-red', value: status.red, label: '红（坏）' }),
          h(StatusCard, { cls: 'cr-yellow', value: status.yellow, label: '黄（注意）' }),
          h(StatusCard, { cls: 'cr-green', value: status.green, label: '绿（好）' }),
          h(StatusCard, { cls: 'cr-gray', value: status.gray, label: '灰（锁）' })
        ]),
        h('div', { style: { marginBottom: 10 } }, [
          status.pricing ? h('span', { className: 'cr-chip' }, status.pricing) : null,
          state.lastChecked ? h('span', { className: 'cr-chip' }, '上次体检 ' + String(state.lastChecked).slice(0, 19)) : null,
          state.lastRedAt ? h('span', { className: 'cr-chip bad' }, '上次红 ' + String(state.lastRedAt).slice(0, 19)) : null,
          ep.guiPort ? h('span', { className: 'cr-chip ' + (ep.mismatch ? 'bad' : 'on') }, 'GUI 端口 ' + ep.guiPort + (ep.mismatch ? '（漂移！）' : '')) : null,
          usage.lastBridgeStart ? h('span', { className: 'cr-chip on' }, '桥在线') : null
        ]),
        h('details', { className: 'cr-sec', open: true }, [
          h('summary', null, '🚨 红项与修法（' + redChecks.length + ' 条）'),
          h('div', { style: { marginTop: 6 } }, redChecks.length ? redChecks.slice(0, 3).map(function (c) {
            return h('div', { className: 'cr-row', key: 'red-' + c.fault, style: { borderColor: '#f56c6c' } }, [
              h('div', { style: { flex: 1 } }, [
                h('span', { style: { fontWeight: 600, color: '#c0392b' } }, '● ' + c.fault),
                h('span', { style: { color: '#999', marginLeft: 8 } }, String(c.msg || '').slice(0, 60))
              ]),
              h('button', { className: 'cr-btn cr-mini', disabled: actBusy, onClick: function () { actAction('doctor-auto') } }, '一键修'),
              h('button', { className: 'cr-btn cr-mini', disabled: actBusy, onClick: function () { actAction('probe') } }, '复位')
            ])
          }) : h('div', { style: { color: '#67c23a' } }, '没有红项，全绿')) + (redChecks.length > 3 ? h('div', { style: { color: '#999', fontSize: 11, marginTop: 4 } }, '还有 ' + (redChecks.length - 3) + ' 条，见体检明细') : null)
        ]),
        h('div', { className: 'cr-actions', style: { marginBottom: 10 } }, [
          h('button', { className: 'cr-btn', disabled: actBusy, onClick: function () { act('/doctor') } }, actBusy ? '体检中…' : '立即体检'),
          h('button', { className: 'cr-btn', disabled: actBusy, onClick: function () { act('/backup') } }, actBusy ? '忙…' : '一键备份'),
          h('button', { className: 'cr-btn', disabled: actBusy, onClick: function () { act('/rollback-dryrun') } }, actBusy ? '忙…' : '回滚预演'),
          h('button', { className: 'cr-btn cr-warn', disabled: actBusy, onClick: function () { if (window.confirm('重启桥？QQ 会短暂离线，看门狗 1-2 分钟内自动拉起新桥。')) actAction('restart-bridge') } }, actBusy ? '忙…' : '重启桥')
        ]),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '🩺 体检明细（' + (ov.checks || []).length + ' 项）'),
          h('div', { style: { marginTop: 6 } }, checkRows.length ? checkRows : h('div', { style: { color: '#999' } }, '暂无明细，点「立即体检」生成'))
        ]),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '📜 管家规则（全文）'),
          h('div', { style: { marginTop: 6 } }, ruleGroups)
        ]),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '📦 插件台账（' + (config.plugins || []).length + ' 个 · 按需调度）'),
          h('div', { className: 'cr-grid', style: { marginTop: 6 } }, pluginCards)
        ]),
        h('details', { className: 'cr-sec', open: false }, [
          h('summary', null, '🧰 全部能力（' + ((ov.ability && ov.ability.items) ? ov.ability.items.length : 0) + ' 项 · 每行可跑一次）'),
          h('div', { style: { marginTop: 6 } }, ((ov.ability && ov.ability.items) || []).map(function (it) {
            return h('div', { className: 'cr-row', key: 'ab-' + it.id }, [
              h('div', { style: { flex: 1 } }, [
                h('span', { style: { fontWeight: 600 } }, it.name),
                h('span', { style: { color: '#999', marginLeft: 8 } }, it.desc || '')
              ]),
              h('button', { className: 'cr-btn cr-mini', disabled: actBusy, onClick: function () { actAction(it.id) } }, '跑一次')
            ])
          }))
        ]),
        ((ov.missingPlugins && ov.missingPlugins.length) ? h('details', { className: 'cr-sec', open: true }, [
          h('summary', null, '🔍 缺失插件检测（' + ov.missingPlugins.length + ' 个没装）'),
          h('div', { style: { marginTop: 6 } }, ov.missingPlugins.map(function (mp) {
            return h('div', { className: 'cr-rule', key: 'miss-' + mp.plugin, style: { borderColor: '#e6a23c' } }, [
              h('div', { style: { fontWeight: 600 } }, '❓ ' + mp.plugin + ' —— 没安装'),
              h('div', { style: { fontSize: 12, color: '#666', marginTop: 2 } }, '用途：' + mp.use),
              h('div', { style: { fontSize: 12, color: '#b88230', marginTop: 2 } }, '怎么装：' + mp.hint)
            ])
          }))
        ]) : null),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '🏠 管家数据'),
          h('div', { style: { marginTop: 6 } }, [
            h('div', { className: 'cr-kv' }, [h('span', null, '今日对话轮次'), h('b', null, usage.rows + '（成功 ' + usage.okRows + '）')]),
            h('div', { className: 'cr-kv' }, [h('span', null, '今日输入 / 输出'), h('b', null, fmt(usage.inputTokens) + ' / ' + fmt(usage.outputTokens))]),
            h('div', { className: 'cr-kv' }, [h('span', null, '未完成待办 / 逾期'), h('b', null, dues.pending + ' 件 / ' + dues.overdue + ' 件')]),
            h('div', { className: 'cr-kv' }, [h('span', null, '拦截账（乱动手被挡）'), h('b', null, ov.intercepts + ' 笔')]),
            h('div', { className: 'cr-kv' }, [h('span', null, '桌宠'), h('b', null, config.pet && config.pet.enabled ? '开 · 每 ' + config.pet.intervalMin + ' 分钟说话' : '关')])
          ]),
          (dues.lines && dues.lines.length) ? h('div', { className: 'cr-txt', style: { marginTop: 6, fontSize: 12, color: '#777', whiteSpace: 'pre-wrap' } }, '欠债：' + dues.lines.join('；')) : null
        ]),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '⌨️ 命令速查（' + (ov.verbs || []).length + ' 条）'),
          h('table', { className: 'cr-table', style: { marginTop: 6 } }, h('tbody', null, verbRows))
        ]),
        h('div', { className: 'cr-sec' }, [
          h('summary', { style: { fontWeight: 700, marginBottom: 6 } }, '⚙️ 设置（保存即生效，先自动备份）'),
          h('div', { className: 'cr-row' },
            h('label', null, '删文件先问脑公'), h('input', { type: 'checkbox', checked: config.autonomy.askDelete, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askDelete'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', null, '外发消息先问脑公'), h('input', { type: 'checkbox', checked: config.autonomy.askOutbound, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askOutbound'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', null, '动根目录先问脑公'), h('input', { type: 'checkbox', checked: config.autonomy.askRoots, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askRoots'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', null, '修完自动复检（静默验证）'), h('input', { type: 'checkbox', checked: config.autonomy.silentVerify, disabled: busy, onChange: function (ev) { edit(['autonomy', 'silentVerify'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', null, '单轮花钱上限（元）'),
            h('input', { className: 'cr-input', type: 'number', value: config.autonomy.perTurn, disabled: busy, onChange: function (ev) { var n = Number(ev.target.value); cState[1](Object.assign({}, config, { autonomy: Object.assign({}, config.autonomy, { perTurn: n }) })) }, onBlur: function (ev) { var n = Number(ev.target.value); if (n > 0) edit(['autonomy', 'reportMoney', 'perTurn'], n) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '每天花钱上限（元，到顶只报警不打断）'),
            h('input', { className: 'cr-input', type: 'number', value: config.autonomy.daily, disabled: busy, onChange: function (ev) { var n = Number(ev.target.value); cState[1](Object.assign({}, config, { autonomy: Object.assign({}, config.autonomy, { daily: n }) })) }, onBlur: function (ev) { var n = Number(ev.target.value); if (n > 0) edit(['autonomy', 'reportMoney', 'daily'], n) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '每晚 21:00 早报推送到 QQ'),
            h('input', { type: 'checkbox', checked: config.dailyPush, disabled: busy, onChange: function (ev) { edit(['checks', 'dailyPush', 'enabled'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '桌宠开启（透明小窗 + 语音）'),
            h('input', { type: 'checkbox', checked: config.pet && config.pet.enabled, disabled: busy, onChange: function (ev) { edit(['pet', 'enabled'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '桌宠说话间隔（分钟）'),
            h('input', { className: 'cr-input', type: 'number', value: config.pet.intervalMin, disabled: busy, onChange: function (ev) { var n = Number(ev.target.value); cState[1](Object.assign({}, config, { pet: Object.assign({}, config.pet, { intervalMin: n }) })) }, onBlur: function (ev) { var n = Number(ev.target.value); if (n >= 1 && n <= 240) edit(['pet', 'intervalMin'], n) } }))
        ]),
        msg ? h('div', { className: 'cr-msg' }, msg) : null,
        h('div', { className: 'cr-note' }, '真实回滚与卸载仍走命令 crystal rollback / install.ps1 -Uninstall，面板只给预演。作者：QQ 2870864194（脑公）· MIT')
      ])
    }

    var PANEL_ID = 'dsh-crystal'

    function apply(ctx) {
      ctx.slots.inject('main', function () {
        return ctx.slots.register({ name: 'main', key: PANEL_ID }, Panel)
      })
      ctx.slots.inject('sidebar.panellist', function () {
        return ctx.slots.register({
          name: 'sidebar.panellist',
          id: PANEL_ID,
          order: 36,
          label: '结晶'
        }, function Icon() { return h('span', null, '💎') })
      })
    }

    exports.apply = apply
    exports.inject = ['slots']
    return module.exports
  }
})
