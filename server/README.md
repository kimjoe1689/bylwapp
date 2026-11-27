# bylwapp 服务端

Go 管理后台。SQLite 使用纯 Go 驱动 `modernc.org/sqlite`，`CGO_ENABLED=0` 即可编译。

```bash
make test
make run
```

默认监听 `:8080`，数据库文件是 `data/bylw.db`。也可以用环境变量或参数：

```bash
BYLW_ADDR=:9090 BYLW_DB=/tmp/bylw.db go run ./cmd/server
go run ./cmd/server -addr :9090 -db /tmp/bylw.db
```

浏览器打开 `http://127.0.0.1:8080`。接口说明见仓库根目录的 README。
