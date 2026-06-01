# WindLab

WindLab 是一个使用 SwiftUI 开发的 macOS 风资源数据分析原型应用，目标是提供类似 Windographer 的本地数据浏览、统计和可视化能力。

## 已实现功能

- 打开 `.windog` 文件并解析测风数据、字段信息和时间序列。
- 支持导入 `.txt`、`.csv`、`.tsv` 数据文件，并在导入时打开配置窗口确认字段类型、单位、高度、颜色和可见性。
- Summary 页面展示数据集属性、环境条件、风速与风功率、风切变系数。
- Summary 中可根据实际数据计算：
  - 接近 100 m 高度的平均风速。
  - 50 m 风功率密度。
  - 按 50 m 风功率密度划分 Wind Power Class。
- Time Series 页面支持原始数据、逐日平均、逐月平均、逐年平均显示。
- Time Series 支持风速、风向和其它字段选择显示，并支持缩放、框选放大和动态坐标轴。
- Wind Rose 页面支持风向频数、频率、统计量和风能玫瑰图，并提供方向传感器、扇区数、过滤条件等配置。
- Histogram 页面支持风速字段直方图、频率/频数显示、分仓设置、过滤条件和威布尔分布拟合。
- 工具栏中的风速分布分析窗口支持最大似然、最小二乘和 WAsP 风速分布拟合对比。
- Configure Data Set 窗口支持查看和编辑字段配置、数据集信息，并按字段动态显示 PDF、日内平均和月度统计图。
- 提供 `scripts/package_app.sh`，可将 SwiftPM 构建结果打包为 macOS `.app`。

## 项目结构

```text
app/WindLabMac/        SwiftUI macOS 应用
app/WindLabMac/Sources 应用源码
app/WindLabMac/scripts 打包脚本
app/WindLabMac/assets  应用资源
```

## 运行

```bash
cd app/WindLabMac
swift run WindLabMac
```

## 构建

```bash
cd app/WindLabMac
swift build
```

## 打包为 macOS App

```bash
cd app/WindLabMac
./scripts/package_app.sh
```

打包结果默认输出到：

```text
app/WindLabMac/dist/WindLab.app
```

## 说明

实际 windog 文件格式仍在逐步补全兼容，遇到新的文件结构时可能需要继续扩展解析逻辑。
