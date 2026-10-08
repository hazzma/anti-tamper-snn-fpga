# Laporan Evaluasi SNN-1N vs Baseline

**Dataset**: data/raw/synthetic_A4.csv
**Total Ticks**: 2000 (Normal: 1001, Tamper: 999)

| Detektor | Deteksi Tamper (Ticks) | Tingkat Deteksi (%) | False Alarm (Ticks) | False Alarm Rate (%) |
| -------- | ----------------------- | -------------------- | ------------------ | ------------------- |
| B1 (Datasheet) | 1 | 0.10% | 0 | 0.00% |
| B2 (Tuned Threshold) | 1 | 0.10% | 0 | 0.00% |
| SNN-1N (PoC) | 241 | 24.12% | 0 | 0.00% |

**Catatan**:
- Skenario A4 dirancang tetap berada di dalam batas datasheet sehingga B1 tidak mampu mendeteksi (0%).
- SNN-1N mengintegrasikan bukti lemah temporal secara multimodal tanpa false alarm pada fase normal.
