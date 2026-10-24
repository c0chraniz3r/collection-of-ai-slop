#!/usr/bin/env python3
"""
Simple GUI frontend for SUSE KIWI-ng image builder.

Requirements:
    - Python 3.8+
    - PyQt6 (pip install PyQt6)
    - kiwi-ng installed and in PATH
"""

import sys
import subprocess
from pathlib import Path

from PyQt6.QtCore import Qt, QThread, pyqtSignal
from PyQt6.QtWidgets import (
    QApplication,
    QWidget,
    QGridLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QTextEdit,
    QFileDialog,
    QComboBox,
    QMessageBox,
)


class KiwiBuildWorker(QThread):
    output = pyqtSignal(str)
    finished_ok = pyqtSignal()
    finished_error = pyqtSignal(int)

    def __init__(self, cmd):
        super().__init__()
        self.cmd = cmd

    def run(self):
        try:
            proc = subprocess.Popen(
                self.cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            for line in proc.stdout:
                self.output.emit(line)
            ret = proc.wait()
            if ret == 0:
                self.finished_ok.emit()
            else:
                self.finished_error.emit(ret)
        except Exception as e:
            self.output.emit(f"[ERROR] {e}\n")
            self.finished_error.emit(-1)


class KiwiGui(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("KIWI-ng Image Builder GUI")
        self.resize(800, 500)
        self.worker = None
        self._build_ui()

    def _build_ui(self):
        layout = QGridLayout(self)

        # Image type
        layout.addWidget(QLabel("Image type (--type):"), 0, 0)
        self.type_combo = QComboBox()
        self.type_combo.addItems([
            "",          # default (no --type)
            "oem",
            "vmx",
            "iso",
            "docker",
            "pxe",
        ])
        layout.addWidget(self.type_combo, 0, 1)

        # Description directory
        layout.addWidget(QLabel("Image description directory (--description):"), 1, 0)
        self.desc_edit = QLineEdit()
        layout.addWidget(self.desc_edit, 1, 1)
        self.desc_btn = QPushButton("Browse…")
        self.desc_btn.clicked.connect(self._choose_description)
        layout.addWidget(self.desc_btn, 1, 2)

        # Repository URL
        layout.addWidget(QLabel("Repository URL (--set-repo):"), 2, 0)
        self.repo_edit = QLineEdit("https://download.opensuse.org/distribution/leap/16.0/repo/oss")
        layout.addWidget(self.repo_edit, 2, 1, 1, 2)

        # Target directory
        layout.addWidget(QLabel("Target directory (--target-dir):"), 3, 0)
        self.target_edit = QLineEdit(str(Path.home() / "kiwi-build-output"))
        layout.addWidget(self.target_edit, 3, 1)
        self.target_btn = QPushButton("Browse…")
        self.target_btn.clicked.connect(self._choose_target)
        layout.addWidget(self.target_btn, 3, 2)

        # Extra options
        layout.addWidget(QLabel("Extra kiwi-ng options:"), 4, 0)
        self.extra_edit = QLineEdit()
        layout.addWidget(self.extra_edit, 4, 1, 1, 2)

        # Build button
        self.build_btn = QPushButton("Build image")
        self.build_btn.clicked.connect(self._start_build)
        layout.addWidget(self.build_btn, 5, 0, 1, 3)

        # Output log
        layout.addWidget(QLabel("Build log:"), 6, 0)
        self.log = QTextEdit()
        self.log.setReadOnly(True)
        self.log.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap)
        layout.addWidget(self.log, 7, 0, 1, 3)

    def _choose_description(self):
        path = QFileDialog.getExistingDirectory(self, "Select KIWI image description directory")
        if path:
            self.desc_edit.setText(path)

    def _choose_target(self):
        path = QFileDialog.getExistingDirectory(self, "Select target directory")
        if path:
            self.target_edit.setText(path)

    def _start_build(self):
        desc = self.desc_edit.text().strip()
        repo = self.repo_edit.text().strip()
        target = self.target_edit.text().strip()
        img_type = self.type_combo.currentText().strip()
        extra = self.extra_edit.text().strip()

        if not desc or not repo or not target:
            QMessageBox.warning(self, "Missing fields", "Description, repository, and target directory are required.")
            return

        cmd = ["kiwi-ng"]
        if img_type:
            cmd += ["--type", img_type]
        cmd += [
            "system", "build",
            "--description", desc,
            "--set-repo", repo,
            "--target-dir", target,
        ]
        if extra:
            # naive split; for more complex options you might want shlex.split
            cmd += extra.split()

        self.log.clear()
        self.log.append(f"$ {' '.join(cmd)}\n")
        self.build_btn.setEnabled(False)

        self.worker = KiwiBuildWorker(cmd)
        self.worker.output.connect(self._append_log)
        self.worker.finished_ok.connect(self._build_ok)
        self.worker.finished_error.connect(self._build_error)
        self.worker.start()

    def _append_log(self, text: str):
        self.log.moveCursor(self.log.textCursor().End)
        self.log.insertPlainText(text)
        self.log.moveCursor(self.log.textCursor().End)

    def _build_ok(self):
        self.build_btn.setEnabled(True)
        QMessageBox.information(self, "Build finished", "KIWI-ng image build completed successfully.")

    def _build_error(self, code: int):
        self.build_btn.setEnabled(True)
        QMessageBox.critical(self, "Build failed", f"KIWI-ng exited with code {code}.\nCheck the log for details.")


def main():
    app = QApplication(sys.argv)
    gui = KiwiGui()
    gui.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
