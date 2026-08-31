# 章节代理来源与主审记录

用户已确认提纲与一次性交付完整 Markdown 初稿。paper-orchestration 要求每个主要章节由独立代理承担；主代理持有证据映射、复核日志和最终合并文件，逐章完整阅读并执行两阶段审阅。本轮代理仅修改各自章节，没有修改 RTL、Python Golden 或原有综合报告。

## 已接受章节

- chapters/01_requirements.md | agent=/root/chapter_requirements | packet=plan/task-packets/01_requirements.md | status=ACCEPTED | reviewer=/root | 核对两版官方文档的算法要求与平台歧义；未将省略 DDR 描述推断为正式豁免。
- chapters/02_architecture.md | agent=/root/chapter_architecture | packet=plan/task-packets/02_architecture.md | status=ACCEPTED | reviewer=/root | 核对无 ready 流接口、中心坐标、级联重编号、两种存储后端和整机边界。
- chapters/03_algorithms.md | agent=/root/chapter_algorithms | packet=plan/task-packets/03_algorithms.md | status=ACCEPTED | reviewer=/root | 核对误差参考域、固定系数、公式、位宽与有效边界；纠正“核心已向外提供灰度旁路”的不准确表述。
- chapters/04_rtl.md | agent=/root/chapter_rtl | packet=plan/task-packets/04_rtl.md | status=ACCEPTED | reviewer=/root | 核对 XPM 同址读写、同步读时序、两行轮转、中值组合网络及厂商替换责任。
- chapters/05_verification.md | agent=/root/chapter_verification | packet=plan/task-packets/05_verification.md | status=ACCEPTED | reviewer=/root | 独立运行 5 项 Golden、全输入域数学穷举与 12 个 XSIM 顶层；区分小帧逐码与大帧计数；补入已查看的既有图像及独立零阈值诊断记录。
- chapters/06_integration.md | agent=/root/chapter_integration | packet=plan/task-packets/06_integration.md | status=ACCEPTED | reviewer=/root | 核对摄像头、CDC、显示、配置和 DDR 均为方案而非完成项；补充异常整帧丢弃不能证明基础无丢帧要求已满足。
- chapters/07_conclusion.md | agent=/root/chapter_conclusion | packet=plan/task-packets/07_conclusion.md | status=ACCEPTED | reviewer=/root | 结论限定在算法与指定用例验证；Ti60 时序、帧率、功耗和真实图像检测质量未作完成断言。

ACCEPTED 表示章节作为含真实待完成项的工程初稿已接受，不表示其中计划实施的硬件功能已经实现。

