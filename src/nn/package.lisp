;;;; package.lisp — Metis neural substrate (pure Common Lisp)
(defpackage :metis.nn
  (:use :cl :alexandria)
  (:export
   #:*nn-default-dtype*
   #:tensor #:tensor-p #:tensor-data #:tensor-shape #:tensor-grad
   #:tensor-requires-grad #:make-tensor #:tensor-zeros #:tensor-randn
   #:tensor-from-list #:tensor-ref #:tensor-set #:tensor-numel
   #:tensor-reshape #:tensor-copy #:tensor-no-grad
   #:zero-grad #:backward
   #:t+ #:t- #:t* #:t/ #:t-neg #:t-sum #:t-mean #:t-matmul #:t-transpose
   #:t-relu #:t-sigmoid #:t-tanh-act #:t-softmax #:t-log-softmax
   #:t-cross-entropy #:t-mse #:t-embedding-lookup #:t-causal-context-mean
   #:t-cat #:t-slice
   #:parameter #:linear #:embedding #:mlp #:module-parameters
   #:module-forward #:module-mode
   #:sgd #:adam #:optimizer-step #:optimizer-zero-grad
   #:char-vocab #:vocab-encode #:vocab-decode #:vocab-size
   #:build-char-vocab #:corpus-from-string #:corpus-from-file
   #:language-model #:language-model-p
   #:lm-vocab #:lm-hidden #:lm-seq-len #:lm-depth #:lm-emb-dim
   #:lm-hidden-layers #:lm-loss #:lm-generate #:lm-forward-logits
   #:train! #:train-lm!
   #:save-checkpoint #:load-checkpoint
   #:nn-registry-register #:nn-registry-get #:nn-registry-list
   #:*nn-registry*))

(in-package :metis.nn)

(defparameter *nn-default-dtype* 'double-float)
(defparameter *grad-enabled* t)
(defparameter *nn-registry* (make-hash-table :test #'equal))
