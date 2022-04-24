# tasty-bench [![Hackage](http://img.shields.io/hackage/v/tasty-bench.svg)](https://hackage.haskell.org/package/tasty-bench) [![Stackage LTS](http://stackage.org/package/tasty-bench/badge/lts)](http://stackage.org/lts/package/tasty-bench) [![Stackage Nightly](http://stackage.org/package/tasty-bench/badge/nightly)](http://stackage.org/nightly/package/tasty-bench)

Featherlight benchmark framework (only one file!) for performance measurement
with API mimicking [`criterion`](http://hackage.haskell.org/package/criterion)
and [`gauge`](http://hackage.haskell.org/package/gauge).
A prominent feature is built-in comparison against previous runs
and between benchmarks.

<!-- MarkdownTOC autolink="true" -->

- [How lightweight is it?](#how-lightweight-is-it)
- [How is it possible?](#how-is-it-possible)
- [How to switch?](#how-to-switch)
- [How to write a benchmark?](#how-to-write-a-benchmark)
- [How to read results?](#how-to-read-results)
- [Wall-clock time vs. CPU time](#wall-clock-time-vs-cpu-time)
- [Statistical model](#statistical-model)
- [Memory usage](#memory-usage)
- [Combining tests and benchmarks](#combining-tests-and-benchmarks)
- [Troubleshooting](#troubleshooting)
- [Isolating interfering benchmarks](#isolating-interfering-benchmarks)
- [Comparison against baseline](#comparison-against-baseline)
- [Comparison between benchmarks](#comparison-between-benchmarks)
- [Plotting results](#plotting-results)
- [Build flags](#build-flags)
- [Command-line options](#command-line-options)
- [Custom command-line options](#custom-command-line-options)

<!-- /MarkdownTOC -->

## How lightweight is it?

There is only one source file `Test.Tasty.Bench` and no non-boot dependencies
except [`tasty`](http://hackage.haskell.org/package/tasty).
So if you already depend on `tasty` for a test suite, there
is nothing else to install.

Compare this to `criterion` (10+ modules, 50+ dependencies) and `gauge` (40+ modules, depends on `basement` and `vector`). A build on a clean machine is up to 16x
faster than `criterion` and up to 4x faster than `gauge`. A build without dependencies
is up to 6x faster than `criterion` and up to 8x faster than `gauge`.

`tasty-bench` is a native Haskell library and works everywhere, where GHC
does. We support a full range of architectures (`i386`, `amd64`, `armhf`,
`arm64`, `ppc64le`, `s390x`) and operating systems (Linux, Windows, MacOS,
FreeBSD), plus any GHC from 7.0 to 9.2.

## How is it possible?

Our benchmarks are literally regular `tasty` tests, so we can leverage all existing
machinery for command-line options, resource management, structuring,
listing and filtering benchmarks, running and reporting results. It also means
that `tasty-bench` can be used in conjunction with other `tasty` ingredients.

Unlike `criterion` and `gauge` we use a very simple statistical model described below.
This is arguably a questionable choice, but it works pretty well in practice.
A rare developer is sufficiently well-versed in probability theory
to make sense and use of all numbers generated by `criterion`.

## How to switch?

[Cabal mixins](https://cabal.readthedocs.io/en/3.4/cabal-package.html#pkg-field-mixins)
allow to taste `tasty-bench` instead of `criterion` or `gauge`
without changing a single line of code:

```cabal
cabal-version: 2.0

benchmark foo
  ...
  build-depends:
    tasty-bench
  mixins:
    tasty-bench (Test.Tasty.Bench as Criterion, Test.Tasty.Bench as Criterion.Main, Test.Tasty.Bench as Gauge, Test.Tasty.Bench as Gauge.Main)
```

This works vice versa as well: if you use `tasty-bench`, but at some point
need a more comprehensive statistical analysis,
it is easy to switch temporarily back to `criterion`.

## How to write a benchmark?

Benchmarks are declared in a separate section of `cabal` file:

```cabal
cabal-version:   2.0
name:            bench-fibo
version:         0.0
build-type:      Simple
synopsis:        Example of a benchmark

benchmark bench-fibo
  main-is:       BenchFibo.hs
  type:          exitcode-stdio-1.0
  build-depends: base, tasty-bench
  ghc-options:   "-with-rtsopts=-A32m"
```

And here is `BenchFibo.hs`:

```haskell
import Test.Tasty.Bench

fibo :: Int -> Integer
fibo n = if n < 2 then toInteger n else fibo (n - 1) + fibo (n - 2)

main :: IO ()
main = defaultMain
  [ bgroup "fibonacci numbers"
    [ bench "fifth"     $ nf fibo  5
    , bench "tenth"     $ nf fibo 10
    , bench "twentieth" $ nf fibo 20
    ]
  ]
```

Since `tasty-bench` provides an API compatible with `criterion`,
one can refer to [its documentation](http://www.serpentine.com/criterion/tutorial.html#how-to-write-a-benchmark-suite) for more examples.

## How to read results?

Running the example above (`cabal bench` or `stack bench`)
results in the following output:

```
All
  fibonacci numbers
    fifth:     OK (2.13s)
       63 ns ± 3.4 ns
    tenth:     OK (1.71s)
      809 ns ±  73 ns
    twentieth: OK (3.39s)
      104 μs ± 4.9 μs

All 3 tests passed (7.25s)
```

The output says that, for instance, the first benchmark was repeatedly
executed for 2.13 seconds (wall-clock time), its predicted mean CPU time was
63 nanoseconds and means of individual samples do not often diverge from it
further than ±3.4 nanoseconds (double standard deviation). Take standard
deviation numbers with a grain of salt; there are lies, damned lies, and
statistics.

## Wall-clock time vs. CPU time

What time are we talking about?
Both `criterion` and `gauge` by default report wall-clock time, which is
affected by any other application which runs concurrently.
Ideally benchmarks are executed on a dedicated server without any other load,
but — let's face the truth — most of developers run benchmarks
on a laptop with a hundred other services and a window manager, and
watch videos while waiting for benchmarks to finish. That's the cause
of a notorious "variance introduced by outliers: 88% (severely inflated)" warning.

To alleviate this issue `tasty-bench` measures CPU time by `getCPUTime`
instead of wall-clock time.
It does not provide a perfect isolation from other processes (e. g.,
if CPU cache is spoiled by others, populating data back from RAM
is your burden), but is a bit more stable.

Caveat: this means that for multithreaded algorithms
`tasty-bench` reports total elapsed CPU time across all cores, while
`criterion` and `gauge` print maximum of core's wall-clock time.
It also means that `tasty-bench` cannot measure time spent out of process,
e. g., calls to other executables.

## Statistical model

Here is a procedure used by `tasty-bench` to measure execution time:

1. Set _n_ ← 1.
2. Measure execution time _tₙ_ of _n_ iterations
   and execution time _t₂ₙ_ of _2n_ iterations.
3. Find _t_ which minimizes deviation of (_nt_, _2nt_) from (_tₙ_, _t₂ₙ_),
   namely _t_ ← (_tₙ_ + _2t₂ₙ_) / _5n_.
4. If deviation is small enough (see `--stdev` below)
   or time is running out soon (see `--timeout` below),
   return _t_ as a mean execution time.
5. Otherwise set _n_ ← _2n_ and jump back to Step 2.

This is roughly similar to the linear regression approach which `criterion` takes,
but we fit only two last points. This allows us to simplify away all heavy-weight
statistical analysis. More importantly, earlier measurements,
which are presumably shorter and noisier, do not affect overall result.
This is in contrast to `criterion`, which fits all measurements and
is biased to use more data points corresponding to shorter runs
(it employs _n_ ← _1.05n_ progression).

Mean time and its deviation does not say much about the
distribution of individual timings. E. g., imagine a computation which
(according to a coarse system timer) takes either 0 ms or 1 ms with equal
probability. While one would be able to establish that its mean time is 0.5 ms
with a very small deviation, this does not imply that individual measurements
are anywhere near 0.5 ms. Even assuming an infinite precision of a system
timer, the distribution of individual times is not known to be
[normal](https://en.wikipedia.org/wiki/Normal_distribution).

Obligatory disclaimer: statistics is a tricky matter, there is no
one-size-fits-all approach.
In the absence of a good theory
simplistic approaches are as (un)sound as obscure ones.
Those who seek statistical soundness should rather collect raw data
and process it themselves using a proper statistical toolbox.
Data reported by `tasty-bench`
is only of indicative and comparative significance.

## Memory usage

Configuring RTS to collect GC statistics
(e. g., via `cabal bench --benchmark-options '+RTS -T'`
or `stack bench --ba '+RTS -T'`) enables `tasty-bench` to estimate and report
memory usage:

```
All
  fibonacci numbers
    fifth:     OK (2.13s)
       63 ns ± 3.4 ns, 223 B  allocated,   0 B  copied, 2.0 MB peak memory
    tenth:     OK (1.71s)
      809 ns ±  73 ns, 2.3 KB allocated,   0 B  copied, 4.0 MB peak memory
    twentieth: OK (3.39s)
      104 μs ± 4.9 μs, 277 KB allocated,  59 B  copied, 5.0 MB peak memory

All 3 tests passed (7.25s)
```

This data is reported as per `RTSStats` fields: `allocated_bytes`, `copied_bytes`
and `max_mem_in_use_bytes`.

## Combining tests and benchmarks

When optimizing an existing function, it is important to check that its
observable behavior remains unchanged. One can rebuild
both tests and benchmarks after each change, but it would be more convenient
to run sanity checks within benchmark itself. Since our benchmarks
are compatible with `tasty` tests, we can easily do so.

Imagine you come up with a faster function `myFibo` to generate Fibonacci numbers:

```haskell
import Test.Tasty.Bench
import Test.Tasty.QuickCheck -- from tasty-quickcheck package

fibo :: Int -> Integer
fibo n = if n < 2 then toInteger n else fibo (n - 1) + fibo (n - 2)

myFibo :: Int -> Integer
myFibo n = if n < 3 then toInteger n else myFibo (n - 1) + myFibo (n - 2)

main :: IO ()
main = Test.Tasty.Bench.defaultMain -- not Test.Tasty.defaultMain
  [ bench "fibo   20" $ nf fibo   20
  , bench "myFibo 20" $ nf myFibo 20
  , testProperty "myFibo = fibo" $ \n -> fibo n === myFibo n
  ]
```

This outputs:

```
All
  fibo   20:     OK (3.02s)
    104 μs ± 4.9 μs
  myFibo 20:     OK (1.99s)
     71 μs ± 5.3 μs
  myFibo = fibo: FAIL
    *** Failed! Falsified (after 5 tests and 1 shrink):
    2
    1 /= 2
    Use --quickcheck-replay=927711 to reproduce.

1 out of 3 tests failed (5.03s)
```

We see that `myFibo` is indeed significantly faster than `fibo`,
but unfortunately does not do the same thing. One should probably
look for another way to speed up generation of Fibonacci numbers.

## Troubleshooting

* If benchmarks take too long, set `--timeout` to limit execution time
  of individual benchmarks, and `tasty-bench` will do its best to fit
  into a given time frame. Without `--timeout` we rerun benchmarks until
  achieving a target precision set by `--stdev`, which in a noisy environment
  of a modern laptop with GUI may take a lot of time.

  While `criterion` runs each benchmark at least for 5 seconds,
  `tasty-bench` is happy to conclude earlier, if it does not compromise
  the quality of results. In our experiments `tasty-bench` suites
  tend to finish earlier, even if some individual benchmarks
  take longer than with `criterion`.

  A common source of noisiness is garbage collection. Setting a larger
  allocation area (_nursery_) is often a good idea, either via
  `cabal bench --benchmark-options '+RTS -A32m'` or `stack bench --ba '+RTS -A32m'`.
  Alternatively bake it into
  `cabal` file as `ghc-options: "-with-rtsopts=-A32m"`.

  For GHC ≥ 8.10 consider switching benchmarks to a non-moving garbage collector,
  because it decreases GC pauses and corresponding noise: `+RTS --nonmoving-gc`.

* Never compile benchmarks with `-fstatic-argument-transformation`, because it
  breaks a trick we use to force GHC into reevaluation of the same function application
  over and over again.

* If benchmark results look malformed like below, make sure that you are
  invoking `Test.Tasty.Bench.defaultMain` and not `Test.Tasty.defaultMain`
  (the difference is `consoleBenchReporter` vs. `consoleTestReporter`):

  ```
  All
    fibo 20:       OK (1.46s)
      Response {respEstimate = Estimate {estMean = Measurement {measTime = 87496728, measAllocs = 0, measCopied = 0}, estStdev = 694487}, respIfSlower = FailIfSlower Infinity, respIfFaster = FailIfFaster Infinity}
  ```

* If benchmarks fail with an error message

  ```
  Unhandled resource. Probably a bug in the runner you're using.
  ```

  or

  ```
  Unexpected state of the resource (NotCreated) in getResource. Report as a tasty bug.
  ```

  this is likely caused by `env` or `envWithCleanup` affecting benchmarks structure.
  You can use `env` to read test data from `IO`, but not to read benchmark names
  or affect their hierarchy in other way. This is a fundamental restriction of `tasty`
  to list and filter benchmarks without launching missiles.

* If benchmarks fail with `Test dependencies form a loop`, this is likely
  because of `bcompare`, which compares a benchmark with itself.
  Locating a benchmark in a global environment may be tricky, please refer to
  [`tasty` documentation](https://github.com/UnkindPartition/tasty#patterns) for details
  and consider using `locateBenchmark`.

## Isolating interfering benchmarks

One difficulty of benchmarking in Haskell is that it is
hard to isolate benchmarks so that they do not interfere.
Changing the order of benchmarks or skipping some of them
has an effect on heap's layout and thus affects garbage collection.
This issue is well attested in
[both](https://github.com/haskell/criterion/issues/166)
[`criterion`](https://github.com/haskell/criterion/issues/60)
and
[`gauge`](https://github.com/vincenthz/hs-gauge/issues/2).

Usually (but not always) skipping some benchmarks speeds up remaining ones.
That's because once a benchmark allocated heap which for some reason
was not promptly released afterwards (e. g., it forced a top-level thunk
in an underlying library), all further benchmarks are slowed down
by garbage collector processing this additional amount of live data
over and over again.

There are several mitigation strategies. First of all, giving garbage collector
more breathing space by `+RTS -A32m` (or more) is often good enough.

Further, avoid using top-level bindings to store large test data. Once such thunks
are forced, they remain allocated forever, which affects detrimentally subsequent
unrelated benchmarks. Treat them as external data, supplied via `env`: instead of

```haskell
largeData :: String
largeData = replicate 1000000 'a'

main :: IO ()
main = defaultMain
  [ bench "large" $ nf length largeData, ... ]
```

use

```haskell
import Control.DeepSeq (force)
import Control.Exception (evaluate)

main :: IO ()
main = defaultMain
  [ env (evaluate (force (replicate 1000000 'a'))) $ \largeData ->
    bench "large" $ nf length largeData, ... ]
```

Finally, as an ultimate measure to reduce interference between benchmarks,
one can run each of them in a separate process. We do not quite recommend
this approach, but if you are desperate, here is how.

Assuming that a benchmark is declared in `cabal` file as `benchmark my-bench` component,
let's first find its executable:

```sh
cabal build --enable-benchmarks my-bench
MYBENCH=$(cabal list-bin my-bench) # available since cabal-3.4
```

Now list all benchmark names (hopefully, they do not contain newlines),
escape quotes and slashes, and run each of them separately:

```sh
$MYBENCH -l | sed -e 's/[\"]/\\\\\\&/g' | while read -r name; do $MYBENCH -p '$0 == "'"$name"'"'; done
```

## Comparison against baseline

One can compare benchmark results against an earlier baseline in an automatic way.
To use this feature, first run `tasty-bench` with `--csv FILE` key
to dump results to `FILE` in CSV format
(it could be a good idea to set smaller `--stdev`, if possible):

```
Name,Mean (ps),2*Stdev (ps)
All.fibonacci numbers.fifth,48453,4060
All.fibonacci numbers.tenth,637152,46744
All.fibonacci numbers.twentieth,81369531,3342646
```

Now modify implementation and rerun benchmarks
with `--baseline FILE` key. This produces a report as follows:

```
All
  fibonacci numbers
    fifth:     OK (0.44s)
       53 ns ± 2.7 ns,  8% slower than baseline
    tenth:     OK (0.33s)
      641 ns ±  59 ns
    twentieth: OK (0.36s)
       77 μs ± 6.4 μs,  5% faster than baseline

All 3 tests passed (1.50s)
```

You can also fail benchmarks, which deviate too far from baseline, using
`--fail-if-slower` and `--fail-if-faster` options. For example, setting both of them
to 6 will fail the first benchmark above (because it is more than 6% slower),
but the last one still succeeds (even while it is measurably faster than baseline,
deviation is less than 6%). Consider also using `--hide-successes` to show
only problematic benchmarks, or even
[`tasty-rerun`](http://hackage.haskell.org/package/tasty-rerun) package
to focus on rerunning failing items only.

If you wish to compare two CSV reports non-interactively, here is a handy `awk` incantation:

```sh
awk 'BEGIN{FS=",";OFS=",";print "Name,Old,New,Ratio"}FNR==1{next}FNR==NR{a[$1]=$2;next}{print $1,a[$1],$2,$2/a[$1];gs+=log($2/a[$1]);gc++}END{print "Geometric mean,,",exp(gs/gc)}' old.csv new.csv
```

Here is a larger shell snippet to compare two `git` commits:

```sh
#!/bin/sh
compareBenches () {
  # compareBenches oldCommit newCommit <other arguments are passed to benchmarks directly>
  OLD="$1"
  shift
  NEW="$1"
  shift
  git checkout -q "$OLD" && \
  cabal run -v0 benchmarks -- --csv "$OLD".csv "$@" && \
  git checkout -q "$NEW" && \
  cabal run -v0 benchmarks -- --baseline "$OLD".csv --csv "$NEW".csv "$@" && \
  git checkout -q "@{-2}" && \
  awk 'BEGIN{FS=",";OFS=",";print "Name,'"$OLD"','"$NEW"',Ratio"}FNR==1{next}FNR==NR{a[$1]=$2;next}{print $1,a[$1],$2,$2/a[$1];gs+=log($2/a[$1]);gc++}END{print "Geometric mean,,",exp(gs/gc)}' "$OLD".csv "$NEW".csv > "$OLD"-vs-"$NEW".csv
}
```

Note that columns in CSV report are different from what `criterion` or `gauge`
would produce. If names do not contain commas, missing columns can be faked this way:

```sh
cat tasty-bench.csv \
| awk 'BEGIN {FS=",";OFS=","}; {print $1,$2/1e12,$2/1e12,$2/1e12,$3/2e12,$3/2e12,$3/2e12}' \
| sed '1s/.*/Name,Mean,MeanLB,MeanUB,Stddev,StddevLB,StddevUB/'
```

To fake `gauge` in `--csvraw` mode use

```sh
cat tasty-bench.csv \
| awk 'BEGIN {FS=",";OFS=","}; {print $1,1,$2/1e12,0,$2/1e12,$2/1e12,0,$6+0,0,0,0,0,$4+0,0,$5+0,0,0,0,0}' \
| sed '1s/.*/name,iters,time,cycles,cpuTime,utime,stime,maxrss,minflt,majflt,nvcsw,nivcsw,allocated,numGcs,bytesCopied,mutatorWallSeconds,mutatorCpuSeconds,gcWallSeconds,gcCpuSeconds/'
```

Please refer to `gawk` manual, if you wish to process names with
[commas](https://www.gnu.org/software/gawk/manual/gawk.html#Splitting-By-Content)
or
[quotes](https://www.gnu.org/software/gawk/manual/gawk.html#More-CSV).

## Comparison between benchmarks

You can also compare benchmarks to each other without any external tools,
all in the comfort of your terminal.

```haskell
import Test.Tasty.Bench

fibo :: Int -> Integer
fibo n = if n < 2 then toInteger n else fibo (n - 1) + fibo (n - 2)

main :: IO ()
main = defaultMain
  [ bgroup "fibonacci numbers"
    [ bcompare "tenth"  $ bench "fifth"     $ nf fibo  5
    ,                     bench "tenth"     $ nf fibo 10
    , bcompare "tenth"  $ bench "twentieth" $ nf fibo 20
    ]
  ]
```

This produces a report, comparing mean times of `fifth` and `twentieth` to `tenth`:

```
All
  fibonacci numbers
    fifth:     OK (16.56s)
      121 ns ± 2.6 ns, 0.08x
    tenth:     OK (6.84s)
      1.6 μs ±  31 ns
    twentieth: OK (6.96s)
      203 μs ± 4.1 μs, 128.36x
```

To locate a baseline benchmark in a larger suite use `locateBenchmark`.

One can leverage comparisons between benchmarks to implement portable performance
tests, expressing properties like "this algorithm must be at least twice faster
than that one" or "this operation should not be more than thrice slower than that".
This can be achieved with `bcompareWithin`, which takes an acceptable interval
of performance as an argument.

## Plotting results

Users can dump results into CSV with `--csv FILE`
and plot them using `gnuplot` or other software. But for convenience
there is also a built-in quick-and-dirty SVG plotting feature,
which can be invoked by passing `--svg FILE`. Here is a sample of its output:

![Plotting](./example.svg)

## Build flags

Build flags are a brittle subject and users do not normally need to touch them.

* If you find yourself in an environment, where `tasty` is not available and you
  have access to boot packages only, you can still use `tasty-bench`! Just copy
  `Test/Tasty/Bench.hs` to your project (imagine it like a header-only C library).
  It will provide you with functions to build `Benchmarkable` and run them manually
  via `measureCpuTime`. This mode of operation can be also configured
  by disabling Cabal flag `tasty`.

* If results are amiss or oscillate wildly and adjusting `--timeout` and `--stdev`
  does not help, you may be interested to investigate individual timings of
  successive runs by enabling Cabal flag `debug`. This will pipe raw data into `stderr`.

## Command-line options

Use `--help` to list command-line options.

* `-p`, `--pattern`

  This is a standard `tasty` option, which allows filtering benchmarks
  by a pattern or `awk` expression. Please refer to
  [`tasty` documentation](https://github.com/UnkindPartition/tasty#patterns)
  for details.

* `-t`, `--timeout`

  This is a standard `tasty` option, setting timeout for individual benchmarks
  in seconds. Use it when benchmarks tend to take too long: `tasty-bench` will make
  an effort to report results (even if of subpar quality) before timeout. Setting
  timeout too tight (insufficient for at least three iterations)
  will result in a benchmark failure. One can adjust it locally for a group
  of benchmarks, e. g., `localOption (mkTimeout 100000000)` for 100 seconds.

* `--stdev`

  Target relative standard deviation of measurements in percents (5% by default).
  Large values correspond to fast and loose benchmarks, and small ones to long and precise.
  It can also be adjusted locally for a group of benchmarks,
  e. g., `localOption (RelStDev 0.02)`.
  If benchmarking takes far too long, consider setting `--timeout`,
  which will interrupt benchmarks, potentially before reaching the target deviation.

* `--csv`

  File to write results in CSV format.

* `--baseline`

  File to read baseline results in CSV format (as produced by `--csv`).

* `--fail-if-slower`, `--fail-if-faster`

  Upper bounds of acceptable slow down / speed up in percents. If a benchmark is unacceptably slower / faster than baseline (see `--baseline`),
  it will be reported as failed. Can be used in conjunction with
  a standard `tasty` option `--hide-successes` to show only problematic benchmarks.
  Both options can be adjusted locally for a group of benchmarks,
  e. g., `localOption (FailIfSlower 0.10)`.

* `--svg`

  File to plot results in SVG format.

* `+RTS -T`

  Estimate and report memory usage.

## Custom command-line options

As usual with `tasty`, it is easy to extend benchmarks with custom command-line options.
Here is an example:

```haskell
import Data.Proxy
import Test.Tasty.Bench
import Test.Tasty.Ingredients.Basic
import Test.Tasty.Options
import Test.Tasty.Runners

newtype RandomSeed = RandomSeed Int

instance IsOption RandomSeed where
  defaultValue = RandomSeed 42
  parseValue = fmap RandomSeed . safeRead
  optionName = pure "seed"
  optionHelp = pure "Random seed used in benchmarks"

main :: IO ()
main = do
  let customOpts  = [Option (Proxy :: Proxy RandomSeed)]
      ingredients = includingOptions customOpts : benchIngredients
  opts <- parseOptions ingredients benchmarks
  let RandomSeed seed = lookupOption opts
  defaultMainWithIngredients ingredients benchmarks

benchmarks :: Benchmark
benchmarks = bgroup "All" []
```
