"""High-DPI Windows desktop and tray app for local clipboard OCR."""
from __future__ import annotations

import ctypes
import logging
import os
import queue
import sys
import tempfile
import threading
import time
from ctypes import wintypes
from logging.handlers import RotatingFileHandler
from pathlib import Path

from PIL import Image, ImageGrab
from PySide6.QtCore import QObject, Qt, QTimer, Signal
from PySide6.QtGui import QAction, QCloseEvent, QFont, QIcon, QPixmap
from PySide6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QMenu,
    QPlainTextEdit, QProgressBar, QPushButton, QSystemTrayIcon,
    QVBoxLayout, QWidget,
)


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from engine import BackendError  # noqa: E402
from engine_windows import Engine, LOCAL  # noqa: E402


LOG_DIR = LOCAL / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
logger = logging.getLogger("clipboard_ocr")
if not logger.handlers:
    handler = RotatingFileHandler(LOG_DIR / "app.log", maxBytes=2_000_000, backupCount=2, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
CF_UNICODETEXT, GMEM_MOVEABLE = 13, 0x0002
WM_HOTKEY, WM_QUIT = 0x0312, 0x0012
MOD_ALT, MOD_CONTROL, MOD_NOREPEAT, VK_O = 0x0001, 0x0002, 0x4000, 0x4F
MAX_IMAGE_PIXELS = 12_000_000


def should_start_hidden(render_path, tray_available):
    """Keep the production app in the tray, but preserve render and fallback UI."""
    return render_path is None and tray_available

user32.GetClipboardSequenceNumber.restype = wintypes.DWORD
user32.OpenClipboard.argtypes = [wintypes.HWND]
user32.OpenClipboard.restype = wintypes.BOOL
user32.EmptyClipboard.argtypes = []
user32.EmptyClipboard.restype = wintypes.BOOL
user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
user32.SetClipboardData.restype = wintypes.HANDLE
user32.CloseClipboard.argtypes = []
user32.CloseClipboard.restype = wintypes.BOOL
kernel32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
kernel32.GlobalAlloc.restype = wintypes.HGLOBAL
kernel32.GlobalLock.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalLock.restype = wintypes.LPVOID
kernel32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalUnlock.restype = wintypes.BOOL
kernel32.GlobalFree.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalFree.restype = wintypes.HGLOBAL
kernel32.CreateMutexW.argtypes = [ctypes.c_void_p, wintypes.BOOL, wintypes.LPCWSTR]
kernel32.CreateMutexW.restype = wintypes.HANDLE


def clipboard_sequence():
    return int(user32.GetClipboardSequenceNumber())


def copy_text(text, expected_sequence=None):
    for _ in range(10):
        if user32.OpenClipboard(None):
            break
        time.sleep(.05)
    else:
        return False
    handle = None
    try:
        if expected_sequence is not None and clipboard_sequence() != expected_sequence:
            return False
        data = (text + "\0").encode("utf-16-le")
        handle = kernel32.GlobalAlloc(GMEM_MOVEABLE, len(data))
        pointer = kernel32.GlobalLock(handle) if handle else None
        if not pointer:
            return False
        ctypes.memmove(pointer, data, len(data))
        kernel32.GlobalUnlock(handle)
        if not user32.EmptyClipboard() or not user32.SetClipboardData(CF_UNICODETEXT, handle):
            return False
        handle = None
        return True
    finally:
        if handle:
            kernel32.GlobalFree(handle)
        user32.CloseClipboard()


def prepare_image(image):
    pixels = image.width * image.height
    if pixels > MAX_IMAGE_PIXELS:
        scale = (MAX_IMAGE_PIXELS / pixels) ** .5
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    if image.mode in ("RGBA", "LA"):
        alpha = image.getchannel("A")
        background = Image.new("RGB", image.size, "white")
        background.paste(image.convert("RGB"), mask=alpha)
        return background
    return image if image.mode == "RGB" else image.convert("RGB")


class Hotkey:
    def __init__(self, callback):
        self.callback = callback
        self.thread_id = None
        self.ready = threading.Event()
        self.registered = False

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()
        self.ready.wait(5)
        return self.registered

    def _run(self):
        self.thread_id = kernel32.GetCurrentThreadId()
        self.registered = bool(user32.RegisterHotKey(None, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_O))
        self.ready.set()
        if not self.registered:
            return
        message = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(message), None, 0, 0) > 0:
            if message.message == WM_HOTKEY:
                self.callback()
        user32.UnregisterHotKey(None, 1)

    def stop(self):
        if self.thread_id:
            user32.PostThreadMessageW(self.thread_id, WM_QUIT, 0, 0)


class Bridge(QObject):
    hotkey = Signal()
    loaded = Signal(str, float)
    unloaded = Signal()
    result = Signal(str, float, bool)
    failure = Signal(str)


class MainWindow(QMainWindow):
    def __init__(self, runtime=True):
        super().__init__()
        self.runtime = runtime
        self.bridge = Bridge()
        self.bridge.hotkey.connect(self.recognize)
        self.bridge.loaded.connect(self.on_loaded)
        self.bridge.unloaded.connect(self.on_unloaded)
        self.bridge.result.connect(self.on_result)
        self.bridge.failure.connect(self.on_failure)
        self.commands = queue.Queue()
        self.busy = True
        self.model_loaded = False
        self.latest_result = ""
        self.closing = False
        self.backend_name = "Detecting GPU backend…"
        self.setWindowTitle("Clipboard OCR")
        self.setWindowIcon(QIcon(str(ROOT / "assets/AppIcon.ico")))
        self.resize(900, 720)
        self.setMinimumSize(760, 620)
        self._build_ui()
        if runtime:
            self._build_tray()
            self.hotkey = Hotkey(self.bridge.hotkey.emit)
            if not self.hotkey.start():
                self.hotkey_value.setText("Unavailable")
            self.worker_thread = threading.Thread(target=self._worker, daemon=True)
            self.worker_thread.start()
            self.commands.put(("load", None, None))
        else:
            self.model_loaded = True
            self.backend_value.setText("llama.cpp Vulkan · NVIDIA GPU · 自动调优")
            self.elapsed_label.setText("Engine warm")
            self.set_state("Ready for capture", "Copy an image and press Ctrl+Alt+O. The engine is already warm.", "ready", busy=False)

    def _build_ui(self):
        root = QWidget(objectName="root")
        page = QVBoxLayout(root)
        page.setContentsMargins(38, 30, 38, 28)
        page.setSpacing(20)

        header = QHBoxLayout()
        logo = QLabel()
        logo.setPixmap(QPixmap(str(ROOT / "assets/AppIcon.png")).scaled(58, 58, Qt.KeepAspectRatio, Qt.SmoothTransformation))
        header.addWidget(logo)
        titles = QVBoxLayout()
        title = QLabel("Clipboard OCR", objectName="title")
        subtitle = QLabel("LOCAL DOCUMENT INTELLIGENCE", objectName="eyebrow")
        titles.addWidget(title)
        titles.addWidget(subtitle)
        header.addLayout(titles)
        header.addStretch()
        privacy = QLabel("●  LOCAL ONLY", objectName="privacy")
        header.addWidget(privacy, alignment=Qt.AlignTop)
        page.addLayout(header)

        status_card = QFrame(objectName="statusCard")
        status_layout = QVBoxLayout(status_card)
        status_layout.setContentsMargins(24, 20, 24, 20)
        top = QHBoxLayout()
        self.status_dot = QLabel("●", objectName="statusDot")
        self.status_label = QLabel("Preparing recognition engine", objectName="statusTitle")
        self.status_detail = QLabel("Loading the optimized GPU pipeline in the background.", objectName="statusDetail")
        top.addWidget(self.status_dot)
        top.addWidget(self.status_label)
        top.addStretch()
        self.elapsed_label = QLabel("", objectName="elapsed")
        top.addWidget(self.elapsed_label)
        status_layout.addLayout(top)
        status_layout.addWidget(self.status_detail)
        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setTextVisible(False)
        status_layout.addWidget(self.progress)
        page.addWidget(status_card)

        metrics = QHBoxLayout()
        metrics.setSpacing(14)
        self.backend_value = self._metric(metrics, "ACCELERATOR", self.backend_name)
        self.hotkey_value = self._metric(metrics, "GLOBAL SHORTCUT", "Ctrl + Alt + O")
        self.mode_value = self._metric(metrics, "OUTPUT", "Markdown + LaTeX")
        page.addLayout(metrics)

        actions = QHBoxLayout()
        actions.setSpacing(12)
        self.recognize_button = QPushButton("Recognize clipboard", objectName="primaryButton")
        self.recognize_button.clicked.connect(self.recognize)
        self.recognize_button.setEnabled(False)
        self.copy_button = QPushButton("Copy result", objectName="secondaryButton")
        self.copy_button.clicked.connect(self.copy_result)
        self.copy_button.setEnabled(False)
        self.unload_button = QPushButton("Release GPU", objectName="ghostButton")
        self.unload_button.clicked.connect(self.unload)
        self.unload_button.setEnabled(False)
        actions.addWidget(self.recognize_button, 2)
        actions.addWidget(self.copy_button, 1)
        actions.addWidget(self.unload_button, 1)
        page.addLayout(actions)

        preview_card = QFrame(objectName="previewCard")
        preview_layout = QVBoxLayout(preview_card)
        preview_layout.setContentsMargins(22, 18, 22, 20)
        preview_head = QHBoxLayout()
        preview_head.addWidget(QLabel("LATEST RESULT", objectName="sectionLabel"))
        preview_head.addStretch()
        self.count_label = QLabel("No result yet", objectName="muted")
        preview_head.addWidget(self.count_label)
        preview_layout.addLayout(preview_head)
        self.preview = QPlainTextEdit()
        self.preview.setReadOnly(True)
        self.preview.setPlaceholderText("Copy an image, then press Ctrl+Alt+O.\nThe recognized Markdown will appear here and be copied automatically.")
        self.preview.setLineWrapMode(QPlainTextEdit.WidgetWidth)
        preview_layout.addWidget(self.preview)
        page.addWidget(preview_card, 1)

        footer = QLabel("Images are processed locally and temporary inputs are deleted after recognition. Closing this window keeps the tray service running.", objectName="footer")
        footer.setWordWrap(True)
        page.addWidget(footer)
        self.setCentralWidget(root)

    def _metric(self, layout, label, value):
        card = QFrame(objectName="metricCard")
        box = QVBoxLayout(card)
        box.setContentsMargins(18, 14, 18, 14)
        box.addWidget(QLabel(label, objectName="metricLabel"))
        value_label = QLabel(value, objectName="metricValue")
        value_label.setWordWrap(True)
        box.addWidget(value_label)
        layout.addWidget(card, 1)
        return value_label

    def _build_tray(self):
        self.tray = QSystemTrayIcon(self.windowIcon(), self)
        self.tray.setToolTip("Clipboard OCR · Preparing")
        menu = QMenu()
        show_action = QAction("Open Clipboard OCR", self)
        show_action.triggered.connect(self.show_window)
        recognize_action = QAction("Recognize Clipboard    Ctrl+Alt+O", self)
        recognize_action.triggered.connect(self.recognize)
        quit_action = QAction("Quit", self)
        quit_action.triggered.connect(self.quit_app)
        menu.addAction(show_action)
        menu.addAction(recognize_action)
        menu.addSeparator()
        menu.addAction(quit_action)
        self.tray.setContextMenu(menu)
        self.tray.activated.connect(lambda reason: self.show_window() if reason == QSystemTrayIcon.Trigger else None)
        self.tray.show()

    def set_state(self, title, detail, kind="working", busy=None):
        if busy is not None:
            self.busy = busy
        self.status_label.setText(title)
        self.status_detail.setText(detail)
        colors = {"working": "#2563EB", "ready": "#0F9D75", "error": "#DC3545"}
        self.status_dot.setStyleSheet(f"color:{colors[kind]};")
        self.progress.setVisible(self.busy)
        self.progress.setRange(0, 0 if self.busy else 1)
        self.recognize_button.setEnabled(self.model_loaded and not self.busy)
        self.unload_button.setEnabled(self.model_loaded and not self.busy)
        self.copy_button.setEnabled(bool(self.latest_result))
        if hasattr(self, "tray"):
            self.tray.setToolTip("Clipboard OCR · " + title)

    def recognize(self):
        if self.busy or not self.model_loaded:
            self.show_window()
            return
        self.set_state("Reading clipboard", "Capturing a stable image snapshot without replacing your current data.", busy=True)
        sequence = clipboard_sequence()
        path = None
        try:
            image = ImageGrab.grabclipboard()
            if not isinstance(image, Image.Image):
                raise ValueError("No image found. Copy image pixels or use Win+Shift+S, then try again.")
            if clipboard_sequence() != sequence:
                raise ValueError("The clipboard changed while it was being read. Try again.")
            image = prepare_image(image)
            inputs = LOCAL / "inputs"
            inputs.mkdir(parents=True, exist_ok=True)
            descriptor, name = tempfile.mkstemp(suffix=".png", dir=inputs)
            os.close(descriptor)
            path = Path(name)
            image.save(path, "PNG", compress_level=1)
            self.elapsed_label.setText("")
            self.set_state("Recognizing document", "Detecting layout, text, equations and reading order on the NVIDIA GPU.", busy=True)
            self.commands.put(("recognize", path, sequence))
        except Exception as error:
            if path:
                path.unlink(missing_ok=True)
            self.set_state("Clipboard image required", str(error), "error", busy=False)
            self.tray.showMessage("Clipboard OCR", str(error), QSystemTrayIcon.Warning, 5000)

    def copy_result(self):
        if self.latest_result and copy_text(self.latest_result):
            self.set_state("Markdown copied", "The latest result is ready to paste.", "ready", busy=False)
            self.tray.showMessage("Clipboard OCR", "Markdown copied", QSystemTrayIcon.Information, 2500)
        else:
            self.set_state("Clipboard write failed", "Try Copy result again.", "error", busy=False)

    def unload(self):
        if self.busy:
            return
        self.set_state("Releasing GPU", "Stopping the model service and clearing GPU memory.", busy=True)
        self.commands.put(("unload", None, None))

    def _worker(self):
        engine = None
        messages = {
            "gpu_unavailable": "NVIDIA GPU runtime is unavailable. Run Windows setup again.",
            "model_load_failed": "The recognition engine could not be loaded.",
            "recognition_failed": "Recognition failed. Try a smaller or clearer image.",
            "no_text": "No text was recognized in this image.",
        }
        while True:
            action, path, sequence = self.commands.get()
            if action == "quit":
                if engine:
                    engine.close()
                return
            try:
                if action == "load":
                    started = time.perf_counter()
                    engine = engine or Engine()
                    engine.load()
                    self.bridge.loaded.emit(engine.backend_name, time.perf_counter() - started)
                elif action == "unload":
                    if engine:
                        engine.close()
                    engine = None
                    self.bridge.unloaded.emit()
                elif action == "recognize":
                    engine = engine or Engine()
                    started = time.perf_counter()
                    markdown = engine.recognize(path)
                    copied = copy_text(markdown, expected_sequence=sequence)
                    self.bridge.result.emit(markdown, time.perf_counter() - started, copied)
            except BackendError as error:
                if engine:
                    engine.close()
                engine = None
                logger.exception("OCR backend error: %s", error)
                self.bridge.failure.emit(messages.get(str(error), "Recognition failed."))
            except Exception:
                if engine:
                    engine.close()
                engine = None
                logger.exception("Unexpected worker failure")
                self.bridge.failure.emit("An internal error occurred. Details were saved to the local diagnostic log.")
            finally:
                if path:
                    path.unlink(missing_ok=True)

    def on_loaded(self, backend, seconds):
        self.model_loaded = True
        self.backend_name = backend
        self.backend_value.setText(backend)
        self.elapsed_label.setText(f"Ready in {seconds:.1f} s")
        self.set_state("Ready for capture", "Copy an image and press Ctrl+Alt+O. The engine is already warm.", "ready", busy=False)

    def on_unloaded(self):
        self.model_loaded = False
        self.set_state("GPU released", "Click Load engine to prepare recognition again.", "ready", busy=False)
        self.recognize_button.setText("Load engine")
        try:
            self.recognize_button.clicked.disconnect()
        except RuntimeError:
            pass
        self.recognize_button.clicked.connect(self.reload)
        self.recognize_button.setEnabled(True)

    def reload(self):
        self.recognize_button.setText("Recognize clipboard")
        try:
            self.recognize_button.clicked.disconnect()
        except RuntimeError:
            pass
        self.recognize_button.clicked.connect(self.recognize)
        self.set_state("Preparing recognition engine", "Loading the optimized GPU pipeline in the background.", busy=True)
        self.commands.put(("load", None, None))

    def on_result(self, markdown, seconds, copied):
        self.latest_result = markdown
        self.preview.setPlainText(markdown)
        self.count_label.setText(f"{len(markdown):,} characters · {seconds:.1f} s")
        self.elapsed_label.setText(f"OCR {seconds:.1f} s")
        if copied:
            title, detail = "Markdown copied", "Recognition completed and the clipboard was updated safely."
        else:
            title, detail = "Result ready", "The clipboard changed during recognition. Use Copy result when ready."
        self.set_state(title, detail, "ready", busy=False)
        self.tray.showMessage("Clipboard OCR", title, QSystemTrayIcon.Information, 3500)

    def on_failure(self, message):
        self.model_loaded = False
        self.set_state("Recognition unavailable", message + " Use Load engine to retry.", "error", busy=False)
        self.recognize_button.setText("Load engine")
        self.recognize_button.setEnabled(True)
        try:
            self.recognize_button.clicked.disconnect()
        except RuntimeError:
            pass
        self.recognize_button.clicked.connect(self.reload)
        self.tray.showMessage("Clipboard OCR", message, QSystemTrayIcon.Critical, 6000)

    def show_window(self):
        self.showNormal()
        self.raise_()
        self.activateWindow()

    def closeEvent(self, event: QCloseEvent):
        if self.closing or not self.runtime:
            event.accept()
        else:
            self.hide()
            self.tray.showMessage("Clipboard OCR", "Still running in the notification area", QSystemTrayIcon.Information, 2500)
            event.ignore()

    def quit_app(self):
        self.closing = True
        self.hotkey.stop()
        self.commands.put(("quit", None, None))
        self.worker_thread.join(timeout=8)
        self.tray.hide()
        QApplication.quit()


STYLE = """
QWidget#root { background: #F3F6FA; color: #152238; }
QLabel { font-family: "Segoe UI Variable Text", "Segoe UI"; }
QLabel#title { font: 700 28px "Segoe UI Variable Display"; color: #122033; }
QLabel#eyebrow, QLabel#metricLabel, QLabel#sectionLabel { font: 700 10px "Segoe UI"; letter-spacing: 1.5px; color: #718096; }
QLabel#privacy { background: #E5F7F0; color: #087A59; border: 1px solid #BDE8D7; border-radius: 12px; padding: 6px 10px; font: 700 10px "Segoe UI"; }
QFrame#statusCard { background: white; border: 1px solid #DDE4EE; border-radius: 14px; }
QLabel#statusDot { font-size: 17px; }
QLabel#statusTitle { font: 700 17px "Segoe UI Variable Text"; color: #17263B; }
QLabel#statusDetail, QLabel#muted { color: #66758A; font-size: 12px; }
QLabel#elapsed { color: #2563EB; font: 700 12px "Segoe UI"; }
QProgressBar { height: 4px; background: #E8EDF4; border: none; border-radius: 2px; margin-top: 8px; }
QProgressBar::chunk { background: #2563EB; border-radius: 2px; }
QFrame#metricCard { background: #EAF0F8; border: 1px solid #DCE4EF; border-radius: 11px; }
QLabel#metricValue { color: #1B2B42; font: 600 13px "Segoe UI Variable Text"; }
QPushButton { min-height: 43px; border-radius: 9px; padding: 0 18px; font: 600 13px "Segoe UI Variable Text"; }
QPushButton#primaryButton { background: #2563EB; color: white; border: 1px solid #1D4ED8; }
QPushButton#primaryButton:hover { background: #1D4ED8; }
QPushButton#secondaryButton { background: white; color: #1D4ED8; border: 1px solid #AFC5EF; }
QPushButton#secondaryButton:hover { background: #EFF5FF; }
QPushButton#ghostButton { background: transparent; color: #52637A; border: 1px solid #CBD5E1; }
QPushButton:disabled { background: #E5EAF1; color: #9AA7B7; border-color: #DDE3EA; }
QPushButton#secondaryButton:disabled, QPushButton#ghostButton:disabled { background: #E5EAF1; color: #9AA7B7; border-color: #DDE3EA; }
QFrame#previewCard { background: white; border: 1px solid #DDE4EE; border-radius: 14px; }
QPlainTextEdit { background: #F8FAFC; color: #17263B; border: 1px solid #E1E7EF; border-radius: 9px; padding: 13px; font: 12px "Cascadia Mono", "Consolas"; selection-background-color: #BDD2FF; }
QLabel#footer { color: #738197; font-size: 11px; }
"""


def main():
    logger.info("Application starting")
    render_path = Path(sys.argv[sys.argv.index("--render") + 1]) if "--render" in sys.argv else None
    if not render_path:
        mutex = kernel32.CreateMutexW(None, False, "Local\\ClipboardOCR.Windows")
        if not mutex or ctypes.get_last_error() == 183:
            return
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("Clipboard OCR")
    app.setFont(QFont("Segoe UI Variable Text", 10))
    app.setStyleSheet(STYLE)
    window = MainWindow(runtime=not render_path)
    if render_path:
        window.show()
        QTimer.singleShot(800, lambda: (window.grab().save(str(render_path)), app.quit()))
    elif should_start_hidden(render_path, QSystemTrayIcon.isSystemTrayAvailable()):
        window.hide()
        QTimer.singleShot(700, lambda: window.tray.showMessage(
            "Clipboard OCR", "Running in the notification area · Ctrl+Alt+O to recognize",
            QSystemTrayIcon.Information, 3000))
    else:
        logger.warning("System tray unavailable; showing the main window")
        window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
