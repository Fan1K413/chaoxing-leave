# 学习通 OA 自动化

用于自动提交学习通 / 超星 OA 的请假与销假申请。

本仓库是公开版模板，不包含 Cookie、抓包文件、照片、定位、姓名、学号等个人敏感信息。运行所需的私密参数通过 GitHub Actions Secrets 或本地环境变量提供。

## 功能

- 每周四自动提交请假申请
  - 请假时间：周五 12:00 至周日 18:00
  - 申请日期：运行当周周四
- 每周日自动提交销假申请
  - 销假时间：运行时北京时间
- 支持 GitHub Actions 定时运行
- 支持本地手动运行
- 提供模拟请假页面
  - 可在浏览器中填写、上传面部照片、手写签名并模拟提交
  - 自动缓存除时间/日期外的填写内容，以及上传照片和签名

## 目录结构

```text
.
├── leave.sh                   # 请假提交脚本
├── cancel.sh                  # 销假提交脚本
├── .github/workflows/
│   ├── leave.yml              # 请假定时任务
│   └── cancel.yml             # 销假定时任务
├── docs/
│   ├── index.html             # 公开说明页
│   └── simulation/
│       ├── index.html         # 模拟请假页面结构；不预置照片或签名图片
│       ├── simulation.css     # 模拟页样式
│       └── simulation.js      # 模拟页交互、缓存和提交演示逻辑
├── .gitignore
└── README.md
```

## GitHub Actions 定时

| 工作流 | 文件 | 时间 |
| --- | --- | --- |
| 请假 | `.github/workflows/leave.yml` | 每周四 09:07（北京时间） |
| 销假 | `.github/workflows/cancel.yml` | 每周日 20:00（北京时间） |

两个工作流都支持在 GitHub Actions 页面手动触发。

## 需要配置的 Secrets

进入 GitHub 仓库：

```text
Settings → Secrets and variables → Actions → New repository secret
```

添加以下 Secrets：

| Secret | 说明 |
| --- | --- |
| `CHAOXING_COOKIES` | 学习通 / 超星 OA 登录 Cookie |
| `LEAVE_PHOTO_URL` | 请假面部拍照图片链接 |
| `CANCEL_LAT` | 销假定位纬度 |
| `CANCEL_LNG` | 销假定位经度 |
| `CANCEL_ADDRESS` | 销假定位地址 |

### `CHAOXING_COOKIES`

浏览器登录 https://office.chaoxing.com 后复制完整 Cookie。

格式示例：

```text
key1=value1; key2=value2; key3=value3
```

只需要填 Cookie 内容，不要带 `Cookie:` 前缀。

### `LEAVE_PHOTO_URL`

填一张可被 GitHub Actions 访问的图片链接，例如：

```text
https://example.com/photo.jpg
```

不要把本人照片直接提交到公开仓库。

### 销假定位

`CANCEL_LAT`、`CANCEL_LNG` 填数字字符串，`CANCEL_ADDRESS` 填地址文本。

示例：

```text
CANCEL_LAT=36.000000
CANCEL_LNG=117.000000
CANCEL_ADDRESS=山东省济南市...
```

## 模拟请假页面

打开 `docs/simulation` 可以在浏览器里模拟请假表单填写与提交，适合提前检查页面展示效果。

公开仓库不预置默认照片或签名图片。首次打开时需要自行上传面部照片并手写签名；完成后这些内容会缓存在当前浏览器中，下次打开同一页面会自动恢复。

页面资源已拆分为 `index.html`、`simulation.css` 和 `simulation.js`。样式文件只保留模拟页需要的表单、上传、签名、审批流程和自定义控件样式；本地小图标资源以内嵌 data URI 保存在 CSS 中，避免额外维护 assets 目录。提交后可通过数据日志右侧图标筛选上方详情表单中显示的字段；其中“审批操作”仅控制数据日志中的审批操作卡，不影响上方流程、数据日志区域或创建记录。该显示设置仅在当前页面会话中生效，不会写入本地缓存。

### 自动缓存

模拟页会把以下内容保存到当前浏览器的 `localStorage`，下次打开同一页面会自动恢复：

- 姓名、学号、年级、院系、专业、班级
- 宿舍号
- 辅导员姓名、辅导员工号
- 请假类型、是否出校、是否出市、是否出省
- 上传的面部照片
- 手写签名

不会缓存以下时间类字段，它们每次打开都会按页面逻辑重新生成：

- 请假开始时间
- 请假结束时间
- 请假申请时间
- 请假时长

面部照片会先压缩后再写入本地缓存，避免浏览器缓存空间不足；如果图片过大导致无法缓存，当前页面仍可继续使用，但刷新后可能需要重新上传。提交详情中，面部照片文件右下角的下载图标会下载图片：当前页面会话优先下载原始上传文件；刷新后则下载本地缓存版本，缓存过程中图片可能被压缩为 JPEG。

## 本地敏感文件

本地调试时可能会用到 Cookie、抓包文件或照片，这些都不要提交到公开仓库：

- `cookies`：本地 Cookie 文件，脚本会自动读取
- `har/`：本地抓包文件统一存放目录，建议按用途命名，例如 `har/leave-office.chaoxing.com.har`、`har/cancel-office.chaoxing.com.har`
- `*.jpg`、`*.png` 等图片：不要把本人照片放进 Git 记录

`.gitignore` 已忽略 `cookies`、`*.har` 和常见图片格式。整理抓包文件时可以统一放到 `har/` 目录，并在文件名里标明用途（如 `leave-` / `cancel-` 前缀），方便之后区分；该目录里的 `.har` 文件不会被 Git 提交。

## 本地运行

### 安装依赖

```bash
pip install pycryptodome
```

### 本地 Cookie

如果不想每次传环境变量，可以在仓库根目录创建 `cookies` 文件：

```text
key1=value1; key2=value2; key3=value3
```

该文件已被 `.gitignore` 忽略，不会提交。

### 请假

```bash
CHAOXING_COOKIES='你的 Cookie' \
LEAVE_PHOTO_URL='https://example.com/photo.jpg' \
bash leave.sh
```

或使用根目录 `cookies` 文件：

```bash
LEAVE_PHOTO_URL='https://example.com/photo.jpg' bash leave.sh
```

### 销假

```bash
CHAOXING_COOKIES='你的 Cookie' \
CANCEL_LAT='纬度' \
CANCEL_LNG='经度' \
CANCEL_ADDRESS='地址' \
bash cancel.sh
```

或使用根目录 `cookies` 文件：

```bash
CANCEL_LAT='纬度' \
CANCEL_LNG='经度' \
CANCEL_ADDRESS='地址' \
bash cancel.sh
```