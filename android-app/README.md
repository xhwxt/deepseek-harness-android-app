# android-app/ —— APK 构建工程

把 DSH 内核 + node 运行时 + 移动端适配打包成可直接安装的 Android APK（`DeepSeekHarness.apk`）。

## 目录结构

```
android-app/
├── build.sh              一键打包脚本（7 步：组装 payload → aapt → javac → d8 → 打包 → zipalign → 签名）
├── env.sh                编译工具链环境（可 export PREFIX 覆盖工具链位置）
├── AndroidManifest.xml   包名/targetSdk(28)/自由旋转/Shizuku 声明/版本号（versionCode/versionName）
├── libs/                 Shizuku 官方 aar（api/provider/aidl）
├── res/                  图标 + 字符串资源
├── sdk/                  放 platform android.jar（见 sdk/README.md，不入仓库）
├── src/.../MainActivity.java  Android 原生壳（权限引导页/加载页/引擎启动/看门狗）
└── release.jks           签名密钥（⚠️ 不入仓库，仅本机构建用）
```

## 构建环境（必备）

构建需要**完整开发环境**（不在本仓库内，见 `docs/开发指南.md` 第三节）：

- `runtime/` —— node v26 运行时（bionic 版：`bin/node` + `lib/*.so`）
- `dshroot/` —— DSH 内核（`@deepseek-ai/dsh`，含 Android 补丁）
- `build/` —— 编译工具链（aapt / javac / d8 / zipalign / apksigner）
- `.dsh/` —— DSH 配置（cordis.patch.yml / settings.yaml / profiles/web）
- `release.jks` —— 签名密钥

统一通过 `DSH_DEV_HOME` 指向（结构见 `docs/开发指南.md`）。App 内实例：`/data/user/0/com.deepseek.harness/files/buildenv/devhome`。

## 打包命令

```sh
export DSH_DEV_HOME=<devhome 路径>   # 含 runtime/dshroot/build/.dsh/rish
export JAVA_BIN=<java-17/bin 路径>   # javac 所在目录
export ANDROID_JAR=<android.jar 路径>
export KEYSTORE_PASS=<签名密码>
export KEYSTORE_ALIAS=dsh
sh build.sh
# 产物：android-app/DeepSeekHarness.apk
```

## build.sh 关键点

- **第 0 步**自动注入移动端适配（`sh ../mobile-patch/inject.sh`），payload 随 APK 打包
- **安全检查**：payload 里发现 `sk-` 密钥或 `.credentials.yaml` 立即中止
- **防坏包**：javac 失败立即中止（不再吞错）；`classes.dex` 必须含 `MainActivity` 才放行（v1.2.0 曾因缺校验产出安装即闪退的坏包）
- **soname 实体化**：按 `LINKS.txt` 把版本化 .so 复制成同名实体文件（jar 打包会压平软链，否则 node 起不来）
- **版本标记**：`dshroot_revision.txt`（assets）用于 App 判断外部 `/sdcard/DeepSeekHarness/dshroot` 是否需要补齐

## 版本号修改

改 `AndroidManifest.xml` 的 `android:versionCode` / `android:versionName` 后重新打包（小改动可走快速重打包：`jar uf` 就地更新 + zipalign + 重签）。

## 注意

- ⚠️ **targetSdk 必须保持 28**（≥29 时 Android 把私有目录挂 noexec，node 起不来）
- `release.jks` 与密码**绝不提交仓库**（.gitignore 已排除）
- 安装包自测方法（防 ERR_CONNECTION_REFUSED）：抽出 payload 实测引擎 HTTP 200，见 `docs/开发指南.md` / `交接文档.md`

## 变体：正式版 / 共存修复版（v1.13.7 新增）

```sh
sh build.sh            # 正式版     com.deepseek.harness        端口 3080  /sdcard/DeepSeekHarness
sh build.sh coexist    # 共存修复版 com.deepseek.harness.fix    端口 3086  /sdcard/DeepSeekHarnessFix
# 产物：android-app/DeepSeekHarness.apk / android-app/DeepSeekHarness-fix.apk
```

共存版与正式版**包名不同**，可同时安装、互不覆盖：

| | 正式版 | 共存修复版 |
|---|---|---|
| 包名 | `com.deepseek.harness` | `com.deepseek.harness.fix` |
| 引擎端口 | 3080（通知 3081 / 无障碍 3181） | 3086 |
| 外部目录 | `/sdcard/DeepSeekHarness` | `/sdcard/DeepSeekHarnessFix` |
| provider authority | `…harness.shizuku` / `…harness.logshare` | `…harness.fix.shizuku` / `…harness.fix.logshare` |

实现（`build.sh` 里那段 `case "$VARIANT"`）：源码目录结构完全不动，只在打包时把 manifest 的
`package`、两个 provider authority 换掉，并把**组件名展开成绝对包名**——`.MainActivity` 在 `.fix`
包下会被解析成 `com.deepseek.harness.fix.MainActivity`，不展开就是启动即 ClassNotFound；
同时用 `aapt --custom-package com.deepseek.harness` 让 `R.java` 仍生成在原包，否则 javac 找不到 R。

⚠️ 共存版是**另一个 App**：应用私有数据（API Key / 会话 / 凭证）不与正式版共享，
首次打开需要在设置页重新填一次 API Key；外部目录也是独立的，不会动正式版的数据。

### 共存版的虚拟屏端口隔离（v1.13.8）

正式版与共存版各自独立的 vscreen 桥与核心（此前写死 8999/8998，两版同装时正式版先占用，
共存版桥 `bind` 静默失败 → **它的预览窗根本建不出来**，用户看到的其实是正式版的预览窗）：

| | 正式版 | 共存修复版 |
|---|---|---|
| 桥接端口（插件 → App） | 8999 | **9009** |
| 核心端口（特权 app_process） | 8998 | **9008** |

App 把桥端口通过环境变量 `APP_VS_PORT` 下发给引擎，插件 `dsh-tool-vscreen` 读它
（`Number(process.env.APP_VS_PORT || 8999)`）。

⚠️ **打包前必须把仓库里的插件同步进 devhome**，否则 payload 里还是旧插件（build.sh 组装
payload 时插件取自 `$DSH_DEV_HOME/dshroot`，仓库 `plugins/` 只是归档）：

```sh
sh plugins/sync-to-devhome.sh "$DSH_DEV_HOME"    # 幂等；改动会备份成 index.js.bak-*
```

### 虚拟屏预览窗（v1.13.8）

- 右上角只有两个钮：`✕` 关闭预览窗（虚拟屏继续跑）、`▾` 最小化 / 展开（只留按钮栏）
- **缩放一律用双指捏合**，不加缩放键
- 建窗 / 双指缩放 / 拖动 / 折叠，**所有**改窗口几何的路径都走 `clampPreviewBounds()`：
  最大占屏 70%（宽与可用高），并扣掉状态栏占位（真机实测窗口坐标系偏移 133px）
  —— 保证按钮条永远在屏幕内可点
