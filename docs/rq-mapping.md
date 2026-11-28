# RQ 功能与导出

论文正文没有改。下表只说明代码现在能记录什么、从哪里导出。没有数据时指标是 `not_evaluable`。

| 论文端点 Thesis endpoint | 实现 Feature | 导出 Export |
| --- | --- | --- |
| RQ1 提醒投递、确认、错过、删失、时延 | 应用内服药/喝水提醒。到期后写入 `COMMAND_LOGGED`，确认分为 `ACK_TIMELY` / `ACK_DELAYED`，超时为 `MISSED`，观察不完整可标 `CENSORED`。`delay_ms` 写在事件里。 | `GET /api/v1/exports/rq1.json`。设备日志给出确认率和错过率；观察者投递率要有 `reminder_eligible` 与 `reminder_perceived` 对照行。 |
| RQ2 与独立对照比较 | 心率接触状态写成 `worn_state`。照护逾期是运营规则：提醒未确认，或配置窗口内没有新测量。观察者用对照账或 CSV 记下 `worn`、`data_gap`、`care_attention`。 | `GET /api/v1/exports/rq2.json`。只统计 device_id + match_key 对上的行。对不上的记入 unmatched，不当成错。 |
| RQ3 持久化、同步、恢复 | SQLite 日志先确认再上传。重复提交返回 duplicate，冲突保留第一份。超时后用读回核对。调试页和 `tools/device-sim` 可注入断网、超时、时钟偏移。 | `GET /api/v1/exports/rq3.json` 与 `/api/v1/exports/reconciliation.json`。服务器看不到仍留在手机上的 pending，也不估计数据丢失。 |
| RQ4 可用性 | 大字高对比模式、任务计时与处置（独立完成 / 协助 / 放弃）、10 题 SUS。缺一题就不算总分。 | `GET /api/v1/exports/rq4.json`。这不是伦理审批后的正式受试记录。 |
| 最近 100 条与设备状态 | 管理页列表、趋势图、同步偏旧、冲突。 | `GET /api/v1/dashboard/events`、`/dashboard/devices`、`/dashboard/series`、`/exports/events.csv`、`/exports/events.json`。 |
