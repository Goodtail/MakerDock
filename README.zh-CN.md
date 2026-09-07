<p align="center"><img src="assets/brand/icon-master.png" width="96" alt="MakerDock 应用图标"></p>
<h1 align="center">MakerDock</h1>
<p align="center"><strong>收好每个模型，记住每次打印。</strong><br>为3MF模型收藏与Bambu Studio打造的macOS伴侣应用</p>
<p align="center"><a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · 简体中文 · <a href="README.ja.md">日本語</a></p>
<p align="center"><a href="https://github.com/Goodtail/MakerDock/releases">下载</a> · <a href="#为什么做-makerdock">开发缘由</a> · <a href="#即将推出">后续计划</a> · <a href="Docs/development.md">从源码构建</a></p>
<p align="center">macOS 13及以上 · Apple Silicon / Intel · 免费开源 · MIT</p>

![简体中文界面的MakerDock模型库](Docs/screenshots/zh-Hans/library.png)

## 为什么做 MakerDock？

找到喜欢的模型，下载3MF，在Studio里打开。过了几天想再打印，却想不起文件放在哪里，于是又下载一份。下载文件夹越来越满，但Finder无法告诉你每块打印板上有什么、预计要打多久，更不知道这个模型是否已经打印过。

**MakerDock把下载的模型和实际打印记录放在一起。** 用预览图找模型，直接打开已有文件，再把打印结果留在模型旁边。它配合官方Bambu Studio使用，无需安装修改版切片软件。

## 把杂乱的文件夹变成好用的模型库

| 日常遇到的问题 | MakerDock的解决方式 |
| --- | --- |
| “那个模型存在哪里了？” | 提供网格与列表视图，以及搜索、分类、标签和收藏。 |
| “这个文件是不是下载过？” | 通过文件哈希合并内容完全相同的导入文件，并保留来源位置。不同配置的文件仍分别保存。 |
| “每块打印板上都有什么？” | 一次列出已保存的打印板预览，点击即可放大。 |
| “打印需要多久？” | 读取3MF中保存的估时；已有MakerWorld估时信息时优先显示，也可通过本机Studio按所选打印机计算。 |
| “这个模型已经打印了吗？” | 查看已完成与未完成的模型，按次记录时间、耗材和备注。 |
| “几十个文件怎么整理？” | 多选后批量分类、收藏、标记完成、移入废纸篓或恢复。 |

### 一眼查看所有打印板

无需反复切换下拉菜单。把各块打印板的预览放在一起看，点击放大，确认内容后再用Studio打开。

![放大的打印板预览](Docs/screenshots/zh-Hans/plates.png)

### 轻松记录一次打印

标记完成，检查已填好的时间，然后保存。预计时间可以修改；有数据时，还能记录耗材类型、颜色和克数，再留下下次打印要参考的备注。已完成的归档文件会移入专用文件夹，保存前可在对话框中查看相关移动内容。

![分别记录打印时间、耗材与备注](Docs/screenshots/zh-Hans/print-record.png)

### 一次整理多个模型

进入选择模式，选中多张卡片，就能统一分类、标记完成，或移入可恢复的废纸篓。批量完成时，每个模型仍保留各自的时间与耗材预填值，也可以添加共用备注。

![多选模型并批量整理](Docs/screenshots/zh-Hans/selection.png)

## 还包括这些功能

- **文件夹自动检查与拖放导入：** 单独导入3MF，或检查你选择的文件夹。
- **保护归档原件：** 在Studio中打开独立的工作副本，编辑不会覆盖模型库保存的原件。
- **把来源链接留在文件旁：** 关联MakerWorld模型页与打印配置页，在浏览器中打开。之前保存的网页信息也会保留。
- **按自己的打印机计算：** 选择打印机、喷嘴和质量，或导入官方Studio当前选择的设置。兼容的本地计算结果会缓存。
- **可恢复的整理操作：** 从废纸篓恢复时，分类、备注和打印记录一并恢复。删除模型库条目不会删除外部原始文件。
- **四种界面语言：** 在设置中选择英语、韩语、日语或简体中文。
- **本地保存：** 使用模型库无需MakerDock账号，不需要使用情况分析或云端上传。

## 开始使用

1. 在[Releases](https://github.com/Goodtail/MakerDock/releases)下载DMG。签名与公证状态会在对应发行说明中列明。
2. 将**MakerDock**拖入**Applications**文件夹。支持macOS 13及以上、Apple Silicon与Intel。
3. 导入`.3mf`文件，拖入应用窗口，或选择要自动检查的文件夹。
4. 查看模型，用另行安装的**官方Bambu Studio**打开。实际打印完成后，在MakerDock留下完成记录。

浏览模型库和手动记录不需要Studio。切片及基于Studio的时间计算需要安装Studio。

## 估时与实际打印结果

未切片的3MF可能只有几何形状和设置，没有保存预计时间。仅选择打印机并不能得到准确时长，还需要切片。MakerDock可以用文件副本和独立的临时设置，请兼容的官方Studio进行计算。打印前请在Studio中确认最终设置。

打印完成由**用户手动记录**。MakerDock不会自动检测打印机任务结束，不读取实时AMS料盘库存，也不测量实际耗材消耗。如果实际结果不同，请修改预填的时间和耗材数值。

## 即将推出

- **Chrome伴侣扩展 — 即将推出：** 计划把模型与打印配置信息交给模型库，并复用已经保存的下载文件。
- **应用内MakerWorld自动收集 — 实验阶段：** 开发源码中包含网页浏览、下载检测和配置复用的实现。在明确服务允许的使用范围之前，公开DMG不会启用这些功能。

目前公开版专注于本地文件管理，不拦截MakerWorld下载，也不会注册为Bambu Studio的URL处理程序。开源许可不授予第三方服务或模型的使用权。详情见[集成状态](Docs/integration-status.md)。

## 开发与许可

应用使用SwiftUI、AppKit和一个小型Swift 3MF库构建，通过ZIPFoundation处理ZIP文件。正式版与开发版使用独立标识和存储，开发版图标带有DEV标记。

[开发与测试](Docs/development.md) · [隐私说明](PRIVACY.md) · [参与贡献](CONTRIBUTING.md) · [第三方声明](THIRD_PARTY_NOTICES.md)

代码、文档及原创示例采用[MIT许可](LICENSE)。Bambu Studio是独立的AGPL应用，不包含在本项目中。MakerDock是Goodtail的独立项目，与Bambu Lab或MakerWorld不存在官方隶属、合作或背书关系。相关名称和商标归各自权利人所有。

<sub>所有截图均来自实际运行的简体中文应用，使用原创演示模型和示意估时。未包含个人模型库或其他创作者的下载模型。<a href="Docs/screenshots/README.md">截图与复现说明</a></sub>
