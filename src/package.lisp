;;;; package.lisp — Metis public surface (production 1.0)
(defpackage :metis
  (:use :cl :alexandria)
  (:export
   ;; version / lifecycle
   #:*metis-version*
   #:metis-version-string
   #:metis-build-info
   #:boot
   #:reset-mind
   #:run
   #:run-once
   #:production-boot
   ;; knowledge
   #:assert-fact
   #:retract-fact
   #:assert-rule
   #:facts
   #:rules
   #:tell
   #:ask
   #:ask-all
   #:prove
   #:forward-chain
   ;; frames
   #:deframe
   #:frame-get
   #:frame-set
   #:frame-slots
   #:all-frames
   ;; planning
   #:define-operator
   #:plan
   #:execute-plan
   #:htn-plan
   #:htn-defmethod
   #:htn-defprimitive
   ;; memory / learning
   #:remember-episode
   #:recall-episodes
   #:install-skill
   #:find-skills
   #:working-add
   #:working-contents
   #:learn-from-plan
   #:reinforce-skill
   ;; TMS / belief
   #:tms-why
   #:tms-in-facts
   #:belief-get
   #:belief-set
   #:belief-query
   ;; introspection / meta / explain
   #:reflect
   #:explain
   #:explain-deep
   #:explain-fact
   #:self-model
   #:reason-trace
   #:synthesize-skill
   #:mind-status
   #:rewrite-rule
   #:eval-in-mind
   #:sandboxed-eval
   ;; agent cycle
   #:perceive
   #:deliberate
   #:act
   #:cognitive-cycle
   #:pursue
   #:goal-push
   #:goal-pop
   #:current-goals
   ;; multi-agent
   #:society-boot
   #:society-default-ensemble
   #:society-register
   #:society-send
   #:society-broadcast
   #:society-step
   #:society-run-cycles
   #:society-start-async
   #:society-stop
   #:*society*
   #:bb-post
   #:bb-read
   ;; tools / llm
   #:register-tool
   #:invoke-tool
   #:list-tools
   #:llm-complete
   #:llm-enabled-p
   ;; language / world / tx
   #:interpret
   #:save-world
   #:load-world
   #:tx-begin
   #:tx-assert
   #:tx-retract
   #:tx-commit
   #:tx-rollback
   #:with-mind-transaction
   ;; daemon / API
   #:daemon-start
   #:daemon-stop
   #:daemon-status
   #:api-start
   #:api-stop
   #:api-status
   ;; config / log
   #:*config*
   #:*mind*
   #:get-config
   #:set-config
   #:metis-log
   #:recent-logs
   #:log-set-level
   #:csp-solve
   #:security-profile
   ;; 2.0 further paths
   #:rete-compile
   #:run-forward-rete
   #:forward-chain-rete
   #:rete-assert-wme
   #:rete-assert-fact
   #:rete-invalidate
   #:durable-open
   #:durable-close
   #:durable-put
   #:durable-get
   #:durable-save-mind
   #:durable-load-mind
   #:durable-roundtrip-ok-p
   #:tms-formal-verify
   #:load-large-corpus
   #:arc-boot
   #:arc-cycle
   #:arc-status
   #:arc-thesis
   #:*arc*
   #:api-security-check-input
   #:api-require-auth
   ;; 3.0 EPOCH
   #:epoch-thesis
   #:epoch-open
   #:epoch-step
   #:epoch-run
   #:epoch-suspend
   #:epoch-resume
   #:epoch-status
   #:epoch-flagship
   #:epoch-guarded-self-mod
   #:epoch-ingest-self-code
   #:epoch-leap-resume-demo
   #:*epoch*
   #:*epoch-thesis*
   ;; 3.1 interactive interface
   #:session-create
   #:session-ensure
   #:session-get
   #:session-attach-file
   #:session-attach-photo
   #:session-attach-context
   #:session-list-attachments
   #:session-get-attachment
   #:session-attachment-text
   #:session-status
   #:*session*
   #:iface-turn
   #:iface-drive
   #:iface-repl
   #:iface-accommodate
   #:iface-flagship
   #:iface-thesis
   #:*iface-thesis*)
  (:documentation
   "Metis 1.0 — production introspective multi-agent cognitive architecture.
    Code is data; minds reason, plan (STRIPS+HTN), maintain truth, learn, and collaborate."))

(in-package :metis)

(pushnew :metis-production *features*)
