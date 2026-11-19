/* ============================================================================
 * dsh-crystal — 浏览器半侧：侧栏「结晶」面板
 * 状态红黄绿 + 立即体检 / 一键备份 / 回滚预演按钮 + 总表开关表单（规则/预算线/早报/按需档位）
 * 手写 ModuleLoader bundle，不用构建；数据全部来自宿主路由 /dsh-crystal/*
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
      '.cr-root{padding:16px;font-size:13px;color:var(--dsh-text, #222);max-width:640px}',
      '.cr-h1{margin:0 0 4px;font-size:16px;font-weight:700}',
      '.cr-sub{color:var(--dsh-text-dim, #888);margin:0 0 14px}',
      '.cr-cards{display:flex;gap:10px;margin-bottom:14px}',
      '.cr-card{flex:1;border:1px solid #e2e2e2;border-radius:10px;padding:10px 12px;text-align:center;background:var(--dsh-bg-card,#fff)}',
      '.cr-num{font-size:22px;font-weight:800}',
      '.cr-red{color:#d33}.cr-yellow{color:#b8860b}.cr-green{color:#2a9d3a}.cr-gray{color:#999}',
      '.cr-actions{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px}',
      '.cr-btn{border:1px solid #c9c9c9;background:#fff;border-radius:8px;padding:7px 12px;cursor:pointer;font-size:13px}',
      '.cr-btn:disabled{opacity:.5;cursor:wait}',
      '.cr-sec{border-top:1px solid #eee;padding-top:12px;margin-top:12px}',
      '.cr-row{display:flex;align-items:center;justify-content:space-between;padding:6px 0}',
      '.cr-row label{flex:1}',
      '.cr-input{width:90px;border:1px solid #ccc;border-radius:6px;padding:4px 6px}',
      '.cr-select{border:1px solid #ccc;border-radius:6px;padding:4px 6px;background:#fff}',
      '.cr-msg{margin-top:8px;white-space:pre-wrap;font-family:ui-monospace,Consolas,monospace;font-size:12px;color:#666;max-height:120px;overflow:auto}',
      '.cr-note{color:#999;font-size:12px;margin-top:10px}'
    ].join('\n')

    function StatusCard(props) {
      return h('div', { className: 'cr-card' }, [
        h('div', { className: 'cr-num ' + props.cls }, String(props.value)),
        h('div', { style: { fontSize: 12, color: '#888' } }, props.label)
      ])
    }

    function Panel() {
      var status0 = { red: null, yellow: null, green: null, gray: null, pricing: '' }
      var config0 = {
        rules: [], budgetWarnCnyDaily: 12, dailyPush: true, plugins: [],
        autonomy: { askDelete: true, askOutbound: true, askRoots: true, silentVerify: true, reportMoney: { perTurn: 3, daily: 12 } },
        pet: { enabled: false, voice: true, intervalMin: 15, greetingAm: true, greetingPm: true }
      }
      var sState = useState(status0)
      var cState = useState(config0)
      var busyState = useState(false)
      var msgState = useState('')
      var status = sState[0], setStatus = sState[1]
      var config = cState[0], setConfig = cState[1]
      var busy = busyState[0], setBusy = busyState[1]
      var msg = msgState[0], setMsg = msgState[1]

      function refresh() {
        return fetchJson(API + '/status').then(function (d) { setStatus(d) }).catch(function (e) { setMsg('状态读取失败：' + e.message) })
      }
      function loadConfig() {
        return fetchJson(API + '/config').then(function (d) { setConfig(d) }).catch(function (e) { setMsg('配置读取失败：' + e.message) })
      }
      useEffect(function () { refresh(); loadConfig() }, [])

      function act(path) {
        setBusy(true); setMsg('')
        return fetchJson(API + path, { method: 'POST' }).then(function (d) {
          setMsg(d.last || ('exit=' + d.exit + ' 红' + d.red + ' 黄' + d.yellow + ' 绿' + d.green + ' 灰' + d.gray))
          return refresh()
        }).catch(function (e) { setMsg('失败：' + e.message) }).finally(function () { setBusy(false) })
      }

      function edit(path, value) {
        setBusy(true); setMsg('')
        fetchJson(API + '/config', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ edits: [{ path: path, value: value }] })
        }).then(function (d) {
          var okN = (d.applied || 0)
          setMsg('已保存 ' + okN + ' 项，备份：' + (d.backup || '').split(/[\\/]/).pop())
          return loadConfig()
        }).catch(function (e) { setMsg('保存失败：' + e.message) }).finally(function () { setBusy(false) })
      }

      var ruleRows = (config.rules || []).map(function (r) {
        var path = ['rules', r.id, 'enabled']
        return h('div', { className: 'cr-row', key: r.id },
          h('label', null, r.id + ' ' + String(r.text || '').slice(0, 24)),
          h('input', {
            type: 'checkbox', checked: r.enabled, disabled: busy,
            onChange: function (ev) { edit(path, !!ev.target.checked) }
          }))
      })
      var pluginRows = (config.plugins || []).map(function (p) {
        return h('div', { className: 'cr-row', key: p.id },
          h('label', null, p.id),
          h('select', {
            className: 'cr-select', value: p.demand, disabled: busy,
            onChange: function (ev) { edit(['plugins', p.id, 'demand'], ev.target.value) }
          }, [
            h('option', { value: 'always' }, '常驻 always'),
            h('option', { value: 'on-demand' }, '按需 on-demand'),
            h('option', { value: 'off' }, '停用 off')
          ]))
      })

      return h('div', { className: 'cr-root' }, [
        h('style', null, CSS),
        h('h1', { className: 'cr-h1' }, '结晶 · dsh-crystal'),
        h('p', { className: 'cr-sub' }, '系统大管家：体检、备份、按需调度、预算报警全在这。平时不用管，红了会推 QQ。'),
        h('div', { className: 'cr-cards' }, [
          h(StatusCard, { cls: 'cr-red', value: status.red === null ? '—' : status.red, label: '红' }),
          h(StatusCard, { cls: 'cr-yellow', value: status.yellow === null ? '—' : status.yellow, label: '黄' }),
          h(StatusCard, { cls: 'cr-green', value: status.green === null ? '—' : status.green, label: '绿' }),
          h(StatusCard, { cls: 'cr-gray', value: status.gray === null ? '—' : status.gray, label: '灰' })
        ]),
        status.pricing ? h('div', { style: { fontSize: 12, color: '#888', marginBottom: 10 } }, status.pricing) : null,
        h('div', { className: 'cr-actions' }, [
          h('button', { className: 'cr-btn', disabled: busy, onClick: function () { act('/doctor') } }, '立即体检'),
          h('button', { className: 'cr-btn', disabled: busy, onClick: function () { act('/backup') } }, '一键备份'),
          h('button', { className: 'cr-btn', disabled: busy, onClick: function () { act('/rollback-dryrun') } }, '回滚预演')
        ]),
        h('div', { className: 'cr-sec' }, [
          h('div', { style: { fontWeight: 700, marginBottom: 4 } }, '规则开关（保存即生效，先备份后写）'),
          ruleRows
        ]),
        h('div', { className: 'cr-sec' }, [
          h('div', { className: 'cr-row' },
            h('label', null, '预算钱线（元/日，到顶只报警不打断）'),
            h('input', {
              className: 'cr-input', type: 'number', value: config.budgetWarnCnyDaily, disabled: busy,
              onChange: function (ev) {
                var n = Number(ev.target.value)
                cState[1](Object.assign({}, config, { budgetWarnCnyDaily: n }))
              },
              onBlur: function (ev) { var n = Number(ev.target.value); if (n > 0) edit(['checks', 'budget', 'warnCnyDaily'], n) }
            })),
          h('div', { className: 'cr-row' },
            h('label', null, '每晚 21:00 早报推送到 QQ'),
            h('input', { type: 'checkbox', checked: config.dailyPush, disabled: busy, onChange: function (ev) { edit(['checks', 'dailyPush', 'enabled'], !!ev.target.checked) } }))
        ]),
        h('div', { className: 'cr-sec' }, [
          h('div', { style: { fontWeight: 700, marginBottom: 4 } }, '权限分级（管家自己能动手的界限）'),
          h('div', { className: 'cr-row' },
            h('label', null, '删文件先问脑公'), h('input', { type: 'checkbox', checked: config.autonomy.askDelete, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askDelete'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '外发消息先问脑公'), h('input', { type: 'checkbox', checked: config.autonomy.askOutbound, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askOutbound'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '动根目录先问脑公'), h('input', { type: 'checkbox', checked: config.autonomy.askRoots, disabled: busy, onChange: function (ev) { edit(['autonomy', 'askRoots'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '修完自动复检（静默验证）'), h('input', { type: 'checkbox', checked: config.autonomy.silentVerify, disabled: busy, onChange: function (ev) { edit(['autonomy', 'silentVerify'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '花钱单轮上限（元）'),
            h('input', { className: 'cr-input', type: 'number', value: config.autonomy.reportMoney.perTurn, disabled: busy, onBlur: function (ev) { var n = Number(ev.target.value); if (n > 0) edit(['autonomy', 'reportMoney', 'perTurn'], n) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '花钱每日上限（元）'),
            h('input', { className: 'cr-input', type: 'number', value: config.autonomy.reportMoney.daily, disabled: busy, onBlur: function (ev) { var n = Number(ev.target.value); if (n > 0) edit(['autonomy', 'reportMoney', 'daily'], n) } }))
        ]),
        h('div', { className: 'cr-sec' }, [
          h('div', { style: { fontWeight: 700, marginBottom: 4 } }, '插件按需档位（用到才开，用完自动关）'),
          pluginRows
        ]),
        h('div', { className: 'cr-sec' }, [
          h('div', { style: { fontWeight: 700, marginBottom: 4 } }, '桌面大肥鱼桌宠（透明小窗，说体检/用量/欠债）'),
          h('div', { className: 'cr-row' },
            h('label', null, '开启桌宠'), h('input', { type: 'checkbox', checked: config.pet.enabled, disabled: busy, onChange: function (ev) { edit(['pet', 'enabled'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '语音说话'), h('input', { type: 'checkbox', checked: config.pet.voice, disabled: busy, onChange: function (ev) { edit(['pet', 'voice'], !!ev.target.checked) } })),
          h('div', { className: 'cr-row' },
            h('label', null, '说话间隔（分钟）'), h('input', { className: 'cr-input', type: 'number', value: config.pet.intervalMin, disabled: busy, onBlur: function (ev) { var n = Number(ev.target.value); if (n >= 1 && n <= 240) edit(['pet', 'intervalMin'], n) } }))
        ]),
        h('div', { className: 'cr-sec' }, [
          h('div', { style: { fontWeight: 700, marginBottom: 4 } }, '使用教程（新手四步）'),
          h('ol', { style: { margin: '4px 0 0 16px', fontSize: 12, lineHeight: 1.8 } }, [
            h('li', null, '装好就完事：装完自动注册 4 个计划任务，医生每 8 小时体检一次，坏的自己修。'),
            h('li', null, '平时不用管：出红才推 QQ 提醒（红警直推）；每天晚上 21:00 自动发「爱丽丝早报」。'),
            h('li', null, '命令只在想看的时候用：crystal status 看家底、crystal doctor 体检、crystal backup 备份、crystal rollback -List 看回滚点。'),
            h('li', null, '想自己改配置：上面每个开关保存即生效（先自动备份）；改坏了一键回滚。')
          ])
        ]),
        msg ? h('div', { className: 'cr-msg' }, msg) : null,
        h('div', { className: 'cr-note' }, '真实回滚与卸载仍走命令 crystal rollback / install.ps1 -Uninstall，面板只给预演。')
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
