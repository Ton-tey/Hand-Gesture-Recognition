# Hand Gesture Recognition for Touchless Device Control

A real-time, camera-based application that recognizes 8 hand gestures (plus an idle class) and turns them into
device commands (media, volume, slides), **entirely on the local machine**. MediaPipe Hands extracts 21 landmarks,
a compact MLP (~17.4k parameters, exported to ONNX) classifies them, and a temporal smoother makes sure a
command only fires after a gesture is held steadily.

> CPE178P · Mapúa University · MEJIA, Michael Stanly R. · PACLIBON, John Paul B.

Privacy by design: no video frame is ever stored or transmitted. Only event metadata (time, gesture, confidence,
action, latency) goes to a local SQLite log.

## Pipeline

```
webcam frame → MediaPipe hand landmarks (21×3) → EMA smoothing → wrist-relative / scale / handedness normalization
  → 63-d vector → ONNX MLP (9-way softmax) → temporal smoother (N frames above threshold)
  → action mapper → dispatcher (OS media/arrow keys) → SQLite event log → GUI overlay + local API
```

## Repository layout

```
hgr/
  classes.py          9 classes, HaGRID name mapping
  landmarks.py        MediaPipe HandDetector (Tasks API), skeleton connections
  preprocessing.py    normalization, mirroring, landmark EMA
  augment.py          landmark + photometric augmentation
  build_dataset.py    HaGRID images → landmarks.npz, subject-independent 70/15/15 split
  data_io.py          .npz format
  model.py            GestureMLP (primary), GestureGRU and MobileNetV2 (comparators)
  train.py            training (class weights, label smoothing, early stopping, LR plateau)
  tune.py             random hyperparameter search        crossval.py   5-fold subject-wise CV
  evaluate.py         macro-F1, confusion matrix, subgroup robustness (NFR-2)
  export_onnx.py      ONNX export + verification (1e-5 match, softmax sums to 1, < 5 MB)
  classifier.py       ONNX Runtime CPU classifier
  smoother.py         confirm-after-N-frames + debounce + cooldown
  actions.py, mapper.py, dispatcher.py, config.py   mappings, validation, key presses, admin PIN, hot reload
  logger.py           SQLite event log
  pipeline.py         frame → action pipeline
  capture.py, gui.py, app.py   webcam, PySide6 client, entry point
  api.py              FastAPI REST + WebSocket (127.0.0.1)
  benchmark.py        latency / size comparison of MLP vs GRU vs MobileNetV2
  collect_webcam.py   record team landmark samples        synthetic.py   fake data for smoke tests
configs/default_profile.json   shipped gesture→action mapping and thresholds
data/README.md                 dataset layout and instructions  ← read this first
saved_models/                  gesture_mlp.onnx + class_names.json (after export)
reports/                       metrics, confusion matrix, training curves (after evaluation)
tests/                         81 automated tests
```

## Quick start

```bash
python -m venv .venv
.venv\Scripts\activate                 # Windows   (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt
python -m hgr.download_model           # MediaPipe hand model → saved_models/hand_landmarker.task
```

**1. Dataset.** Put the HaGRID images and annotations under `data/raw/` as described in [`data/README.md`](data/README.md), then:

```bash
python -m hgr.build_dataset --raw-dir data/raw --workers 4
```

**2. Train, evaluate, export.**

```bash
python -m hgr.train                    # → saved_models/gesture_mlp.pt, reports/training_curves.png
python -m hgr.evaluate --split test    # → reports/metrics.json, confusion_matrix.png, subgroup_f1.csv
python -m hgr.export_onnx              # → saved_models/gesture_mlp.onnx (verified)
# optional
python -m hgr.tune --trials 20 && python -m hgr.train --hparams reports/best_hparams.json
python -m hgr.crossval --folds 5
python -m hgr.benchmark --image path/to/photo_with_hand.jpg
```

**3. Run the app.**

```bash
python -m hgr.app --dry-run            # recognize and log, but press no keys (safe first run)
python -m hgr.app                      # real control; also .\run_app.ps1 or run_app.bat on Windows
```

The first gesture dispatch presses real OS keys, so try `--dry-run` first. Local API docs: <http://127.0.0.1:8000/docs>.

### Try everything before the dataset exists

```bash
python -m hgr.synthetic --out data/processed/synthetic_landmarks.npz
python -m hgr.train --data data/processed/synthetic_landmarks.npz
python -m hgr.evaluate --data data/processed/synthetic_landmarks.npz
python -m hgr.export_onnx --data data/processed/synthetic_landmarks.npz
```

Synthetic data is stylised and trivially separable (expect ~100 % F1). It only proves that the plumbing works.
**Never report its numbers in the paper.**

## Gestures and default actions

| Gesture | Action | Gesture | Action |
|---|---|---|---|
| `open_palm` | pause | `peace_sign` | next item / slide (→) |
| `fist` | mute | `three_fingers` | previous item / slide (←) |
| `thumbs_up` | volume up | `ok_sign` | play |
| `thumbs_down` | volume down | `index_point` | select (Enter) |

Windows exposes one play/pause key, so `pause` and `play` both press it. Mappings, the confidence threshold
(default 0.8) and the stability window (default 5 frames) are edited in the **Configuration** tab (administrator
PIN, default `1234`; change it with `python -m hgr.set_pin`) and apply immediately without a restart. An action can
be bound to only one gesture.

## Developer API (local only)

`GET /health /gestures /mappings /config /events /stats`, `POST /predict` (21×3 landmarks → label),
`PUT /mappings/{gesture}` and `PUT /config` (header `X-Admin-Pin`), and `WS /ws/events` (live gesture events).

## Requirements → code → tests

| Requirement | Where | Verified by |
|---|---|---|
| FR-1 webcam ≥ 25 FPS + landmark overlay | `capture.py`, `gui.py` | `test_gui_smoke.py` (overlay); the live view shows FPS, check it on your laptop |
| FR-2 21 landmarks → 63-d vector | `landmarks.py`, `preprocessing.py` | `test_preprocessing.py` |
| FR-3 9 classes + probabilities | `model.py`, `classifier.py` | `test_model_export.py` (TC-05) |
| FR-4 threshold for N consecutive frames | `smoother.py` | `test_smoother.py` (TC-04) |
| FR-5 event metadata log | `logger.py`, `pipeline.py` | `test_pipeline.py` (TC-01), `test_config_mapper_logger.py` |
| FR-6 edit mappings without restart, searchable log | `config.py`, `gui.py`, `api.py` | `test_pipeline.py` (TC-08), `test_gui_smoke.py`, `test_api.py` |
| NFR-1 p95 ≤ 100 ms | `pipeline.latency_stats`, `benchmark.py` | `hgr.benchmark --image` on the target laptop |
| NFR-2 macro-F1 ≥ 90 %, subgroup drop ≤ 5 pp | `evaluate.py` | run on real data |
| NFR-3 ONNX < 5 MB | `export_onnx.py` | `test_model_export.py` |
| NFR-4 no frames stored | `logger.py` (metadata-only schema) | `test_config_mapper_logger.py` |
| NFR-5 CPU only | ONNX Runtime CPU provider | – |
| TC-02 no hand → no action | `pipeline.py` | `test_pipeline.py` |
| TC-06 camera disconnected | `gui.py` (worker + alert + Retry) | `test_gui_smoke.py` (missing camera) |

Run the tests with `pip install -r requirements-dev.txt && python -m pytest` (GitHub Actions does it on every push).

## Known gaps (to finish as a team)

* **Real results are still to be produced.** All metrics in this repo come from synthetic data in tests; the
  paper's numbers must come from `build_dataset → train → evaluate` on HaGRID.
* **Real-camera path is untested here.** MediaPipe detection, webcam capture, OS key injection and the live
  GUI were developed without a camera or the MediaPipe model file. Run `python -m hgr.app --dry-run` and
  `python -m hgr.benchmark --image …` on your laptop and fix anything environment-specific.
* **Smoothing parameters** (EMA alpha, window N, threshold) cannot be tuned on HaGRID (single images); tune
  them in live testing using false triggers per idle minute.
* **CNN / GRU comparators** are included as model definitions and benchmarked for size and latency only
  (`hgr.benchmark`); training them for an accuracy comparison is not implemented. MobileNetV2 alone is ~9 MB, above the 5 MB budget.
* **PyInstaller packaging** and the user study (≥ 10 volunteers, SUS) are not included.
* No `LICENSE` file yet: choose one before making the repository public.

## AI disclosure

Parts of this code and its tests were drafted with Claude (Anthropic). The team is responsible for reviewing,
running and validating it, consistent with Appendix I of the project proposal.
