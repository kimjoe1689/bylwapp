# bylwapp 客户端

Flutter 应用，目标平台是 Android 和 iOS。本地数据库是 SQLite（`sqflite`），蓝牙使用 `flutter_blue_plus`。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

首页显示本机测量记录，设置页填写服务端地址，扫描页连接鱼跃 YE680B、迈金 H303，或 Colmi R09 / Yawell R05 戒指。

没有真机时，`flutter test` 用样例字节覆盖血压 SFLOAT、心率标志位和戒指报文。连接、indicate/notify 和体温记录是否真正开始，需要实机确认。
