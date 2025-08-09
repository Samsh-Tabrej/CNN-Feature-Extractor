# CNN-Feature-Extractor
# FPGA-Based VGG-16 feature extractor for Edge AI Applications

## Authors
- **Md Samsh Tabrej**
- **Ashish Kumar Sahoo**

---

## 📜 Project Overview
This project implements a **128-channel systolic CNN accelerator** optimized for feature extraction in a **CNN** architecture.  
The system is deployed on a **Genesys-2 FPGA** (Xilinx Kintex-7) and controlled by the **VEGA AT1051 RISC-V processor**, enabling **real-time edge AI inference** for tasks like industrial defect detection.

### Key Highlights
- **CNN Accelerator:** 128×3 Processing Element (PE) systolic array
  - **34×34xN** image convolution with FIFO-based bias forwarding (full deployment)
- **Hierarchical Buffers:** SRAM + register file for image and filter buffers and a fifo for bias buffer
- **Integration:** AXI4 interface with VEGA processor
- **Post-processing:** ReLU
- **INT8 quantization** for low-power, high-speed operation

---

## 🔍 Accelerator Design

### 1. Processing Element (PE)
- Performs **1D convolution** on a row (3 pixels × 3 weights)
- Pipelined stages:
  - Bias add
  - Partial sum accumulation
  - Final output

### 2. Processing Unit (PU)
- 3 cascaded PEs for vertical **3×3 convolution**
- FIFO for bias/psum forwarding between channels

### 3. Buffer System
- **Image Row Buffer** (BRAM + shift-register)
- **Filter Buffer** (with 3 BRAM based sub-buffers)
- **Bias FIFO** (psum-forwarded between channels)

---

## 📊 Segmentation Strategy (VGG-16 Example)
- Feature maps segmented in **Length × Width × Channels** to fit FPGA BRAM constraints
- Ensures each tile fits within buffer capacity for real-time processing

---
