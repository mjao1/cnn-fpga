#!/usr/bin/env python3
"""28×28 user drawn digit frame to FPGA over UART (784 bytes, Q1.7)"""

from __future__ import annotations

import math
import sys

import numpy as np

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("Install pyserial: pip install pyserial", file=sys.stderr)
    sys.exit(1)

DEFAULT_BAUD = 115200
GRID = 28
CELL_PX = 14
BRUSH_SIGMA = 0.55


def quantize_to_uart_bytes(image: np.ndarray) -> bytes:
    g = np.clip(image.astype(np.float32), 0.0, 255.0) / 255.0
    q = np.clip(np.round(g * 127.0), 0, 127).astype(np.uint8)
    return q.reshape(-1, order="C").tobytes()


def _dist_sq_point_segment(
    px: float, py: float, x0: float, y0: float, x1: float, y1: float
) -> float:
    vx = x1 - x0
    vy = y1 - y0
    vv = vx * vx + vy * vy
    if vv < 1e-18:
        dx = px - x0
        dy = py - y0
        return dx * dx + dy * dy
    t = ((px - x0) * vx + (py - y0) * vy) / vv
    if t <= 0.0:
        dx = px - x0
        dy = py - y0
    elif t >= 1.0:
        dx = px - x1
        dy = py - y1
    else:
        bx = x0 + t * vx
        by = y0 + t * vy
        dx = px - bx
        dy = py - by
    return dx * dx + dy * dy


def send_frame(port: str, baud: int, payload: bytes) -> None:
    if len(payload) != GRID * GRID:
        raise ValueError(f"expected {GRID * GRID} bytes, got {len(payload)}")
    with serial.Serial(port, baud, timeout=2.0) as ser:
        ser.reset_input_buffer()
        ser.write(payload)
        ser.flush()


def run_gui(port_hint: str = "") -> None:
    import tkinter as tk
    from tkinter import messagebox, ttk

    class DrawApp:
        def __init__(self, root: tk.Tk, port_hint: str) -> None:
            self.root = root
            self.baud = DEFAULT_BAUD
            self.grid = np.zeros((GRID, GRID), dtype=np.float32)
            self._prev: tuple[int, int] | None = None
            self._brush_sigma = BRUSH_SIGMA

            root.title("cnn-fpga UART image sender")
            head = ttk.Frame(root, padding=8)
            head.pack(fill=tk.X)
            ttk.Label(head, text="COM port").pack(side=tk.LEFT)
            self.port_var = tk.StringVar(value=port_hint)
            ttk.Entry(head, textvariable=self.port_var, width=14).pack(side=tk.LEFT, padx=6)
            ttk.Button(head, text="Refresh ports", command=self._refresh_ports).pack(side=tk.LEFT)

            body = ttk.Frame(root, padding=8)
            body.pack()
            size = GRID * CELL_PX
            self.canvas = tk.Canvas(body, width=size, height=size, bg="black", highlightthickness=1)
            self.canvas.pack()
            self.canvas.bind("<Button-1>", self._paint)
            self.canvas.bind("<B1-Motion>", self._paint)
            self.canvas.bind("<ButtonRelease-1>", self._release)
            self.rects: list[list[int]] = []
            for r in range(GRID):
                row_ids = []
                for c in range(GRID):
                    x0 = c * CELL_PX
                    y0 = r * CELL_PX
                    i = self.canvas.create_rectangle(
                        x0, y0, x0 + CELL_PX, y0 + CELL_PX, fill="black", outline="#222"
                    )
                    row_ids.append(i)
                self.rects.append(row_ids)

            btns = ttk.Frame(root, padding=8)
            btns.pack(fill=tk.X)
            ttk.Button(btns, text="Clear", command=self._clear).pack(side=tk.LEFT, padx=4)
            ttk.Button(btns, text="Send", command=self._send).pack(side=tk.LEFT, padx=4)

        def _refresh_ports(self) -> None:
            ports = [p.device for p in serial.tools.list_ports.comports()]
            if ports:
                self.port_var.set(ports[0])
            else:
                messagebox.showwarning("Serial", "No serial ports found.")

        def _cell(self, event: tk.Event) -> tuple[int, int] | None:
            c = int(event.x // CELL_PX)
            r = int(event.y // CELL_PX)
            if 0 <= r < GRID and 0 <= c < GRID:
                return r, c
            return None

        def _release(self, _event: tk.Event) -> None:
            self._prev = None

        def _paint(self, event: tk.Event) -> None:
            p = self._cell(event)
            if p is None:
                self._prev = None
                return
            if self._prev is not None:
                self._apply_brush_segment(self._prev[0], self._prev[1], p[0], p[1])
            else:
                self._apply_brush_segment(p[0], p[1], p[0], p[1])
            self._prev = p

        def _apply_brush_segment(self, r0: int, c0: int, r1: int, c1: int) -> None:
            x0, y0 = c0 + 0.5, r0 + 0.5
            x1, y1 = c1 + 0.5, r1 + 0.5
            margin = int(math.ceil(self._brush_sigma * 4))
            r_lo = max(0, min(r0, r1) - margin)
            r_hi = min(GRID - 1, max(r0, r1) + margin)
            c_lo = max(0, min(c0, c1) - margin)
            c_hi = min(GRID - 1, max(c0, c1) + margin)
            inv_two_s2 = 1.0 / (2.0 * self._brush_sigma * self._brush_sigma)
            cutoff_sq = (self._brush_sigma * 3.5) ** 2
            for r in range(r_lo, r_hi + 1):
                for c in range(c_lo, c_hi + 1):
                    px, py = c + 0.5, r + 0.5
                    d_sq = _dist_sq_point_segment(px, py, x0, y0, x1, y1)
                    if d_sq > cutoff_sq:
                        continue
                    v = 255.0 * math.exp(-d_sq * inv_two_s2)
                    if v > self.grid[r, c]:
                        self.grid[r, c] = v
                        self._set_cell_visual(r, c)

        def _set_cell_visual(self, r: int, c: int) -> None:
            vi = int(round(self.grid[r, c]))
            vi = max(0, min(255, vi))
            fill = f"#{vi:02x}{vi:02x}{vi:02x}"
            self.canvas.itemconfig(self.rects[r][c], fill=fill, outline=fill)

        def _clear(self) -> None:
            self._prev = None
            self.grid.fill(0.0)
            for r in range(GRID):
                for c in range(GRID):
                    self.canvas.itemconfig(self.rects[r][c], fill="black", outline="#222")

        def _send(self) -> None:
            port = self.port_var.get().strip()
            if not port:
                messagebox.showwarning("Serial", "Set a COM port.")
                return
            payload = quantize_to_uart_bytes(self.grid)
            try:
                send_frame(port, self.baud, payload)
            except serial.SerialException as e:
                messagebox.showerror("Serial", str(e))
            except OSError as e:
                messagebox.showerror("Serial", str(e))

    root = tk.Tk()
    DrawApp(root, port_hint)
    root.mainloop()


def main() -> None:
    run_gui()


if __name__ == "__main__":
    main()
