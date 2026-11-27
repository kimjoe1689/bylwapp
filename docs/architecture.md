# 架构对照 / Architecture mapping

论文里的床旁信息亭仍是论证结构。当前代码没有 ESP32，也没有改论文正文。手机应用加上三只 BLE 设备承担原来信息亭的采集角色，Go + SQLite 承担原来 Firebase 的副本和授权角色。

| 论文里的部分 Thesis component | 现在的实现 Current implementation |
| --- | --- |
| 床旁传感器与界面 kiosk sensors and bedside UI | `app/` 里的 Flutter 采集端，外加鱼跃 YE680B、迈金 H303、Colmi/Yawell R09/R05。解析器仍在 `app/lib/ble/`。 |
| 事件身份 event_id + payload_hash | `bylw-measure/1`。哈希是规范 JSON 的 SHA-256，见 `server/schema` 与 `app/lib/journal/canonical_event.dart`。 |
| MicroSD 本地日志 local-first journal | 手机 SQLite `journal` 表。写入后再读回核对哈希，才允许上传。 |
| 同步工人 sync worker | `app/lib/sync/sync_worker.dart`，以及 `server/devicesim` 彩排。支持自动同步和“立即同步”。 |
| Firebase Realtime Database | `POST/GET /api/v1/devices/{device_id}/events/{event_id}`。相同 id 且哈希相同是 duplicate；哈希不同是 conflict，保留第一份回执。 |
| Firebase Auth 与默认拒绝的规则 | 采集端设备令牌；护理者 / 管理员登录。未携带凭据拒绝访问。设备令牌不能看后台，护理者不能签发令牌。 |
| 护理者仪表板 dashboard | `server/internal/web/index.html`：最近 100 条、每台采集端状态、同步是否偏旧、冲突、测量趋势。 |
| 降级状态 degraded operating state | `NOMINAL`、`BLE_DISCONNECTED`、`NETWORK_DEGRADED`、`AUTH_FAILURE`、`CLOCK_DEGRADED`。调试页可以注入断网、提交后超时和时钟异常。 |
| 独立 ground truth | `ground_truth` 表、CSV 导入、应用里的对照账。RQ2 只在 match_key 对上时计算混淆矩阵。 |
| Chapter 4 导出 | `/api/v1/exports/rq1.json` 到 `rq4.json`，以及事件 CSV/JSON 和对账 JSON。分母为 0 时状态是 `not_evaluable`，不填一个假装测出来的比率。 |

这些导出是证据格式，不是已经完成的实验结果。
