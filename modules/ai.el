;;; ai.el --- GPTel configuration for the SkillW NewAPI backend -*- lexical-binding: t; -*-

(require 'subr-x)

(defconst my/gptel-skillw-models
  '(claude-fable-5 claude-opus-4-8 claude-opus-4.8 claude-opus-5
    claude-opus-5-thinking claude-sonnet-4-8 claude-sonnet-5
    deepseek-v4-flash deepseek-v4-pro gemini-3-flash-preview
    gemini-3.1-pro-preview gpt-5.4 gpt-5.5 gpt-5.6-luna
    gpt-5.6-luna-thinking gpt-5.6-sol gpt-5.6-sol-thinking
    gpt-5.6-terra gpt-5.6-terra-thinking gpt-image-2))

(defun my/gptel-skillw-api-key ()
  "Read the SkillW API key from the SOPS-managed secret file."
  (let ((key-file (or (getenv "SKILLW_API_KEY_FILE")
                      "/run/secrets/skillw/api_key")))
    (unless (file-readable-p key-file)
      (user-error "SkillW API key file is unavailable: %s" key-file))
    (with-temp-buffer
      (insert-file-contents-literally key-file)
      (string-trim (buffer-string)))))

(use-package gptel
  :commands (gptel gptel-send)
  :config
  (setq gptel-backend
        (gptel-make-openai
         "SkillW"
         :host "api.skillw.com"
         :endpoint "/v1/chat/completions"
         :key #'my/gptel-skillw-api-key
         :models my/gptel-skillw-models
         :stream t))
  (setq gptel-model 'gpt-5.4))

;;; ai.el ends here
