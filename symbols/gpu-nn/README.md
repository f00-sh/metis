# gpu-nn symbol

Optional Metis **symbol** (plugin) that accelerates neural matmul via the **CUDA driver API** (`libcuda.so`) and an embedded PTX SGEMM kernel.

## Enable

```lisp
(metis:enable-symbol! "gpu-nn")
(metis:nn-backend-status)
```

Iface:

```
/symbols enable gpu-nn
/symbols backend
```

## Disable (returns compute to cpu-nn)

```
/symbols disable gpu-nn
```

## Requirements

- NVIDIA GPU + working proprietary driver (`libcuda.so`)
- CFFI (Quicklisp)
- No `nvcc` required (PTX is JIT-compiled by the driver)

If CUDA is unavailable, enabling this symbol signals an error and leaves `cpu-nn` as the backend.
