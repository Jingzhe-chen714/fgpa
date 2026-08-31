# 独立 Windows EDA 进程

`Start-DetachedEdaTool.ps1` 通过本机 `Win32_Process` WMI 服务隐藏启动
`run_detached_tool.py` worker。worker 调用 `IsProcessInJob`，只有确认
`worker_in_job=false` 才启动目标工具，并把退出码和输出写入独立 status/log。
脚本不会修改系统服务、计划任务或全局环境变量。

本机测试发现，普通 `CREATE_BREAKAWAY_FROM_JOB` 即使成功创建子进程，也可能仍
继承外层 Job；Python 启动器的直接模式会检测并拒绝继续。不要把“分开执行三个
阶段”当成已经脱离 Windows Job 的证据。

## 使用

以下每条工具命令分别启动，确认上一阶段 `state=completed`、`returncode=0`
后再运行下一阶段。WMI访问需要在允许调用本机进程服务的PowerShell会话中执行；
在Codex内应请求相应执行批准，不绕过沙箱。已有log/status会拒绝覆盖。

```powershell
.\case2\scripts\Start-DetachedEdaTool.ps1 `
  -PythonPath 'C:\Users\30982\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  -WorkingDirectory 'D:\contest\2026FPGA\yilingsi\case2\tb\xsim_newguide' `
  -LogPath 'D:\contest\2026FPGA\yilingsi\case2\tb\xsim_newguide\example_xsim.log' `
  -StatusPath 'D:\contest\2026FPGA\yilingsi\case2\tb\xsim_newguide\example_xsim.status.json' `
  -ToolCommandLine '"D:\vivado\vivado\Vivado\2023.1\bin\xsim.bat" tb_c2_mem_to_axi4_adapter_final_sim -runall'
```

使用本机实际Python/Vivado安装路径；`ToolCommandLine` 是一个工具及其参数，
不要合并 `xvlog`、`xelab`、`xsim` 为一个长命令。命令成功返回只代表worker已
创建，必须读取status和仿真PASS标记才能判断工具完成。

日志保留在相应测试/综合目录中，可在当前Codex会话结束后继续检查。

## 本轮完整回归

`Run-NewguideRegression.ps1` 使用上述启动器执行10项功能仿真（含AXI 64/128位）
和1项剩余IP黑盒展开。每一个compile/elaborate/simulate阶段均有自己的独立WMI
worker、status和log；没有用同一个Windows Job包住整套工具。

```powershell
.\case2\scripts\Run-NewguideRegression.ps1 -RunName xsim_my_validation
```

输出写入新的 `case2/tb/<RunName>`，拒绝覆盖已有目录。调用器若被中断，已经启动
的当前工具继续运行，尚未启动的后续步骤不会自动运行。发生超时只报告状态，不杀
正在运行的工具；再次启动前先检查前次status，避免并发写同一工作目录。
