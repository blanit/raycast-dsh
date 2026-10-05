# Changelog

## [Window toggle fixes and the DSH mark] - 2026-10-05

- 扩展图标改为 DSH 应用自己的标志：由已安装应用的 `resources\icon.png` 缩放为 512×512，不再使用手绘的窗口图形。
- 移除了 `Quit DSH` 与 `Restart DSH`：DSH 桌面壳没有优雅退出的外部入口，这两个命令只能是强制结束进程，不值得为一个热键误触付出打断任务的代价。
- 修复 `Show DSH Window` 丢失最大化状态：原实现无条件调用 `SW_RESTORE`，而它会取消最大化。现在窗口可见时完全不碰 `ShowWindow`，最小化时按 `WPF_RESTORETOMAXIMIZED` 决定是否补 `SW_MAXIMIZE`。
- 修复 `Toggle DSH Window` 永远走唤起逻辑：原判据要求 DSH 是前台窗口，但热键触发时前台是 Raycast 的 HUD。现在按 z 序找「真正的应用窗口」，`WS_EX_TOOLWINDOW` 的启动器窗口天然被排除。
- 报告新增 `inFront` 字段，`DSH Status` 显示窗口是否在最前。

## [Initial Version] - 2026-10-05

- `Toggle DSH Window`：窗口在前台时隐藏到通知区域，否则唤起并聚焦。用来绑全局热键。
- `Show DSH Window` / `Hide DSH Window`：独立的唤起与隐藏命令。
- `DSH Status`：进程、窗口、安装路径、harness home 与会话数一览，并可从列表中执行全部操作。
- 窗口控制由内嵌 C# 的 Win32 助手完成，首次运行编译到 `%LOCALAPPDATA%\RaycastDsh` 以避开 PowerShell 启动开销。
- 处理了两处平台陷阱：`dsh://open` 无法恢复已隐藏的窗口；`windowsHide` 会让进程的第一次 `ShowWindow` 被 STARTUPINFO 覆盖。
