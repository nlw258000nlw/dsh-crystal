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
      '.cr-btn.secondary{background:#fff;color:#2f6fed;border:1px solid #bcd4f0}',
      '.cr-btn.danger{background:#d33c3c}',
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

    // [fix-20261120-3] 消息正文兜底：对象转 JSON、清掉尾部的 'null' 拼接（修红项显示 [object Object]null）
    function strMsg(m) {
      if (m === null || m === undefined) return ''
      var s = typeof m === 'string' ? m : JSON.stringify(m)
      return s.replace(/(\s*null\s*)+$/, '')
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
        // [fix-20261120-10] 台账条目（script./cli./route.）走 itemId 白名单映射；直接动作 id 直发
        const isItem = id.indexOf('script.') === 0 || id.indexOf('cli.') === 0 || id.indexOf('route.') === 0
        const body = isItem ? { itemId: id } : { id: id }
        return fetchJson(API + '/action', { method: 'POST', body: JSON.stringify(body) }).then(function (d) {
          // [fix-20261120-12] 复演返回 steps 数组
          if (d && d.steps) setMsg(d.ok ? ('复演完：' + d.steps.map(function (s) { return s.name + '=' + s.code }).join('，')) : ('复演有失败：' + (d.steps || []).map(function (s) { return s.name + '=' + s.code }).join('，')))
          else setMsg(d.ok ? ('完成 exit=' + d.exit + '；' + (d.tail || '').split('\n').pop()) : ('失败：' + (d.error || '未知')))
          return refresh()
        }).catch(function (e) { setMsg('失败：' + e.message) }).finally(function () { setActBusy(false) })
      }

      // [fix-20261120-6] 面板切档（主人 #598 N-3）：写 state\work-mode.json，二次确认、不自动切
      function setMode(mode) {
        if (!window.confirm(mode === 'work' ? '切到干活档？整机所有会话一起切，可以动手。' : '切回聊天档？整机所有会话只禁跑代码/写文件/改配置，其余照常。')) return
        setActBusy(true); setMsg('')
        return fetchJson(API + '/action', { method: 'POST', body: JSON.stringify({ id: 'set-mode', mode: mode }) })
          .then(function (d) {
            setMsg('切档完成：现在 ' + (d.mode === 'work' ? '干活档' : '聊天档') + '（有效键 ' + d.keysBefore + '→' + d.keysAfter + '）')
            return refresh()
          })
          .catch(function (e) { setMsg('失败：' + e.message) }).finally(function () { setActBusy(false) })
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
          h('span', { className: 'msg' }, c.module + ' · ' + strMsg(c.msg)),
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
      // [fix-20261120-3] 四色数字：/status 没抓到（如 doctor -Quiet 吞掉汇总行）时，用 /overview 体检明细兜底计数
      var cnts = { red: 0, yellow: 0, green: 0, gray: 0 }
      ;(ov.checks || []).forEach(function (c) {
        if (c.status === 'red') cnts.red++
        else if (c.status === 'yellow') cnts.yellow++
        else if (c.status === 'green') cnts.green++
        else if (c.status === 'gray') cnts.gray++
      })
      var hasChecks = (ov.checks || []).length > 0
      var num = function (v, k) { return (v === null || v === undefined) ? (hasChecks ? cnts[k] : null) : v }

      return h('div', { className: 'cr-root' }, [
        h('style', null, CSS),
        h('h1', { className: 'cr-h1' }, '💎 结晶 · dsh-crystal'),
        h('p', { className: 'cr-sub' }, 'DSH 大管家：体检 · 账本 · 插件调度 · 桌宠 · QQ 联动'),
        h('div', { className: 'cr-cards' }, [
          h(StatusCard, { cls: 'cr-red', value: num(status.red, 'red'), label: '红（坏）' }),
          h(StatusCard, { cls: 'cr-yellow', value: num(status.yellow, 'yellow'), label: '黄（注意）' }),
          h(StatusCard, { cls: 'cr-green', value: num(status.green, 'green'), label: '绿（好）' }),
          h(StatusCard, { cls: 'cr-gray', value: num(status.gray, 'gray'), label: '灰（锁）' })
        ]),
        h('div', { style: { marginBottom: 10 } }, [
          status.pricing ? h('span', { className: 'cr-chip' }, status.pricing) : null,
          state.lastChecked ? h('span', { className: 'cr-chip' }, '上次体检 ' + String(state.lastChecked).slice(0, 19)) : null,
          state.lastRedAt ? h('span', { className: 'cr-chip bad' }, '上次红 ' + String(state.lastRedAt).slice(0, 19)) : null,
          ep.guiPort ? h('span', { className: 'cr-chip ' + (ep.mismatch ? 'bad' : 'on') }, 'GUI 端口 ' + ep.guiPort + (ep.mismatch ? '（漂移！）' : '')) : null,
          usage.lastBridgeStart ? h('span', { className: 'cr-chip on' }, '桥在线') : null
        ]),
        // [fix-20261120-2] 模式与档位：当前档 + 判定词 + 双档限制 + 生效范围（主人 m01280 要求「标注解释清楚」）
        (function () {
          var md = ov.mode || {}
          var known = md.mode === 'work' || md.mode === 'chat'
          var isWork = md.mode === 'work'
          var badge = known ? (isWork ? '干活档' : '聊天档') : '未知'
          var tW = (md.triggers && md.triggers.work) || {}
          var tC = (md.triggers && md.triggers.chat) || {}
          var tls = md.tools || {}
          var inj = md.inject || {}
          var line = function (label, value) {
            return h('div', { style: { display: 'flex', gap: 8, padding: '3px 0', borderTop: '1px solid #f2f2f2' } }, [
              h('span', { style: { width: 96, flex: '0 0 96px', color: '#888', fontSize: 12 } }, label),
              h('span', { style: { fontSize: 12, color: '#333', flex: 1, lineHeight: 1.5 } }, value)
            ])
          }
          var list = function (a) { return (a && a.length) ? a.join('、') : '（无）' }
          return h('details', { className: 'cr-sec', open: true }, [
            h('summary', null, '🎚 模式与档位（当前：' + (known ? (isWork ? '干活档 ✔ 可动手' : '聊天档 · 只禁跑代码') : '未知，后端未加载，需重启 DSH 一次') + '） — 现在这档能做什么、怎么切、切了影响谁'),
            h('div', { style: { marginTop: 6 } }, [
              h('div', { style: { marginBottom: 6 } }, [
                h('span', { className: 'cr-chip ' + (known ? (isWork ? 'bad' : 'on') : 'bad'), style: { marginRight: 6 } }, badge),
                h('span', { className: 'cr-chip' }, '判定来源：' + (md.source || '—')),
                h('span', { className: 'cr-chip' }, '已授权会话键 ' + ((md.keys || []).length) + ' 个'),
                md.error ? h('span', { className: 'cr-chip bad' }, '读取失败：' + md.error) : null
              ]),
              line('这档管什么', '聊天档：只禁跑代码、写文件、改配置这三类，看视频、抓网页、读记忆、查待办都能用；干活档：工具全开，只禁发消息那四个，防边干活边乱发。'),
              line('切到干活档', '说「' + list(tW.head) + '」；同一句里出现这些字就当普通聊天、不切：' + list(tW.denyAfter)),
              line('切回聊天档', '说「' + list(tC.head) + '」；避开这些字：' + list(tC.denyAfter)),
              line('聊天档放行', list(tls.chatAllowExact)),
              line('干活档禁发', list(tls.workDenyExact)),
              line('注入什么', '聊天档：' + list(inj.chat) + ' ／ 干活档：' + list(inj.work)),
              line('生效范围', md.scope || '整机所有会话共用一份状态，QQ 只是切换入口'),
              line('会不会过期', md.expireNote || '不按时间过期，只有说「聊天模式」才清零'),
              line('状态文件', md.workModeFile || '（未配置 paths.bridgeHome）'),
              h('div', { style: { fontSize: 11, color: '#999', marginTop: 4 } }, '在 QQ 里说一句就切；下面两个按钮是同一件事的面板入口。'),
              h('div', { className: 'cr-actions', style: { marginTop: 8 } }, [
                h('button', { className: 'cr-btn', disabled: actBusy || isWork, title: '写 work-mode.json 的 global 戳；整机所有会话一起切', onClick: function () { setMode('work') } }, isWork ? '已是干活档' : '切到干活档'),
                h('button', { className: 'cr-btn secondary', disabled: actBusy || (known && !isWork), title: '清空 work-mode.json 的有效戳；整机回到聊天档', onClick: function () { setMode('chat') } }, (known && !isWork) ? '已是聊天档' : '切回聊天档')
              ])
            ])
          ])
        })(),
        h('details', { className: 'cr-sec', open: true }, [
          h('summary', null, '🚨 红项与修法（' + redChecks.length + ' 条）'),
          h('div', { style: { marginTop: 6 } }, (function () {
            // [fix-20261120-5] 原文把 vnode 数组用 + 拼尾注，结果整块被字符串化成「[object Object]null」
            if (!redChecks.length) return h('div', { style: { color: '#67c23a' } }, '没有红项，全绿')
            var rows = redChecks.slice(0, 3).map(function (c) {
              return h('div', { className: 'cr-row', key: 'red-' + strMsg(c.fault), style: { borderColor: '#f56c6c' } }, [
                h('div', { style: { flex: 1 } }, [
                  h('span', { style: { fontWeight: 600, color: '#c0392b' } }, '● ' + strMsg(c.fault)),
                  h('span', { style: { color: '#999', marginLeft: 8 } }, strMsg(c.msg).slice(0, 60))
                ]),
                h('button', { className: 'cr-btn cr-mini', disabled: actBusy, onClick: function () { actAction('doctor-auto') } }, '一键修'),
                h('button', { className: 'cr-btn cr-mini', disabled: actBusy, onClick: function () { actAction('probe') } }, '复位')
              ])
            })
            if (redChecks.length > 3) rows.push(h('div', { style: { color: '#999', fontSize: 11, marginTop: 4 } }, '还有 ' + (redChecks.length - 3) + ' 条，见体检明细'))
            return rows
          })())
        ]),
        h('div', { className: 'cr-actions', style: { marginBottom: 10 } }, [
          h('button', { className: 'cr-btn', disabled: actBusy, onClick: function () { act('/doctor') } }, actBusy ? '体检中…' : '立即体检'),
          h('button', { className: 'cr-btn secondary', disabled: actBusy, onClick: function () { act('/backup') } }, actBusy ? '忙…' : '一键备份'),
          h('button', { className: 'cr-btn secondary', disabled: actBusy, onClick: function () { act('/rollback-dryrun') } }, actBusy ? '忙…' : '回滚预演'),
          // [fix-20261120-12] 一键复演：跑一遍体检+切档安全序列，30 秒内演完
          h('button', { className: 'cr-btn secondary', disabled: actBusy, onClick: function () { actAction('replay') } }, actBusy ? '演着…' : '一键复演'),
          h('button', { className: 'cr-btn danger', disabled: actBusy, onClick: function () { if (window.confirm('重启桥？QQ 会短暂离线，看门狗 1-2 分钟内自动拉起新桥。')) actAction('restart-bridge') } }, actBusy ? '忙…' : '重启桥')
        ]),
        // [fix-20261120-7] QQ 联动区（主人 #598 N-1：四组写全，每条写是什么/开没开/开了会怎样/装不了找谁）
        (function () {
          var groups = [
            { t: '✅ 已经在跑（4 处，默认开）', items: [
              ['记账 shadow', '每轮把 token 花销追写 data\\usage.jsonl', '一直开'],
              ['档期判定', '只读 crystal.json 的峰谷价，决定用哪档模型', '一直开'],
              ['切档启停插件', '按 crystal.json.modePlugins 名单开关插件', '一直开'],
              ['启动标记', '桥启动写一行标记，方便对账「这轮是谁跑的」', '一直开']
            ] },
            { t: '🟡 静默兜底（3 处，默认关）', items: [
              ['令牌自愈', '只有令牌失效且带 x-console-token 时旁路一次', '关'],
              ['发送失败降级', 'socialV2.sendFallback.enabled=false，失败就报错不重试', '关'],
              ['兴趣主动分享', 'socialV2.interests=false，不会主动插话分享', '关']
            ] },
            { t: '🟠 做了一半（1 处）', items: [
              ['拦截账', '桥里写了写入口，但没人调用，面板读不到任何一条', '等接线']
            ] },
            { t: '⚪ 还没有（4 处）', items: [
              ['聊天档改禁列', '现网是白名单（只许 QQ/记忆类工具），要改成只禁跑代码与写文件', '要改桥守卫'],
              ['发送凭证', 'crystal-receipts.json 只有空壳，没有逐条回执', '要改桥'],
              ['关键词自动开插件', 'keyword-map.json 生成了，但桥不读它', '要改桥'],
              ['群聊建议箱', 'suggestions.jsonl 还没有落盘链路，建议进不来', '要改桥']
            ] }
          ]
          return h('details', { className: 'cr-sec', open: false }, [
            h('summary', null, '🔗 QQ 联动（在跑 4 / 兜底 3 / 半截 1 / 还没有 4）'),
            h('div', { style: { fontSize: 11, color: '#999', margin: '6px 0 8px' } }, '这区解决什么：QQ 这边到底替小鱼做了什么、哪些还只是画了张图。'),
            h('div', null, groups.map(function (g) {
              return h('div', { key: 'qqg-' + g.t, style: { marginBottom: 10 } }, [
                h('div', { style: { fontWeight: 600, fontSize: 12, marginBottom: 4 } }, g.t),
                h('div', null, g.items.map(function (it) {
                  return h('div', { className: 'cr-row', key: 'qqi-' + it[0] }, [
                    h('div', { style: { flex: 1 } }, [
                      h('span', { style: { fontWeight: 600 } }, it[0]),
                      h('span', { style: { color: '#666', marginLeft: 8 } }, it[1])
                    ]),
                    h('span', { style: { color: '#999', fontSize: 11, whiteSpace: 'nowrap' } }, it[2])
                  ])
                }))
              ])
            })),
            h('div', { style: { fontSize: 11, color: '#999', marginTop: 2 } }, '标「要改桥」的四件要动 QQ 桥；自己装不了就把它交给小鱼，装完刷新这里会自己变亮。')
          ])
        })(),
        // [fix-20261120-9] 记忆三件（主人 m00811：3 天窗口、只标不删、删除逐条问；建议箱合理就做进去）
        (function () {
          var mem = ov.memory || { checkedAt: '', files: 0, bytes: 0, active: 0, stale: 0, suggestions: 0, staleList: [] }
          return h('details', { className: 'cr-sec' }, [
            h('summary', null, '🧠 记忆（3 天体检' + (mem.checkedAt ? ' @' + mem.checkedAt.slice(11, 16) : '') + '） — 记忆攒了多少、哪些三天没动过，只标不删'),
            h('div', { style: { fontSize: 11, color: '#999', margin: '6px 0 8px' } }, '这区解决什么：记忆只进不出会越来越大；三天一查，没动过的列出来问主人，不点头一条不删。'),
            h('div', { className: 'cr-row' }, [
              h('div', { style: { flex: 1 } }, '共 ' + mem.files + ' 件 / ' + Math.round((mem.bytes || 0) / 1024) + ' KB；3 天内动过 ' + mem.active + '，没动过 ' + mem.stale),
              h('span', { style: { color: '#999', fontSize: 11 } }, '建议箱 ' + mem.suggestions + ' 条')
            ]),
            (mem.staleList && mem.staleList.length) ? h('div', { style: { marginTop: 6 } }, [
              h('div', { style: { fontSize: 11, color: '#c96b00' } }, '没动过（只标不删，清单会问主人）：'),
              h('div', null, mem.staleList.map(function (s) { return h('div', { key: 'ms-' + s, style: { fontSize: 11, color: '#666', paddingLeft: 8 } }, '· ' + s) }))
            ]) : null,
            h('div', { style: { marginTop: 8 } }, [
              h('button', { className: 'cr-btn secondary', disabled: actBusy, style: { marginRight: 6 }, onClick: function () { actAction('mem-check') } }, actBusy ? '忙…' : '重新体检'),
              h('button', { className: 'cr-btn secondary', disabled: actBusy, style: { marginRight: 6 }, onClick: function () { actAction('mem-month') } }, actBusy ? '忙…' : '月度账'),
              h('button', { className: 'cr-btn secondary', disabled: actBusy, onClick: function () { actAction('mem-inbox') } }, actBusy ? '忙…' : '看建议箱')
            ])
          ])
        })(),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '🩺 体检明细（' + (ov.checks || []).length + ' 项） — 22 项检查各自的结果与修法'),
          h('div', { style: { marginTop: 6 } }, checkRows.length ? checkRows : h('div', { style: { color: '#999' } }, '暂无明细，点「立即体检」生成'))
        ]),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '📜 管家规则（全文） — 现在真正塞进模型的规矩，一眼看全'),
          h('div', { style: { marginTop: 6 } }, ruleGroups)
        ]),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '📦 插件台账（' + (config.plugins || []).length + ' 个 · 按需调度） — 每个插件常驻/按需/停用，可当场改'),
          h('div', { className: 'cr-grid', style: { marginTop: 6 } }, pluginCards)
        ]),
        h('details', { className: 'cr-sec', open: false }, [
          h('summary', null, '🧰 全部能力（' + ((ov.ability && ov.ability.items) ? ov.ability.items.length : 0) + ' 项 · 每行可跑一次） — 这插件到底会什么，一条不藏'),
          h('div', { style: { marginTop: 6 } }, ((ov.ability && ov.ability.items) || []).map(function (it) {
            return h('div', { className: 'cr-row', key: 'ab-' + it.id }, [
              h('div', { style: { flex: 1 } }, [
                h('span', { style: { fontWeight: 600 } }, it.name),
                h('span', { style: { color: '#999', marginLeft: 8 } }, it.desc || ''),
                // [fix-20261120-12] 跑过没：没跑过标灰，跑过显示次数与时间
                it.lastRunAt
                  ? h('span', { style: { color: '#8a8', marginLeft: 8, fontSize: 12 } }, '跑过 ' + (it.runCount || 1) + ' 次 · ' + String(it.lastRunAt).slice(5, 16).replace('T', ' '))
                  : h('span', { style: { color: '#c5c5c5', marginLeft: 8, fontSize: 12 } }, '还没跑过')
              ]),
              h('button', { className: 'cr-btn cr-mini' + (it.lastRunAt ? '' : ' secondary'), disabled: actBusy, onClick: function () { actAction(it.id) } }, '跑一次')
            ])
          }))
        ]),
        ((ov.missingPlugins && ov.missingPlugins.length) ? h('details', { className: 'cr-sec', open: true }, [
          h('summary', null, '🔍 缺失插件检测（' + ov.missingPlugins.length + ' 个没装） — 装上就亮，装不上就交给小鱼'),
          h('div', { style: { marginTop: 6 } }, ov.missingPlugins.map(function (mp) {
            return h('div', { className: 'cr-rule', key: 'miss-' + mp.plugin, style: { borderColor: '#e6a23c' } }, [
              h('div', { style: { fontWeight: 600 } }, '❓ ' + mp.plugin + ' —— 没安装'),
              h('div', { style: { fontSize: 12, color: '#666', marginTop: 2 } }, '用途：' + mp.use),
              h('div', { style: { fontSize: 12, color: '#b88230', marginTop: 2 } }, '怎么装：' + mp.hint)
            ])
          }))
        ]) : null),
        h('details', { className: 'cr-sec' }, [
          h('summary', null, '🏠 管家数据 — 轮次、输入输出、待办、拦截账、桌宠状态'),
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
          h('summary', null, '⌨️ 命令速查（' + (ov.verbs || []).length + ' 条） — 命令行能直接敲的动词，跟面板动作同一批'),
          h('table', { className: 'cr-table', style: { marginTop: 6 } }, h('tbody', null, verbRows))
        ]),
        h('div', { className: 'cr-sec' }, [
          h('summary', { style: { fontWeight: 700, marginBottom: 6 } }, '⚙️ 设置（保存即生效，先自动备份） — 危险动作问询开关与花销上限'),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：删文件前必须先问你。默认：开。改了会怎样：关掉后小鱼能自己删文件（不建议）。' }, '删文件先问主人'), h('input', { type: 'checkbox', checked: config.autonomy.askDelete, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askDelete'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：往 QQ/邮箱发东西前先问你。默认：开。改了会怎样：关掉就直接发出去。' }, '外发消息先问主人'), h('input', { type: 'checkbox', checked: config.autonomy.askOutbound, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askOutbound'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：改系统根目录、受管文件前先问你。默认：开。改了会怎样：关掉能直接改这些地方。' }, '动根目录先问主人'), h('input', { type: 'checkbox', checked: config.autonomy.askRoots, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askRoots'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：改完自己再验一遍，不吭声。默认：开。改了会怎样：关掉就不复检，可能带着错交单。' }, '修完自动复检（静默验证）'), h('input', { type: 'checkbox', checked: config.autonomy.silentVerify, disabled: busy, onChange: function (ev) { edit(['autonomy', 'silentVerify'], !!ev.target.checked) } }), h('span', { className: 'cr-badge' }, '默认')),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：一轮对话最多花多少钱。默认：3。改了会怎样：超了只报警，不打断你。' }, '单轮花钱上限（元）'),
            h('input', { className: 'cr-input', type: 'number', value: config.autonomy.perTurn, disabled: busy, onChange: function (ev) { var n = Number(ev.target.value); cState[1](Object.assign({}, config, { autonomy: Object.assign({}, config.autonomy, { perTurn: n }) })) }, onBlur: function (ev) { var n = Number(ev.target.value); if (n > 0) edit(['autonomy', 'reportMoney', 'perTurn'], n) } })),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：一天最多花多少钱。默认：12。改了会怎样：超了只报警，不打断你。' }, '每天花钱上限（元，到顶只报警不打断）'),
            h('input', { className: 'cr-input', type: 'number', value: config.autonomy.daily, disabled: busy, onChange: function (ev) { var n = Number(ev.target.value); cState[1](Object.assign({}, config, { autonomy: Object.assign({}, config.autonomy, { daily: n }) })) }, onBlur: function (ev) { var n = Number(ev.target.value); if (n > 0) edit(['autonomy', 'reportMoney', 'daily'], n) } })),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：每晚把体检与花销推到 QQ。默认：开。改了会怎样：关掉就不推，面板里还能看。' }, '每晚 21:00 早报推送到 QQ'),
            h('input', { type: 'checkbox', checked: config.dailyPush, disabled: busy, onChange: function (ev) { edit(['checks', 'dailyPush', 'enabled'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：桌面那只鱼开不开。默认：开。改了会怎样：关掉窗口消失，下次登录也不再自启。' }, '桌宠开启（透明小窗 + 语音）'),
            h('input', { type: 'checkbox', checked: config.pet && config.pet.enabled, disabled: busy, onChange: function (ev) { edit(['pet', 'enabled'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', { title: '是什么：几分钟冒一句话。默认：15。改了会怎样：改完要重启桌宠才生效。' }, '桌宠说话间隔（分钟）'),
            h('input', { className: 'cr-input', type: 'number', value: config.pet.intervalMin, disabled: busy, onChange: function (ev) { var n = Number(ev.target.value); cState[1](Object.assign({}, config, { pet: Object.assign({}, config.pet, { intervalMin: n }) })) }, onBlur: function (ev) { var n = Number(ev.target.value); if (n >= 1 && n <= 240) edit(['pet', 'intervalMin'], n) } }))
        ]),
        msg ? h('div', { className: 'cr-msg' }, msg) : null,
        h('div', { className: 'cr-note' }, '真实回滚与卸载仍走命令 crystal rollback / install.ps1 -Uninstall，面板只给预演。作者：dsh-crystal · MIT')
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
