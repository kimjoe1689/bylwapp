# bylwapp API（Cloudflare Workers + D1）

Go 后台（`server/`）的 HTTP 契约移植。Hono + D1，绑定名 `DB`。管理页 HTML 内联在脚本里，上传一个 ES module 就能跑。密码用 WebCrypto PBKDF2-SHA256（10_000 次），因为 Workers 没有 bcrypt。没有管理员时，第一次请求用 secret 创建。

Go 实现留在仓库里，给本机和局域网用。两边的路径、状态码和 JSON 字段对齐；测试在 `worker/test/contract.test.ts`，对照 `server/internal/httpapi/server_test.go` 和 `server/metrics/rq_test.go`。

## 本地

```bash
cd worker
npm ci
npm test
npm run typecheck
```

测试用 Vitest 和 `@cloudflare/vitest-plugin`（原先的 `@cloudflare/vitest-pool-workers` 已改名，workerd 也更旧，盖不住当前的 `compatibility_date`）。

## 打包

不需要 Cloudflare 登录：

```bash
cd worker
npx wrangler deploy --dry-run --outdir deploy-bundle
node scripts/write-schema.mjs
```

产物：

| 文件 | 用途 |
| --- | --- |
| `worker/deploy-bundle/index.js` | 要上传的单个 ES module。`main_module` 文件名是 `index.js` |
| `worker/deploy-bundle/schema.sql` | `migrations/` 合并后的全部建表语句 |
| `worker/deploy-bundle/index.js.map` | 可选的 source map，运行时不需要 |

`wrangler.toml`：

- `name = "bylwapp-api"`
- `compatibility_date = "2026-11-27"`
- `compatibility_flags = ["nodejs_compat"]`
- D1 binding：`DB`，`database_name = "bylwapp"`，`database_id` 目前是占位 `00000000-0000-0000-0000-000000000000`
- 普通变量：`STALE_AFTER = "15m"`（采集端多久没上报算偏旧）。不设置时代码也按 15 分钟算

## 用 Wrangler 部署

1. `npx wrangler d1 create bylwapp`，把打印出的 `database_id` 填进 `worker/wrangler.toml`。
2. 建表（二选一）：
   - `npx wrangler d1 migrations apply bylwapp --remote`
   - `npx wrangler d1 execute bylwapp --remote --file=deploy-bundle/schema.sql`
3. Secret（都不要写进 toml 或源码）。密码至少 8 位。库里还没有用户时，下一次请求会创建这个管理员；已经有用户则不会覆盖。

```bash
npx wrangler secret put BOOTSTRAP_ADMIN_USER
npx wrangler secret put BOOTSTRAP_ADMIN_PASSWORD
```

4. `npx wrangler deploy`
5. 把自定义域名 `bylw-api.zzjteacher.com` 绑到这个 Worker。

## 用 Cloudflare API 上传单个脚本

不跑 `wrangler deploy` 时，上传 `deploy-bundle/index.js` 这一个模块即可。元数据：

- Worker 名称：`bylwapp-api`
- `main_module`：`index.js`
- `compatibility_date`：`2026-11-27`
- `compatibility_flags`：`["nodejs_compat"]`
- bindings：
  - D1，`name` 必须是 `DB`，`id` 是上一步的 database id
  - plain text，`name` 为 `STALE_AFTER`，`text` 为 `15m`（可省略）
- secrets：`BOOTSTRAP_ADMIN_USER`、`BOOTSTRAP_ADMIN_PASSWORD`
- 先对同一个 D1 执行 `deploy-bundle/schema.sql`（按文件里的语句顺序）

示例 metadata：

```json
{
  "main_module": "index.js",
  "compatibility_date": "2026-11-27",
  "compatibility_flags": ["nodejs_compat"],
  "bindings": [
    { "type": "d1", "name": "DB", "id": "<database_id>" },
    { "type": "plain_text", "name": "STALE_AFTER", "text": "15m" }
  ]
}
```

脚本是 ES module，`export default { fetch }`。没有静态资源绑定。

## 配对码

调试页里的设备令牌仍然可以手贴。管理员登录 `GET /` 后，登记采集端并生成 6 位配对码。采集端调用：

```http
POST /api/v1/devices/pair
Content-Type: application/json

{"code":"123456"}
```

成功是 `201`，正文含 `token` 和 `device_id`。配对码 10 分钟内有效，核销一次后再用会 `400`。App 侧对应 `app/lib/api/device_pairing.dart` 的 `redeemPairingCode`。设置页没有加输入框，避免和正在改 `app/lib/screens` 的另一个改动撞车；现有调试页仍把令牌记在 `CollectorPrefs.deviceToken`。

## 接口

与 `server/internal/httpapi` 相同，另加配对码两条：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/health` | `{"status":"ok","time":...}`，数据库失败是 503 `degraded` |
| `GET` | `/` | 管理页 |
| `POST` | `/api/v1/auth/login` | 管理员 / 护理者，会话 12 小时 |
| `POST` | `/api/v1/devices/{id}/events` | 设备令牌。相同 `event_id` + `payload_hash` 是 duplicate；同 id 不同 hash 是 conflict，保留第一份 |
| `GET` | `/api/v1/devices/{id}/events/{event_id}` | 回读 |
| `GET` | `/api/v1/dashboard/events` `devices` `conflicts` `series` | 护理者或管理员 |
| `GET` | `/api/v1/exports/rq1.json` … `rq4.json` | 分母为 0 时 `not_evaluable` |
| `GET` | `/api/v1/exports/events.json` `events.csv` `reconciliation.json` | |
| `GET` `POST` | `/api/v1/ground-truth` 和 `/import` | 对照账，CSV 列为 device_id, match_key, reference_type, reference_value, observed_at, observer, notes |
| `POST` | `/api/v1/admin/users` `devices` `devices/{id}/tokens` | 仅管理员 |
| `POST` | `/api/v1/admin/devices/{id}/pairing-codes` | 管理员发配对码 |
| `POST` | `/api/v1/devices/pair` | 用配对码换设备令牌 |

CORS 与 Go 版相同：`Access-Control-Allow-Origin: *`，允许 `Authorization, Content-Type`，方法 `GET, POST, OPTIONS`。`OPTIONS` 返回 204。时间用 UTC：健康检查是秒级 RFC3339（`Z`），回执时间是 RFC3339Nano（去掉末尾的 0）。
