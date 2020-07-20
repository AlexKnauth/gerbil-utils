;; -*- Gerbil -*-
;;;; Support for simpler ./build.ss scripts
(export #t)

(import
  :gerbil/gambit/system :gerbil/gambit/misc :gerbil/gambit/os
  :std/format :std/getopt :std/iter :std/make
  :std/misc/list :std/misc/ports :std/misc/string :std/misc/process
  :std/pregexp :std/srfi/1 :std/srfi/13 :std/sugar
  ./exit ./filesystem ./multicall ./path ./path-config ./ports ./source ./versioning)

(def (all-ss-files)
  ((cut lset-difference equal? <> '("build.ss" "unit-tests.ss" "main.ss"))
   (find-files "" (cut path-extension-is? <> ".ss")
               recurse?: (lambda (x) (not (member (path-strip-directory x) '("t" ".git" "_darcs")))))))

(def %name #f)
(def %repo #f)
(def %version-path #f)
(def %deps '())
(def %srcdir #f)
(def %spec all-ss-files)
(def %pkg-config-libs #f)
(def %nix-deps #f)

(def (%set-build-environment!
      script-path add-load-path
      name: (name #f)
      repo: (repo #f)
      deps: (deps '())
      version-path: (version-path #f)
      spec: (spec #f)
      pkg-config-libs: (pkg-config-libs #f)
      nix-deps: (nix-deps #f))
  (set-current-ports-encoding-standard-unix!)
  (set! %srcdir (path-normalize (path-directory script-path)))
  (current-directory %srcdir)
  (add-load-path %srcdir)
  (set! source-directory (lambda () %srcdir))
  (set! home-directory (lambda () %srcdir))
  (set! %name name)
  (set! %repo repo)
  (set! %deps deps)
  (set! %version-path version-path)
  (when spec (set! %spec spec))
  (set! %pkg-config-libs pkg-config-libs)
  (set! %nix-deps nix-deps))

(defsyntax (init-build-environment! stx)
  (syntax-case stx ()
    ((ctx args ...)
     (with-syntax ((main (datum->syntax #'ctx 'main))
                   (add-load-path (datum->syntax #'ctx 'add-load-path)))
     #'(begin
         (%set-build-environment! (this-source-file ctx) add-load-path args ...)
         (def main call-entry-point))))))

(def ($ cmd)
  (match (shell-command cmd #t)
    ([ret . path] (and (zero? ret) (string-trim-eol path)))))
(def (which? cmd) ($ (string-append "which " cmd)))

(def (gerbil-is-nix?)
  (string-prefix? "/nix/store/" _gx#gerbil-libdir))

(def (pkg-config-options pkg-config-libs nix-deps)
  ;; If running a nix gxi from outside a nix build, we'll query nix-shell for pkg-config information
  (def nix-hack? (and (gerbil-is-nix?) (which? "nix-shell")))
  (def ($$ command)
    ($ (if nix-hack?
         (string-append "nix-shell '<nixpkgs>' -p pkg-config " (string-join nix-deps " ") " --run '" command "'")
         command)))
  (when nix-hack? ($$ "echo ok")) ;; do a first run to ensure all dependencies are loaded
  (def ($pkg-config options)
    ($$ (string-join ["pkg-config" . options] " ")))
  ["-ld-options" ($pkg-config ["--libs" . pkg-config-libs])
   "-cc-options" ($pkg-config ["--cflags" . pkg-config-libs])])

(def gsc-options/no-optimize '("-cc-options" "-O0 -U___SINGLE_HOST"))
(def gsc-options/tcc '("-cc" "tcc" "-cc-options" "-shared"))

(def (make-gsc-options tcc: tcc?
                       optimize: optimize?
                       pkg-config-libs: pkg-config-libs
                       nix-deps: nix-deps)
  (append (when/list tcc? gsc-options/tcc)
          (when/list (not optimize?) gsc-options/no-optimize)
          (when/list pkg-config-libs (pkg-config-options pkg-config-libs nix-deps))))

(def (normalize-spec x gsc-options)
  (match x
    ((? string?) [gxc: x . gsc-options])
    ([(? (cut member <> '(gxc: gsc: exe:))) . _] (append x gsc-options))))

(def (build-spec tcc: (tcc #f) optimize: (optimize #f))
  (def gsc-options (make-gsc-options tcc: tcc optimize: optimize
                                     pkg-config-libs: %pkg-config-libs nix-deps: %nix-deps))
  (def files (%spec))
  (map (cut normalize-spec <> gsc-options) files))

(def compile-getopt
  (getopt
   (flag 'stable "-v" "--verbose"
         help: "Make the build verbose")
   (flag 'debug "-g" "--debug"
         help: "Include debug information")
   (flag 'tcc "-t" "--tcc"
         help: "Use tinycc for a faster compile")
   (flag 'no-optimize "--O" "--no-optimize"
         help: "Disable Gerbil optimization")))

(def (create-version-file)
  (update-version-from-git name: %name deps: %deps path: %version-path repo: %repo))

(define-entry-point (compile . opts)
  "Compile all the files in this package"
  (def opt (getopt-parse compile-getopt opts))
  (defrule {symbol} (hash-get opt 'symbol))
  (def optimize? (not {no-optimize}))
  (when %name (create-version-file))
  (make (build-spec tcc: {tcc} optimize: optimize?)
    srcdir: %srcdir verbose: {verbose} debug: (and {debug} 'env) optimize: optimize?))

(define-entry-point (spec . opts)
  "Show the build specification"
  (def opt (getopt-parse compile-getopt opts))
  (defrule {symbol} (hash-get opt 'symbol))
  (def optimize? (not {no-optimize}))
  (pretty-print (build-spec tcc: {tcc} optimize: optimize?)))

(set-default-entry-point! "compile")