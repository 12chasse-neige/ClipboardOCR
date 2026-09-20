Clipboard OCR Windows 简易诊断工具 v3

用途：检查“安装后没有 GUI / 终端窗口 / 模型无法加载 / RTX 5090 不识别”等问题。

使用方法：
1. 解压这个 ZIP。
2. 双击 run-diagnostics.cmd；诊断窗口会保持打开，不会一闪而过。
3. 等待脚本完成；它会在当前目录生成 ClipboardOCR-diagnostic-时间.zip。
4. 把生成的诊断 ZIP 发回即可。

脚本只读取系统和安装状态，不读取图片、剪贴板内容或 OCR 文本，不会重新下载模型，也不会修改安装环境。

报告包含：快捷方式目标、安装文件、模型文件大小、NVIDIA 驱动信息、Paddle CUDA 状态、llama.cpp 版本、安装日志和最近的应用日志。

如果 Windows SmartScreen 提示，选择“更多信息 → 仍要运行”；这是未签名的本地诊断脚本，不是安装程序。
