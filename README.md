# DeepSeek Harness for Raycast

用 Raycast 补上 DSH 桌面版缺的那一块：**一个真正的全局热键，随时唤起 / 收起 DSH 窗口。**

DSH 桌面壳自己没有注册任何全局快捷键（`lib/main.js` 里没有 `globalShortcut`），只提供了托盘菜单和标题栏关闭按钮。这个扩展把窗口控制权交给 Raycast，因此你可以把 `Toggle DSH Window` 绑到任意热键上。

> 仅支持 Windows。窗口控制走 Win32，没有 macOS 分支。

## 命令

| 命令 | 模式 | 作用 |
| --- | --- | --- |
| **Toggle DSH Window** | 无界面 | 窗口是你正在看的那个 → 隐藏到通知区域；否则唤起并聚焦。**把热键绑到这个命令上。** |
| **Show DSH Window** | 无界面 | 唤起、还原并聚焦；未运行时直接启动 DSH。最大化过的窗口会以最大化状态回来 |
| **Hide DSH Window** | 无界面 | 隐藏到通知区域，等同于点标题栏的关闭按钮：进程继续跑，任务不中断 |
| **DSH Status** | 列表 | 查看进程 / 窗口 / 安装路径 / harness home / 会话数，并从这里执行以上操作 |

## 安装

```powershell
cd D:\WorkSpace\CodeProj\dsh-plugins\raycast-dsh
npm install
npm run dev
```

`ray develop` 会把扩展以开发模式装进正在运行的 Raycast。之后在 Raycast 里搜索 `DSH` 即可看到这些命令。

### 绑定全局热键（关键一步）

Raycast 免费版就支持命令级全局热键：

1. 打开 Raycast（默认 `Alt + Space`）；
2. 搜索 `Toggle DSH Window`，选中它；
3. 按 `Ctrl + K` → **Configure Command** → **Hotkey**；
4. 录一个顺手的组合键（例如 `Alt + Q` 或 `Ctrl + Alt + D`）。

之后无论你在哪个应用里，按这个热键就能唤起 / 收起 DSH 窗口。

## 偏好设置

| 名称 | 默认 | 说明 |
| --- | --- | --- |
| Application Path | 空 | `DeepSeek Harness.exe` 完整路径。留空时自动探测正在运行的进程和默认安装位置 |
| Process Name | `DeepSeek Harness` | 桌面壳的映像名（不含 `.exe`），一般不用改 |
| Launch When Not Running | 开 | 命令发现 DSH 没在跑时是否自动启动它 |
| Launch Timeout | `15` | 启动后等待窗口出现的秒数 |

## 工作原理

窗口控制由一个随扩展发布的 PowerShell 脚本完成，它内嵌一段 C#，通过 Win32 直接操作 DSH 的顶层窗口：

- **定位窗口**：枚举 `DeepSeek Harness` 各进程中所有「无属主的顶层有标题窗口」，取面积最大的那个。因此即使窗口已经被隐藏（`IsWindowVisible` 为 false）也能找到句柄。
- **隐藏**：`ShowWindow(SW_HIDE)`。与点标题栏关闭按钮等价，进程存活、任务继续。
- **唤起**：窗口可见时**完全不碰** `ShowWindow`，只抢焦点；隐藏时用 `SW_SHOW`；最小化时用 `SW_RESTORE`，并且如果它最小化前是最大化的（`GetWindowPlacement` 的 `WPF_RESTORETOMAXIMIZED`），再补一次 `SW_MAXIMIZE`。之后 `SetForegroundWindow`；Windows 的前台锁会拒绝非前台进程抢焦点，所以脚本会临时 `AttachThreadInput` 到当前前台线程，仍被拒绝时再补一次无按键的 ALT 轻敲（解除前台限制的经典做法），然后重试。
- **状态判定**：窗口是否可见、是否最小化、是否持有前台，都由脚本在动作**之后**重新读取。命令的提示文案来自这个实测结果，不会替 Windows 报告一个并不存在的「已聚焦」。

### toggle 怎么判断该隐藏还是该唤起

热键触发时**前台窗口是 Raycast 自己**（它的 HUD 抢了焦点），所以「DSH 是不是前台窗口」这个判据必然失败——这正是最初 toggle 永远走唤起逻辑的原因。

现在的判据是走一遍 z 序，只看「真正的应用窗口」（可见、未最小化、无属主、有标题、非 tool 窗口），落在最上面的那个就是用户原先在看的窗口：

- 是 DSH → 隐藏；
- 不是 DSH → 唤起并聚焦 DSH。

关键在于 **Raycast 自己的窗口是无标题栏的 `WS_EX_TOOLWINDOW`**，天然被这轮筛选排除，所以它在不在前台都不影响判断——脚本不需要知道是谁调用了它。实测两种情形都正确：Chrome/Notepad 在前台时唤起 DSH；Raycast 的 tool 窗口在前台而 DSH 在其下方时隐藏 DSH。

### 为什么不直接用 DSH 自带的 `dsh://open`

DSH 桌面版确实注册了 `dsh://` 协议，`dsh://open` 会走到 `focusPrimaryWindow()`，看起来正是我们要的。但实测在这台机器上：

- 用 WM_CLOSE 隐藏窗口后，`dsh://open` **不会**把窗口恢复出来；
- 再次启动 `DeepSeek Harness.exe` 走单实例路由（`second-instance` → `focusPrimaryWindow()`）同样无效。

所以唤起必须由外部直接用 Win32 完成。`dsh://open` 只被保留为「DSH 未运行时如何把它拉起来」的一个兜底启动方式。

### 为什么要有编译缓存

脚本第一次运行时会把自己内嵌的 C# 编译成 `%LOCALAPPDATA%\RaycastDsh\dsh-window.exe` 并缓存：

- 直接跑缓存 exe 约 **110 ms**；
- 每次都启动 Windows PowerShell 则要 **450 ms 以上**，对热键来说太迟钝。

脚本用内嵌源码的 SHA-256 作为指纹，源码变了就重新编译；编译不可用时退回 `Add-Type` 在进程内加载同一份代码，功能不受影响。扩展侧还会比较 exe 与脚本的修改时间，脚本更新后自动走一次重新编译。

### 一个反直觉的坑

Node 的 `child_process` 若带 `windowsHide: true`，会给子进程设置 `STARTF_USESHOWWINDOW` + `SW_HIDE`。而 Windows 规定：**进程的第一次 `ShowWindow` 调用会被 STARTUPINFO 里的 `wShowWindow` 覆盖**。结果就是我们那句 `ShowWindow(hwnd, SW_SHOW)` 被静默丢掉——窗口该显示却纹丝不动。

脚本因此把每条 `ShowWindow` 命令都下发两次（该调用本身幂等），确保真正生效的那次活下来。

## 已知限制

- **无法在浏览器里打开 DSH 界面。** 桌面版的 Web UI（`127.0.0.1:19387`）带浏览器信任围栏，未认证请求一律 401；可用的带令牌 URL 只通过 Electron 主进程内部 IPC 传递，并保存在 Chromium 的 cookie 存储里。真要暴露给浏览器得从 Electron 的加密 cookie 库里取令牌，代价和风险都不合适。
- **Raycast deeplink 到不了本地开发扩展。** 实测 `raycast://extensions/<owner>/dsh/<command>` 会被当成商店扩展去 `backend.raycast.com` 查询并返回 404（`Command not found: … in dsh`）。开发模式下请直接在 Raycast 里搜索命令名运行。
- **不提供退出 DSH 的命令。** DSH 桌面壳对外只暴露「隐藏到通知区域」，没有优雅退出的外部入口（`app.quit()` 只由托盘菜单和内部流程触发），所以任何"退出"都只能是强制结束进程。为了不让一个误触的热键打断进行中的任务，这里干脆不提供。
- **toggle 的判据基于 z 序。** 如果某个启动器用**带标题栏的普通窗口**做 HUD，它会被当成"用户正在看的窗口"，那一轮 toggle 会去唤起而不是隐藏。Raycast 不是这种。
- 只处理**单个** DSH 窗口（当前 profile 的主窗口）。多 profile 同时运行时，命令作用于持有最大窗口的那个实例。

## 开发

```powershell
npm run dev          # 装进 Raycast 并监听改动
npm run lint         # ray lint（ESLint + Prettier）
npm run build        # 构建（Raycast 默认输出位置）
npm run build:dir    # 构建到 ./dist，供下面的验证脚本使用
npm run verify:commands -- toggle   # 在 Raycast 之外跑真实命令
```

`_tools/verify-commands.cjs` 把 `@raycast/api` 打桩后直接加载 `dist/` 里的产物，因此能在不打开 Raycast UI 的情况下验证**实际发布的那份代码**：偏好读取、助手调用、输出解析、提示文案。可用参数：`toggle` / `show` / `hide` / `status`，另有 `--asset-root <dir>` 指定资源目录（用 `dist/assets` 验证的就是打包产物）。

`_tools/probe-maximize.ps1` 自动复现「最大化 → 最小化 → show」并检查窗口是否仍是最大化；`_tools/probe-toggle-front.ps1` 分别把普通应用窗口和 Raycast 的 tool 窗口置前，验证 toggle 两个方向都正确；`_tools/probe-timing.cjs` 观察某个动作之后窗口状态如何随时间稳定（排查前台锁之类的时序问题）；`_tools/probe-raycast-windows.ps1` 打印 Raycast 全部顶层窗口的样式标志——toggle 的 z 序判据就是靠它确认「Raycast 的窗口是 `WS_EX_TOOLWINDOW`」的。

`_tools/make-icon.py` 从已安装的 DSH 应用图标派生 `assets/extension-icon.png`：即 `resources\icon.png` 缩放出的 512×512 版本，所以扩展和它所属的应用是同一个标志（需要 Pillow；应用装在非默认位置时把图标路径作为参数传入）。

## 卸载

在 Raycast 中删除该扩展，然后删掉助手缓存：

```powershell
Remove-Item "$env:LOCALAPPDATA\RaycastDsh" -Recurse -Force
```
