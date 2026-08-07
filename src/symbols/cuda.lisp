;;;; cuda.lisp — CUDA driver API bindings + GPU matmul (plugin substrate)
(in-package :metis.symbols)

;;; Loaded only when gpu-nn activates. Soft-depends on CFFI + libcuda.

(defvar *cuda-ready* nil)
(defvar *cuda-device* nil)
(defvar *cuda-context* nil)
(defvar *cuda-module* nil)
(defvar *cuda-matmul-fn* nil)
(defvar *cuda-device-name* "none")
(defvar *cuda-error* nil)

(defparameter *matmul-ptx*
  "
.version 7.0
.target sm_70
.address_size 64

// C[m,n] = A[m,k] * B[k,n]  (row-major float)
.visible .entry metis_sgemm(
    .param .u64 param_A,
    .param .u64 param_B,
    .param .u64 param_C,
    .param .u32 param_M,
    .param .u32 param_K,
    .param .u32 param_N
)
{
    .reg .pred  %p<4>;
    .reg .f32   %f<8>;
    .reg .b32   %r<20>;
    .reg .b64   %rd<16>;

    ld.param.u64    %rd1, [param_A];
    ld.param.u64    %rd2, [param_B];
    ld.param.u64    %rd3, [param_C];
    ld.param.u32    %r1,  [param_M];
    ld.param.u32    %r2,  [param_K];
    ld.param.u32    %r3,  [param_N];

    mov.u32 %r4, %ctaid.x;
    mov.u32 %r5, %ntid.x;
    mov.u32 %r6, %tid.x;
    mad.lo.s32 %r7, %r4, %r5, %r6;   // linear id

    mul.lo.s32 %r8, %r1, %r3;        // m*n
    setp.ge.s32 %p1, %r7, %r8;
    @%p1 bra DONE;

    // i = id / n ; j = id % n
    div.s32 %r9, %r7, %r3;
    rem.s32 %r10, %r7, %r3;

    mov.f32 %f1, 0f00000000;

    mov.u32 %r11, 0;
LOOP:
    setp.ge.s32 %p2, %r11, %r2;
    @%p2 bra STORE;

    // A[i,k] at i*K + k
    mad.lo.s32 %r12, %r9, %r2, %r11;
    mul.wide.s32 %rd4, %r12, 4;
    add.s64 %rd5, %rd1, %rd4;
    ld.global.f32 %f2, [%rd5];

    // B[k,j] at k*N + j
    mad.lo.s32 %r13, %r11, %r3, %r10;
    mul.wide.s32 %rd6, %r13, 4;
    add.s64 %rd7, %rd2, %rd6;
    ld.global.f32 %f3, [%rd7];

    fma.rn.f32 %f1, %f2, %f3, %f1;

    add.s32 %r11, %r11, 1;
    bra LOOP;

STORE:
    mul.wide.s32 %rd8, %r7, 4;
    add.s64 %rd9, %rd3, %rd8;
    st.global.f32 [%rd9], %f1;

DONE:
    ret;
}
")

(defun %cuda-ok (code where)
  (unless (zerop code)
    (error "CUDA error ~A at ~A" code where))
  code)

(defun cuda-available-p ()
  (ignore-errors
    (ql:quickload :cffi :silent t)
    (cffi:load-foreign-library "libcuda.so")
    (zerop (cffi:foreign-funcall "cuInit" :unsigned-int 0 :int))))

(defun cuda-init! ()
  "Initialize CUDA driver context and load matmul module. Idempotent."
  (when *cuda-ready*
    (return-from cuda-init! t))
  (setf *cuda-error* nil)
  (handler-case
      (progn
        (ql:quickload :cffi :silent t)
        (cffi:load-foreign-library "libcuda.so")
        (%cuda-ok (cffi:foreign-funcall "cuInit" :unsigned-int 0 :int) "cuInit")
        (cffi:with-foreign-object (count :int)
          (%cuda-ok (cffi:foreign-funcall "cuDeviceGetCount" :pointer count :int)
                    "cuDeviceGetCount")
          (when (< (cffi:mem-ref count :int) 1)
            (error "no CUDA devices")))
        (cffi:with-foreign-object (dev :int)
          (%cuda-ok (cffi:foreign-funcall "cuDeviceGet" :pointer dev :int 0 :int)
                    "cuDeviceGet")
          (setf *cuda-device* (cffi:mem-ref dev :int))
          (cffi:with-foreign-pointer (name 256)
            (%cuda-ok (cffi:foreign-funcall "cuDeviceGetName"
                                            :pointer name :int 256
                                            :int *cuda-device* :int)
                      "cuDeviceGetName")
            (setf *cuda-device-name* (cffi:foreign-string-to-lisp name))))
        ;; primary context retain (works across driver versions)
        (cffi:with-foreign-object (ctx :pointer)
          (let ((st (cffi:foreign-funcall "cuDevicePrimaryCtxRetain"
                                          :pointer ctx :int *cuda-device* :int)))
            (if (zerop st)
                (progn
                  (setf *cuda-context* (cffi:mem-ref ctx :pointer))
                  (%cuda-ok (cffi:foreign-funcall "cuCtxSetCurrent"
                                                  :pointer *cuda-context* :int)
                            "cuCtxSetCurrent"))
                ;; fallback cuCtxCreate
                (progn
                  (%cuda-ok (cffi:foreign-funcall "cuCtxCreate_v2"
                                                  :pointer ctx
                                                  :unsigned-int 0
                                                  :int *cuda-device* :int)
                            "cuCtxCreate")
                  (setf *cuda-context* (cffi:mem-ref ctx :pointer))))))
        ;; load PTX
        (cffi:with-foreign-string (ptx *matmul-ptx*)
          (cffi:with-foreign-object (mod :pointer)
            (%cuda-ok (cffi:foreign-funcall "cuModuleLoadData"
                                            :pointer mod
                                            :pointer ptx :int)
                      "cuModuleLoadData")
            (setf *cuda-module* (cffi:mem-ref mod :pointer))))
        (cffi:with-foreign-object (fn :pointer)
          (cffi:with-foreign-string (fname "metis_sgemm")
            (%cuda-ok (cffi:foreign-funcall "cuModuleGetFunction"
                                            :pointer fn
                                            :pointer *cuda-module*
                                            :pointer fname :int)
                      "cuModuleGetFunction")
            (setf *cuda-matmul-fn* (cffi:mem-ref fn :pointer))))
        (setf *cuda-ready* t)
        t)
    (error (e)
      (setf *cuda-error* (princ-to-string e)
            *cuda-ready* nil)
      (error e))))

(defun cuda-shutdown! ()
  (when (and *cuda-ready* *cuda-device*)
    (ignore-errors
      (cffi:foreign-funcall "cuDevicePrimaryCtxRelease_v2"
                            :int *cuda-device* :int)))
  (setf *cuda-ready* nil
        *cuda-module* nil
        *cuda-matmul-fn* nil
        *cuda-context* nil))

(defun %host-double-to-float-array (data n)
  (let ((f (make-array n :element-type 'single-float)))
    (dotimes (i n)
      (setf (aref f i) (float (aref data i) 0f0)))
    f))

(defun cuda-sgemm (a-data b-data m k n)
  "GPU float GEMM; A,B double-float host arrays → double-float result."
  (unless *cuda-ready* (cuda-init!))
  (let* ((an (* m k))
         (bn (* k n))
         (cn (* m n))
         (af (%host-double-to-float-array a-data an))
         (bf (%host-double-to-float-array b-data bn))
         (cf (make-array cn :element-type 'single-float :initial-element 0f0))
         (bytes-a (* an 4))
         (bytes-b (* bn 4))
         (bytes-c (* cn 4)))
    (cffi:with-foreign-objects ((dA :pointer) (dB :pointer) (dC :pointer))
      (%cuda-ok (cffi:foreign-funcall "cuMemAlloc_v2" :pointer dA :ulong bytes-a :int)
                "cuMemAlloc A")
      (%cuda-ok (cffi:foreign-funcall "cuMemAlloc_v2" :pointer dB :ulong bytes-b :int)
                "cuMemAlloc B")
      (%cuda-ok (cffi:foreign-funcall "cuMemAlloc_v2" :pointer dC :ulong bytes-c :int)
                "cuMemAlloc C")
      (let ((pA (cffi:mem-ref dA :pointer))
            (pB (cffi:mem-ref dB :pointer))
            (pC (cffi:mem-ref dC :pointer)))
        (cffi:with-pointer-to-vector-data (ha af)
          (%cuda-ok (cffi:foreign-funcall "cuMemcpyHtoD_v2"
                                          :pointer pA :pointer ha :ulong bytes-a :int)
                    "HtoD A"))
        (cffi:with-pointer-to-vector-data (hb bf)
          (%cuda-ok (cffi:foreign-funcall "cuMemcpyHtoD_v2"
                                          :pointer pB :pointer hb :ulong bytes-b :int)
                    "HtoD B"))
        ;; launch params: 6 args as void* array of pointers to values
        (cffi:with-foreign-objects ((m32 :uint32) (k32 :uint32) (n32 :uint32)
                                    (args :pointer 6)
                                    (extra :pointer))
          (setf (cffi:mem-ref m32 :uint32) m
                (cffi:mem-ref k32 :uint32) k
                (cffi:mem-ref n32 :uint32) n)
          (cffi:with-foreign-objects ((pA-arg :pointer) (pB-arg :pointer) (pC-arg :pointer))
            (setf (cffi:mem-ref pA-arg :pointer) pA
                  (cffi:mem-ref pB-arg :pointer) pB
                  (cffi:mem-ref pC-arg :pointer) pC)
            (setf (cffi:mem-aref args :pointer 0) pA-arg
                  (cffi:mem-aref args :pointer 1) pB-arg
                  (cffi:mem-aref args :pointer 2) pC-arg
                  (cffi:mem-aref args :pointer 3) m32
                  (cffi:mem-aref args :pointer 4) k32
                  (cffi:mem-aref args :pointer 5) n32)
            (let* ((total cn)
                   (block 256)
                   (grid (max 1 (ceiling total block))))
              (%cuda-ok
               (cffi:foreign-funcall "cuLaunchKernel"
                                     :pointer *cuda-matmul-fn*
                                     :unsigned-int grid :unsigned-int 1 :unsigned-int 1
                                     :unsigned-int block :unsigned-int 1 :unsigned-int 1
                                     :unsigned-int 0
                                     :pointer (cffi:null-pointer)
                                     :pointer args
                                     :pointer (cffi:null-pointer)
                                     :int)
               "cuLaunchKernel"))
            (%cuda-ok (cffi:foreign-funcall "cuCtxSynchronize" :int) "sync")
            (cffi:with-pointer-to-vector-data (hc cf)
              (%cuda-ok (cffi:foreign-funcall "cuMemcpyDtoH_v2"
                                              :pointer hc :pointer pC :ulong bytes-c :int)
                        "DtoH C"))))
        (ignore-errors (cffi:foreign-funcall "cuMemFree_v2" :pointer pA :int))
        (ignore-errors (cffi:foreign-funcall "cuMemFree_v2" :pointer pB :int))
        (ignore-errors (cffi:foreign-funcall "cuMemFree_v2" :pointer pC :int))))
    (let ((out (make-array cn :element-type 'double-float)))
      (dotimes (i cn)
        (setf (aref out i) (float (aref cf i) 0d0)))
      out)))

;;; ---------- GPU backend object ----------

(defstruct (gpu-nn-backend (:constructor %make-gpu-nn-backend)
                           (:conc-name gpu-be-))
  (id +gpu-nn-id+)
  (device "cuda")
  (ready nil))

(defun make-gpu-nn-backend ()
  (cuda-init!)
  (%make-gpu-nn-backend :device *cuda-device-name* :ready *cuda-ready*))

(defmethod nn-backend-id ((b gpu-nn-backend))
  (gpu-be-id b))

(defmethod nn-backend-device ((b gpu-nn-backend))
  (gpu-be-device b))

(defmethod nn-backend-status ((b gpu-nn-backend))
  (list :id (gpu-be-id b)
        :device (gpu-be-device b)
        :kind :gpu
        :ready (gpu-be-ready b)
        :cuda-ready *cuda-ready*
        :cuda-error *cuda-error*
        :provider "CUDA driver (libcuda) PTX sgemm"))

(defmethod nn-backend-matmul ((b gpu-nn-backend) a-data b-data m k n)
  (declare (ignore b))
  (cuda-sgemm a-data b-data m k n))
