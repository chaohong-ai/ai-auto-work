---
description: 提交Bug到对应版本的功能文档中
argument-hint: <version> <feature_name> <bug描述>
---

## 参数解析

用户传入的原始参数：`$ARGUMENTS`

**参数格式：** `<version> <feature_name> <bug描述>`

- `version`：版本号，第一个空格分隔段
- `feature_name`：功能名称，第二个空格分隔段
- `bug描述`：Bug 的现象描述，剩余内容

**参数缺失处理：**
1. **三个参数都有** → 直接执行
2. **缺少 bug 描述** → AskUserQuestion 询问
3. **只有 version** → AskUserQuestion 询问功能名称和描述
4. **参数为空** → AskUserQuestion 一次性询问全部

---

## 执行流程

### 第一步：确定文件路径

Bug 文档路径：`Docs/Bug/$version/$feature_name.md`
图片目录路径：`Docs/Bug/$version/images/`

### 第二步：检查并创建目录结构

1. 检查 `Docs/Bug/$version/` 是否存在，不存在则创建
2. 检查 `Docs/Bug/$version/images/` 是否存在，不存在则创建

### 第三步：询问是否有截图

用 AskUserQuestion 询问：是否有相关截图？如果有提供路径，没有则跳过。

**图片处理：**
1. 复制到 `Docs/Bug/$version/images/`
2. 命名：`$feature_name_bugN_原始文件名`
3. 在 Bug 描述中追加图片引用

### 第四步：写入 Bug 条目

- **文件存在** → 在 `# 未修复bug` 部分追加
- **文件不存在** → 创建新文件

**格式：**
```markdown
# 未修复bug
- [ ] [bug描述]
```

有图片时：
```markdown
- [ ] [bug描述]
  - **截图**：
    - ![截图](images/feature_name_bugN_filename.png)
```

### 第五步：输出确认

```
已提交 Bug 到 Docs/Bug/$version/$feature_name.md：
- [ ] [bug描述]
```

---

## 禁止事项

1. **禁止修改已有 Bug 条目**：只追加新条目
2. **禁止分析或修复 Bug**：本命令只记录，修复用 `/bug/fix`
3. **禁止创建多余文件**
