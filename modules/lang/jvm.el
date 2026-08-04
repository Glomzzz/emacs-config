;;; jvm.el --- Shared JVM project and build helpers -*- lexical-binding: t; -*-

(require 'project)
(require 'seq)

(defconst my/jvm-workspace-markers
  '("gradlew" "mvnw" "settings.gradle" "settings.gradle.kts"
    "build.sbt" "project/build.properties" "project.scala" "build.sc"
    "build.mill" "build.mill.scala" "build.mill.yaml" "mill" ".bsp"
    "WORKSPACE" "MODULE.bazel" ".project")
  "Files and directories that identify a JVM workspace root.")

(defconst my/jvm-module-markers
  '("build.gradle" "build.gradle.kts" "pom.xml")
  "Files that identify a standalone JVM module.")

(defconst my/jvm-vc-markers '(".git" ".hg")
  "Version-control markers used as a final JVM project fallback.")

(defun my/jvm-source-mode-p ()
  "Return non-nil when the current buffer contains JVM source code."
  (derived-mode-p 'java-mode 'java-ts-mode
                  'kotlin-mode 'kotlin-ts-mode
                  'scala-mode))

(defun my/jvm-root-with-markers (dir markers)
  "Find the nearest directory above DIR containing one of MARKERS."
  (locate-dominating-file
   dir
   (lambda (candidate)
     (seq-some
      (lambda (marker)
        (file-exists-p (expand-file-name marker candidate)))
      markers))))

(defun my/jvm-project-root (dir)
  "Find the nearest JVM project root above DIR, or return DIR."
  (file-name-as-directory
   (expand-file-name
    (or (my/jvm-root-with-markers dir my/jvm-workspace-markers)
        (my/jvm-root-with-markers dir my/jvm-module-markers)
        (my/jvm-root-with-markers dir my/jvm-vc-markers)
        dir))))

(defun my/jvm-project (dir)
  "Return a transient JVM project rooted above DIR."
  (when (my/jvm-source-mode-p)
    (cons 'transient (my/jvm-project-root dir))))

(defun my/executable-available-p (&rest programs)
  "Return non-nil when one of PROGRAMS is available on `exec-path'."
  (seq-some #'executable-find programs))

(defun my/jvm-wrapper-command (root wrapper task)
  "Build a command for WRAPPER and TASK below ROOT."
  (let ((path (expand-file-name wrapper root)))
    (when (file-exists-p path)
      (format "%s %s"
              (if (file-executable-p path)
                  (concat "./" wrapper)
                (concat "sh ./" wrapper))
              task))))

(defun my/jvm-project-build-command (root)
  "Return the conventional test command for the JVM project at ROOT."
  (or (my/jvm-wrapper-command root "gradlew" "test")
      (my/jvm-wrapper-command root "mvnw" "test")
      (my/jvm-wrapper-command root "mill" "__.test")
      (and (or (file-exists-p (expand-file-name "build.sbt" root))
               (file-exists-p
                (expand-file-name "project/build.properties" root)))
           "sbt test")
      (and (file-exists-p (expand-file-name "project.scala" root))
           "scala-cli test .")
      (and (or (file-exists-p (expand-file-name "build.sc" root))
               (file-exists-p (expand-file-name "build.mill" root))
               (file-exists-p (expand-file-name "build.mill.scala" root))
               (file-exists-p (expand-file-name "build.mill.yaml" root)))
           "mill __.test")
      (and (file-exists-p (expand-file-name "pom.xml" root))
           "mvn test")
      (and (or (file-exists-p (expand-file-name "settings.gradle" root))
               (file-exists-p (expand-file-name "settings.gradle.kts" root))
               (file-exists-p (expand-file-name "build.gradle" root))
               (file-exists-p (expand-file-name "build.gradle.kts" root)))
           "gradle test")
      (and (or (file-exists-p (expand-file-name "WORKSPACE" root))
               (file-exists-p (expand-file-name "MODULE.bazel" root)))
           "bazel test //...")))

(defun my/command-in-directory (directory command)
  "Return a shell command that runs COMMAND in DIRECTORY."
  (format "cd %s && %s"
          (shell-quote-argument (directory-file-name directory))
          command))

(defun my/jvm-buffer-setup (&optional standalone-command)
  "Set JVM buffer defaults and its build command.
Use STANDALONE-COMMAND when the project has no recognized build file."
  (setq-local indent-tabs-mode nil)
  (let* ((root (my/jvm-project-root default-directory))
         (command (or (my/jvm-project-build-command root)
                      standalone-command)))
    (when command
      (setq-local compile-command
                  (my/command-in-directory root command)))))

(add-hook 'project-find-functions #'my/jvm-project)

;;; jvm.el ends here
