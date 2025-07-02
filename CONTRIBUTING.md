# Contributing to stools

欢迎参与 `stools` 项目的开发与完善！这是一个轻量级的 Linux 命令行工具箱，旨在为用户提供便捷、可扩展的脚本工具集。我们热忱欢迎任何形式的贡献，包括代码、文档、脚本、测试和建议。

---

## 📌 快速开始

### 1. Fork & Clone 项目

```bash
git clone https://github.com/YOUR_USERNAME/stools.git
cd stools
git checkout -b feature/your-feature-name
```

### 2. 添加你的功能或修复
- 所有工具脚本建议放在 `tools/` 目录中
- 工具需包含帮助信息（如 `-h` 或 `--help`）
- 保持代码风格一致，尽量遵循 Bash 脚本规范

### 3. 提交修改
```bash
git add .
git commit -m "feat: 添加 xxx 工具"
git push origin feature/your-feature-name
```

### 4. 创建 Pull Request
- 到你的 GitHub 仓库页面点击 `Compare & pull request`
- 填写修改说明，确保 PR 信息清晰

---

## 📂 目录结构说明

```bash
stools/
├── stl/              # 主命令框架
├── tools/            # 用户自定义工具目录
├── meta/             # 框架元信息与配置
├── README.md
└── CONTRIBUTING.md   # 贡献指南（本文件）
```

---

## ✅ 开发建议
- 请勿直接在 `main` 分支上提交代码
- 保持修改原子化，尽量每个 PR 只做一件事
- 对于修改核心框架的提交，请添加详细说明
- 如果你不确定某项修改是否合适，欢迎先提交 issue 讨论

---

## 🙌 其他贡献方式
- 编写或改进文档与教程
- 报告 Bug 或提出功能建议（Issues）
- 帮助 review 其他开发者的 PR

---

## 📞 联系方式
如有疑问或想交流想法，请在 Issues 区留言，或联系项目作者：[frogchou](https://github.com/frogchou)

---

愿我们一起打造一个有趣、有用、值得依赖的 Linux 工具箱项目！✨
