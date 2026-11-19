# minimal-work 最小配置包
- config-fragment.json：桥 config.json 增补片段（占位符 <CRYSTAL_HOME>/<USER_HOME>/<BRIDGE_HOME>/<GUI_PORT>，安装时替换，不写死路径）。
- guard-whitelist.txt：守卫白名单示例（把 crystal 的 4 个计划任务与 3 个锁目录加进 SnowLuma-Guard 白名单，避免看门狗误杀）。
- presets\：桥接预设 patch 模板（四件，对应 qq-chat/qq-chat-owner/qq-chat-readonly/qq-chat-v2；此包模式=<MODE>）。
- install-notes：装完跑 install.ps1 -HomeDir <你的数据目录>。