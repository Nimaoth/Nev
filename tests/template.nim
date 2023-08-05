discard """

  # What actions to expect completion on.
  # Options:
  #   "compile": expect successful compilation
  #   "run": expect successful compilation and execution
  #   "reject": expect failed compilation. The "reject" action can catch
  #             {.error.} pragmas but not {.fatal.} pragmas because
  #             {.fatal.} pragmas guarantee that compilation will be aborted.
  action: "run"

  # The exit code that the test is expected to return. Typically, the default
  # value of 0 is fine. Note that if the test will be run by valgrind, then
  # the test will exit with either a code of 0 on success or 1 on failure.
  exitcode: 0

  # Provide an `output` string to assert that the test prints to standard out
  # exactly the expected string. Provide an `outputsub` string to assert that
  # the string given here is a substring of the standard out output of the
  # test (the output includes both the compiler and test execution output).
  output: ""
  outputsub: ""

  # Whether to sort the output lines before comparing them to the desired
  # output.
  sortoutput: true

  # Each line in the string given here appears in the same order in the
  # compiler output, but there may be more lines that appear before, after, or
  # in between them.
  nimout: '''
a very long,
multi-line
string'''

  # This is the Standard Input the test should take, if any.
  input: ""

  # Error message the test should print, if any.
  errormsg: ""

  # Can be run in batch mode, or not.
  batchable: true

  # Can be run Joined with other tests to run all together, or not.
  joinable: true

  # On Linux 64-bit machines, whether to use Valgrind to check for bad memory
  # accesses or memory leaks. On other architectures, the test will be run
  # as-is, without Valgrind.
  # Options:
  #   true: run the test with Valgrind
  #   false: run the without Valgrind
  #   "leaks": run the test with Valgrind, but do not check for memory leaks
  valgrind: false   # Can use Valgrind to check for memory leaks, or not (Linux 64Bit only).

  # Command the test should use to run. If left out or an empty string is
  # provided, the command is taken to be:
  # "nim $target --hints:on -d:testing --nimblePath:build/deps/pkgs $options $file"
  # Subject to variable interpolation.
  cmd: "nim c -r $file"

  # Maximum generated temporary intermediate code file size for the test.
  maxcodesize: 666

  # Timeout seconds to run the test. Fractional values are supported.
  timeout: 1.5

  # Targets to run the test into (c, cpp, objc, js). Defaults to c.
  targets: "c js"

  # flags with which to run the test, delimited by `;`
  matrix: "; -d:release; -d:caseFoo -d:release"

  # Conditions that will skip this test. Use of multiple "disabled" clauses
  # is permitted.
  disabled: "bsd"   # Can disable OSes...
  disabled: "win"
  disabled: "32bit" # ...or architectures
  disabled: "i386"
  disabled: "azure" # ...or pipeline runners
  disabled: true    # ...or can disable the test entirely

"""
# assert true
# assert 42 == 42, "Assert error message"