# bylwapp

bylwapp 是一个蓝牙健康数据应用，仓库分成两部分：

- `server/`：Go 管理后台，接收客户端上传的测量记录，并在浏览器里查看。
- `app/`：Flutter 客户端，连接血压计、心率带和智能戒指，把数据记在本机 SQLite，再上传到后台。

业务目前就是这三类测量。设备型号可以替换，协议解析和存储字段是按标准蓝牙剖面以及 QRing 戒指明文协议写的。

## 仓库结构

```text
bylwapp/
├── app/          Flutter 客户端（Android、iOS）
├── server/       Go 管理后台
├── Makefile      转到上面两个子项目的常用命令
└── .github/workflows/ci.yml
```

## 架构

```text
血压计 / 心率带 / 戒指
        │  BLE
        ▼
Flutter 设备驱动（解析报文）
        │
        ▼
本机 SQLite（sqflite）
        │  HTTP POST /api/sync
        ▼
Go API（chi）── SQLite（modernc.org/sqlite，无 CGO）
        │
        ▼
浏览器管理页  /
```

客户端按广播名和服务 UUID 选择驱动：

| 驱动 | 目标设备 | 蓝牙剖面 |
| --- | --- | --- |
| 标准血压 | 鱼跃 YE680B（蓝牙版） | Blood Pressure `0x1810`，测量特征 `0x2A35`（indicate），数值为 IEEE-11073 SFLOAT。可选对时：`0x2A08`，或 Current Time `0x1805` / `0x2A2B` |
| 标准心率 | 迈金 H303 胸带 | Heart Rate `0x180D`，测量特征 `0x2A37`（notify），支持 uint8/uint16、佩戴状态、能耗和 RR 间期 |
| QRing 戒指 | Colmi R09、Yawell R05，以及同协议的 R02/R03/R06/R07/R10/R12 | Gadgetbridge `yawell/ring` 的明文协议。实时和历史：步数、心率、血氧、睡眠、压力、HRV；体温仅 R09/R05，且必须先打开体温记录 |

戒指报文是 16 字节，最后一字节是前面载荷的校验和。SpO2、睡眠、体温走 big-data v2，载荷使用 CRC-16/MODBUS。实现对照的是 Gadgetbridge 的协议行为，没有把上游源码拷进本仓库。

## 环境

- Go 1.27.4 或更新版本。`modernc.org/sqlite` 当前版本要求 Go 1.26 以上，这样可以不开 CGO、方便交叉编译。
- Flutter stable（本仓库在 Flutter 3.50.1 / Dart 3.14.0 上跑过 `flutter analyze` 和 `flutter test`）。
- 客户端测试在 Linux 上需要系统里的 `libsqlite3.so.0`。

## 运行服务端

```bash
cd server
make test
make run
```

然后打开 <http://127.0.0.1:8080>。页面可以录入一条测量、按类型筛选，也可以删除设备和记录。

监听地址和数据库路径：

```bash
# 环境变量
BYLW_ADDR=:9090 BYLW_DB=/tmp/bylw.db make -C server run

# 参数优先于环境变量
cd server && go run ./cmd/server -addr :9090 -db /tmp/bylw.db
```

交叉编译示例：

```bash
cd server
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o bin/bylw-server ./cmd/server
```

启动时会自动执行 `server/internal/migrate/sql` 里的迁移。重复启动不会重放已经记入 `schema_migrations` 的脚本。

服务端没有登录。不要把它暴露到公网。

## 运行客户端

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

- 首页列出本机测量，底部按钮把未上传的记录 `POST` 到 `/api/sync`。
- 设置页保存服务器根地址，默认 `http://127.0.0.1:8080`。手机访问电脑上的服务时，要改成电脑的局域网地址。
- 扫描页连接设备。血压计可以对时，戒指可以拉历史。R09/R05 同步前会先写体温记录开关。

`flutter_blue_plus` 2.x 把个人、非营利和教育用途标成 `License.nonprofit`。如果这个应用以后商用，需要改成 `License.commercial` 并取得对方的商业授权。

## HTTP API

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/health` | 健康检查，顺带 ping 数据库 |
| `GET` | `/`、`/admin` | 管理页 |
| `GET` `POST` | `/api/devices` | 设备列表、创建设备 |
| `GET` `PUT` `DELETE` | `/api/devices/{id}` | 查询、改名称/种类/型号、删除（级联删除测量） |
| `GET` `POST` | `/api/measurements` | 列表和单条创建。列表支持 `device_id`、`type`、`from`、`to`、`limit` |
| `GET` `PUT` `DELETE` | `/api/measurements/{id}` | 查询、整条替换、删除 |
| `POST` | `/api/sync` | 客户端上传。按蓝牙地址写入或更新设备，相同设备、类型和时间的记录会跳过 |

`/api/sync` 的请求体：

```json
{
  "device": {
    "name": "YE680B",
    "kind": "blood_pressure",
    "address": "AA:BB:CC:DD:EE:01",
    "model": "Yuwell YE680B"
  },
  "measurements": [
    {
      "type": "blood_pressure",
      "unit": "mmHg",
      "recorded_at": "2026-11-27T08:15:09Z",
      "values": {"systolic": 120, "diastolic": 80, "pulse": 72}
    }
  ]
}
```

`kind` 只能是 `blood_pressure`、`heart_rate`、`ring`。

`type` 可以是 `blood_pressure`、`heart_rate`、`steps`、`spo2`、`sleep`、`sleep_session`、`stress`、`hrv`、`temperature`。`values` 必须是 JSON 对象，字段随类型变化，例如心率的 `bpm` 和 `rr_intervals_ms`，睡眠的 `stage` 和 `duration_min`，体温的 `celsius`。

## 测试

```bash
make server-test
make app-test
```

服务端测试覆盖配置优先级、迁移可重复执行、健康检查、同步去重和管理页。客户端测试用样例字节覆盖：

- 血压 SFLOAT（含 NaN、无穷和一位小数）以及 `0x2A35` 标志位
- 心率 `0x2A37` 的 uint8/uint16、佩戴状态、能耗和 RR
- 戒指 16 字节校验和、CRC-16/MODBUS、活动/心率/血氧/睡眠/压力/HRV/体温解码，以及历史同步状态机

## 还没在真机上验证的部分

开发环境里没有蓝牙硬件，下面这些在代码里标了 `TODO(hardware)`：

- YE680B 实际暴露的是 `0x2A08` 还是 Current Time，以及 indicate 在 iOS 上的表现
- H303 是否完全按标准心率剖面通知，有没有厂商附加字节
- 戒指连接后的 MTU、分包、无应答超时，以及 R09/R05 写入体温开关后是否真的开始记录
- 戒指时间没有时区字段，当前把表盘时间当成 UTC 存储
- `flutter_blue_plus` 的扫描和连接只在代码路径里接好，没有实机日志

解析和上传本身不依赖真机，可以用上面的单元测试和管理页手动录入检查。
