# 学习通 OA 自动化

学习通 OA 请假 / 销假自动化脚本。

> 公开仓库版本不包含 Cookie、抓包文件、定位、照片或个人预填信息。运行所需的敏感参数请通过 GitHub Actions Secrets 或本地环境变量提供。

## 项目结构

```text
.
├── leave/                  # 请假自动化
│   └── submit.sh           # 请假主脚本
├── cancel/                 # 销假自动化
│   └── submit.sh           # 销假主脚本
├── docs/                   # 公开说明页（无个人信息）
├── .github/workflows/      # GitHub Actions
│   ├── leave.yml           # 每周四请假提交
│   └── cancel.yml          # 每周日销假提交
└── cookies                 # 本地 Cookie（不提交到 Git）
```

## 依赖

```bash
pip install pycryptodome
```

## GitHub Actions Secrets

公开仓库使用前，需要在 GitHub 仓库 Settings → Secrets and variables → Actions 中配置：

| Secret | 用途 |
| --- | --- |
| `CHAOXING_COOKIES` | 学习通登录 Cookie |
| `LEAVE_PHOTO_URL` | 请假面部拍照图片链接 |
| `CANCEL_LAT` | 销假定位纬度 |
| `CANCEL_LNG` | 销假定位经度 |
| `CANCEL_ADDRESS` | 销假定位地址 |

## 请假自动提交

- 脚本：`leave/submit.sh`
- 工作流：`.github/workflows/leave.yml`
- 定时：每周四 UTC 1:07（北京时间 9:07）
- 本地运行：

```bash
CHAOXING_COOKIES='...' LEAVE_PHOTO_URL='https://example.com/photo.jpg' bash leave/submit.sh
```

请假脚本会自动计算周五 12:00 到周日 18:00 的请假时间，并通过 `LEAVE_PHOTO_URL` 填入面部拍照字段。

## 销假自动提交

- 脚本：`cancel/submit.sh`
- 工作流：`.github/workflows/cancel.yml`
- 定时：每周日 UTC 12:00（北京时间 20:00）
- 本地运行：

```bash
CHAOXING_COOKIES='...' \
CANCEL_LAT='纬度' \
CANCEL_LNG='经度' \
CANCEL_ADDRESS='定位地址' \
bash cancel/submit.sh
```

销假脚本会使用运行时北京时间作为销假申请时间，并通过环境变量填入定位信息。

## Cookie 更新

1. 浏览器打开 https://office.chaoxing.com 并登录
2. F12 → Application → Cookies → 复制所有 cookie（`key=value; key=value` 格式）
3. GitHub Actions：更新 Secret `CHAOXING_COOKIES`
4. 本地运行：写入根目录 `cookies` 文件，或直接使用环境变量 `CHAOXING_COOKIES`

## 公开仓库注意事项

不要提交以下内容：

- `cookies`
- `*.har`
- `*.log`
- 本人照片或包含 EXIF 的图片
- 真实定位、学号、姓名、审批记录等个人信息
