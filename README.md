# AOXFoundationKit

BiliDili 体系的无业务基础包，提供 ModuleKit、路由、服务注册、环境配置、网络状态和通用协议。

## 能力边界

- `ServiceRegistry` / `ModuleManager`：App 组合与模块生命周期
- `SchemeRouter`：带中间件的 URL 路由
- `NetworkMonitor`：并发安全、可重复 start/stop 的网络状态观察
- `AppEnvironment`：加锁的运行环境配置，不承载账号或业务数据
- `UserFacingError`、线程安全集合和基础格式化扩展

本包不依赖 UIKit 业务页面、网络请求实现或播放器，供上层 Package 单向依赖。

## 要求与验证

- Swift 6
- iOS 16+

```bash
xcodebuild \
  -scheme AOXFoundationKit \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## License

MIT
