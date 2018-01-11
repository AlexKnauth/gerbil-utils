;; -*- Gerbil -*-
;;;; Utilities to run a command in random order

(export #t)

(import
  :gerbil/gambit/exceptions
  :std/format :std/getopt :std/logger :std/iter
  :std/misc/list :std/misc/process :std/pregexp :std/srfi/1 :std/sugar
  :utils/base :utils/error :utils/list :utils/filesystem :utils/multicall :utils/random)

(def (find-all-files regexp args)
  (call-with-list-builder
   (λ (collect _)
     (for-each!
      args
      (λ (arg)
        (walk-filesystem-tree!
         arg
         (λ (path) (when (and (path-is-file? path)
                              (pregexp-match regexp path))
                     (collect path)))))))))

(define-entry-point (random-run . arguments)
  "Run a command with arguments in random order"
  (def gopt
    (getopt
     (option 'log "-l" "--log" default: #f help: "path to random-run log")
     (option 'number-at-once "-n" "--number-at-once" default: #f help: "number of arguments at once")
     (option 'files? "-f" "--files" default: #f help: "search for files in listed directories")
     (option 'regex "-r" "--regex" default: ".*" help: "regexp when using file search")
     (rest-arguments 'arguments help: "arguments, followed by -- then random arguments")))
  (start-logger!)
  (try
   (let* ((opt (getopt-parse gopt arguments))
          (log (hash-get opt 'log))
          (number-at-once (hash-get opt 'number-at-once))
          (files? (hash-get opt 'files?))
          (regex (hash-get opt 'regex))
          (arguments (hash-get opt 'arguments))
          (pos (list-index (looking-for "--") arguments))
          (_ (unless pos (abort! 2 "Missing -- delimiter among arguments")))
          (prefix (take arguments pos))
          (rest (drop arguments (+ pos 1)))
          (arguments-to-randomize
           (if files?
             (find-all-files rest regex)
             rest))
          (randomized-arguments (shuffle-list arguments-to-randomize))
          (do-it (λ (logger)
                   (for (args (if number-at-once
                                (group-by number-at-once randomized-arguments)
                                [randomized-arguments]))
                     (let ((command (append prefix args)))
                       (logger command)
                       (run-process/batch command))))))
     (if log
       (call-with-output-file [path: log create: #t append: #t]
         (λ (f) (do-it (λ (command) (fprintf f "~S~%" command)))))
       (do-it void)))
   (catch (getopt-error? exn)
     (getopt-display-help exn "random-run" (current-error-port))
     (exit 1))
   (catch (uncaught-exception? exn)
     (display-exception (uncaught-exception-reason exn) (current-error-port))
     (exit 1))))