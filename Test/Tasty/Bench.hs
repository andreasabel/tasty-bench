{- |
Module:      Test.Tasty.Bench
Copyright:   (c) 2021 Andrew Lelechenko
Licence:     MIT

Featherlight benchmark framework (only one file!) for performance
measurement with API
mimicking [@criterion@](http://hackage.haskell.org/package/criterion)
and [@gauge@](http://hackage.haskell.org/package/gauge).
A prominent feature is built-in comparison against baseline.

=== How lightweight is it?

There is only one source file "Test.Tasty.Bench" and no external
dependencies except [@tasty@](http://hackage.haskell.org/package/tasty). So
if you already depend on @tasty@ for a test suite, there is nothing else
to install.

Compare this to @criterion@ (10+ modules, 50+ dependencies) and @gauge@
(40+ modules, depends on @basement@ and @vector@).

=== How is it possible?

Our benchmarks are literally regular @tasty@ tests, so we can leverage
all existing machinery for command-line options, resource management,
structuring, listing and filtering benchmarks, running and reporting
results. It also means that @tasty-bench@ can be used in conjunction
with other @tasty@ ingredients.

Unlike @criterion@ and @gauge@ we use a very simple statistical model
described below. This is arguably a questionable choice, but it works
pretty well in practice. A rare developer is sufficiently well-versed in
probability theory to make sense and use of all numbers generated by
@criterion@.

=== How to switch?

<https://cabal.readthedocs.io/en/3.4/cabal-package.html#pkg-field-mixins Cabal mixins>
allow to taste @tasty-bench@ instead of @criterion@ or @gauge@ without
changing a single line of code:

> cabal-version: 2.0
>
> benchmark foo
>   ...
>   build-depends:
>     tasty-bench
>   mixins:
>     tasty-bench (Test.Tasty.Bench as Criterion)

This works vice versa as well: if you use @tasty-bench@, but at some
point need a more comprehensive statistical analysis, it is easy to
switch temporarily back to @criterion@.

=== How to write a benchmark?

Benchmarks are declared in a separate section of @cabal@ file:

> cabal-version:   2.0
> name:            bench-fibo
> version:         0.0
> build-type:      Simple
> synopsis:        Example of a benchmark
>
> benchmark bench-fibo
>   main-is:       BenchFibo.hs
>   type:          exitcode-stdio-1.0
>   build-depends: base, tasty-bench

And here is @BenchFibo.hs@:

> import Test.Tasty.Bench
>
> fibo :: Int -> Integer
> fibo n = if n < 2 then toInteger n else fibo (n - 1) + fibo (n - 2)
>
> main :: IO ()
> main = defaultMain
>   [ bgroup "fibonacci numbers"
>     [ bench "fifth"     $ nf fibo  5
>     , bench "tenth"     $ nf fibo 10
>     , bench "twentieth" $ nf fibo 20
>     ]
>   ]

Since @tasty-bench@ provides an API compatible with @criterion@, one can
refer to
<http://www.serpentine.com/criterion/tutorial.html#how-to-write-a-benchmark-suite its documentation>
for more examples.

=== How to read results?

Running the example above (@cabal@ @bench@ or @stack@ @bench@) results in
the following output:

> All
>   fibonacci numbers
>     fifth:     OK (2.13s)
>        63 ns ± 3.4 ns
>     tenth:     OK (1.71s)
>       809 ns ±  73 ns
>     twentieth: OK (3.39s)
>       104 μs ± 4.9 μs
>
> All 3 tests passed (7.25s)

The output says that, for instance, the first benchmark was repeatedly
executed for 2.13 seconds (wall time), its mean time was 63 nanoseconds
and, assuming ideal precision of a system clock, execution time does not
often diverge from the mean further than ±3.4 nanoseconds (double
standard deviation, which for normal distributions corresponds to
<https://en.wikipedia.org/wiki/68%E2%80%9395%E2%80%9399.7_rule 95%>
probability). Take standard deviation numbers with a grain of salt;
there are lies, damned lies, and statistics.

Note that this data is not directly comparable with @criterion@ output:

> benchmarking fibonacci numbers/fifth
> time                 62.78 ns   (61.99 ns .. 63.41 ns)
>                      0.999 R²   (0.999 R² .. 1.000 R²)
> mean                 62.39 ns   (61.93 ns .. 62.94 ns)
> std dev              1.753 ns   (1.427 ns .. 2.258 ns)

One might interpret the second line as saying that 95% of measurements
fell into 61.99–63.41 ns interval, but this is wrong. It states that the
<https://en.wikipedia.org/wiki/Ordinary_least_squares OLS regression> of
execution time (which is not exactly the mean time) is most probably
somewhere between 61.99 ns and 63.41 ns, but does not say a thing about
individual measurements. To understand how far away a typical
measurement deviates you need to add\/subtract double standard deviation
yourself (which gives 62.78 ns ± 3.506 ns, similar to @tasty-bench@
above).

To add to the confusion, @gauge@ in @--small@ mode outputs not the
second line of @criterion@ report as one might expect, but a mean value
from the penultimate line and a standard deviation:

> fibonacci numbers/fifth                  mean 62.39 ns  ( +- 1.753 ns  )

The interval ±1.753 ns answers for
<https://en.wikipedia.org/wiki/68%E2%80%9395%E2%80%9399.7_rule 68%> of
samples only, double it to estimate the behavior in 95% of cases.

=== Statistical model

Here is a procedure used by @tasty-bench@ to measure execution time:

1.  Set \( n \leftarrow 1 \).
2.  Measure execution time \( t_n \) of \( n \) iterations and execution time
    \( t_{2n} \) of \( 2n \) iterations.
3.  Find \( t \) which minimizes deviation of \( (nt, 2nt) \) from
    \( (t_n, t_{2n}) \).
4.  If deviation is small enough (see @--stdev@ below), return \( t \) as a
    mean execution time.
5.  Otherwise set \( n \leftarrow 2n \) and jump back to Step 2.

This is roughly similar to the linear regression approach which
@criterion@ takes, but we fit only two last points. This allows us to
simplify away all heavy-weight statistical analysis. More importantly,
earlier measurements, which are presumably shorter and noisier, do not
affect overall result. This is in contrast to @criterion@, which fits
all measurements and is biased to use more data points corresponding to
shorter runs (it employs \( n \leftarrow 1.05n \) progression).

An alert reader could object that we measure standard deviation for
samples with \( n \) and \( 2n \) iterations, but report it scaled to a single
iteration. Strictly speaking, this is justified only if we assume that
deviating factors are either roughly periodic (e. g., coarseness of a
system clock, garbage collection) or are likely to affect several
successive iterations in the same way (e. g., slow down by another
concurrent process).

Obligatory disclaimer: statistics is a tricky matter, there is no
one-size-fits-all approach. In the absence of a good theory simplistic
approaches are as (un)sound as obscure ones. Those who seek statistical
soundness should rather collect raw data and process it themselves using
a proper statistical toolbox. Data reported by @tasty-bench@ is only of
indicative and comparative significance.

=== Memory usage

Passing @+RTS@ @-T@ (via @cabal@ @bench@ @--benchmark-options@ @\'+RTS@ @-T\'@ or
@stack@ @bench@ @--ba@ @\'+RTS@ @-T\'@) enables @tasty-bench@ to estimate and
report memory usage such as allocated and copied bytes:

> All
>   fibonacci numbers
>     fifth:     OK (2.13s)
>        63 ns ± 3.4 ns, 223 B  allocated,   0 B  copied
>     tenth:     OK (1.71s)
>       809 ns ±  73 ns, 2.3 KB allocated,   0 B  copied
>     twentieth: OK (3.39s)
>       104 μs ± 4.9 μs, 277 KB allocated,  59 B  copied
>
> All 3 tests passed (7.25s)

=== Combining tests and benchmarks

When optimizing an existing function, it is important to check that its
observable behavior remains unchanged. One can rebuild both tests and
benchmarks after each change, but it would be more convenient to run
sanity checks within benchmark itself. Since our benchmarks are
compatible with @tasty@ tests, we can easily do so.

Imagine you come up with a faster function @myFibo@ to generate
Fibonacci numbers:

> import Test.Tasty.Bench
> import Test.Tasty.QuickCheck -- from tasty-quickcheck package
>
> fibo :: Int -> Integer
> fibo n = if n < 2 then toInteger n else fibo (n - 1) + fibo (n - 2)
>
> myFibo :: Int -> Integer
> myFibo n = if n < 3 then toInteger n else myFibo (n - 1) + myFibo (n - 2)
>
> main :: IO ()
> main = Test.Tasty.Bench.defaultMain -- not Test.Tasty.defaultMain
>   [ bench "fibo   20" $ nf fibo   20
>   , bench "myFibo 20" $ nf myFibo 20
>   , testProperty "myFibo = fibo" $ \n -> fibo n === myFibo n
>   ]

This outputs:

> All
>   fibo   20:     OK (3.02s)
>     104 μs ± 4.9 μs
>   myFibo 20:     OK (1.99s)
>      71 μs ± 5.3 μs
>   myFibo = fibo: FAIL
>     *** Failed! Falsified (after 5 tests and 1 shrink):
>     2
>     1 /= 2
>     Use --quickcheck-replay=927711 to reproduce.
>
> 1 out of 3 tests failed (5.03s)

We see that @myFibo@ is indeed significantly faster than @fibo@, but
unfortunately does not do the same thing. One should probably look for
another way to speed up generation of Fibonacci numbers.

=== Troubleshooting

If benchmark results look malformed like below, make sure that you are
invoking 'Test.Tasty.Bench.defaultMain' and not 'Test.Tasty.defaultMain'
(the difference is 'consoleBenchReporter' vs. 'consoleTestReporter'):

> All
>   fibo 20:       OK (1.46s)
>     Response {respEstimate = Estimate {estMean = Measurement {measTime = 87496728, measAllocs = 0, measCopied = 0}, estSigma = 694487}, respIfSlower = FailIfSlower {unFailIfSlower = Infinity}, respIfFaster = FailIfFaster {unFailIfFaster = Infinity}}

=== Comparison against baseline

One can compare benchmark results against an earlier baseline in an
automatic way. To use this feature, first run @tasty-bench@ with
@--csv@ @FILE@ key to dump results to @FILE@ in CSV format:

> Name,Mean (ps),2*Stdev (ps)
> All.fibonacci numbers.fifth,48453,4060
> All.fibonacci numbers.tenth,637152,46744
> All.fibonacci numbers.twentieth,81369531,3342646

Note that columns do not match CSV reports of @criterion@ and @gauge@.
If desired, missing columns can be faked with
@awk@ @\'BEGIN@ @{FS=\",\";OFS=\",\"};@ @{print@ @$1,$2,$2,$2,$3\/2,$3\/2,$3\/2}\'@
or similar.

Now modify implementation and rerun benchmarks with @--baseline@ @FILE@
key. This produces a report as follows:

> All
>   fibonacci numbers
>     fifth:     OK (0.44s)
>        53 ns ± 2.7 ns,  8% slower than baseline
>     tenth:     OK (0.33s)
>       641 ns ±  59 ns
>     twentieth: OK (0.36s)
>        77 μs ± 6.4 μs,  5% faster than baseline
>
> All 3 tests passed (1.50s)

You can also fail benchmarks, which deviate too far from baseline, using
@--fail-if-slower@ and @--fail-if-faster@ options. For example, setting
both of them to 6 will fail the first benchmark above (because it is
more than 6% slower), but the last one still succeeds (even while it is
measurably faster than baseline, deviation is less than 6%). Consider
also using @--hide-successes@ to show only problematic benchmarks, or
even [@tasty-rerun@](http://hackage.haskell.org/package/tasty-rerun)
package to focus on rerunning failing items only.

=== Command-line options

Use @--help@ to list command-line options.

[@-p@, @--pattern@]:

    This is a standard @tasty@ option, which allows filtering benchmarks
    by a pattern or @awk@ expression. Please refer
    to [@tasty@ documentation](https://github.com/feuerbach/tasty#patterns)
    for details.

[@-t@, @--timeout@]:

    This is a standard @tasty@ option, setting timeout for individual
    benchmarks in seconds. Use it when benchmarks tend to take too long:
    @tasty-bench@ will make an effort to report results (even if of
    subpar quality) before timeout. Setting timeout too tight
    (insufficient for at least three iterations) will result in a
    benchmark failure.

[@--stdev@]:

    Target relative standard deviation of measurements in percents (5%
    by default). Large values correspond to fast and loose benchmarks,
    and small ones to long and precise. If it takes far too long,
    consider setting @--timeout@, which will interrupt benchmarks,
    potentially before reaching the target deviation.

[@--csv@]:

    File to write results in CSV format.

[@--baseline@]:

    File to read baseline results in CSV format (as produced by
    @--csv@).

[@--fail-if-slower@, @--fail-if-faster@]:

    Upper bounds of acceptable slow down \/ speed up in percents. If a
    benchmark is unacceptably slower \/ faster than baseline (see
    @--baseline@), it will be reported as failed. Can be used in
    conjunction with a standard @tasty@ option @--hide-successes@ to
    show only problematic benchmarks.

-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

module Test.Tasty.Bench
  (
  -- * Running 'Benchmark'
    defaultMain
  , Benchmark
  , bench
  , bgroup
  , env
  , envWithCleanup
  -- * Creating 'Benchmarkable'
  , Benchmarkable
  , nf
  , whnf
  , nfIO
  , whnfIO
  , nfAppIO
  , whnfAppIO
  -- * Ingredients
  , benchIngredients
  , consoleBenchReporter
  , csvReporter
  , RelStDev(..)
  , FailIfSlower(..)
  , FailIfFaster(..)
  ) where

import Prelude hiding (Int, Integer)
import Control.Applicative
import Control.DeepSeq
import Control.Exception
import Control.Monad (void, unless, guard, (>=>))
import Data.Data (Typeable)
import Data.Foldable (foldMap, traverse_)
import Data.Int (Int64)
import Data.IntMap (IntMap)
import qualified Data.IntMap as IM
import Data.List (intercalate, stripPrefix, isPrefixOf)
import Data.Monoid (All(..), Any(..))
import Data.Proxy
#if MIN_VERSION_containers(0,5,0)
import Data.Set (lookupGE)
#endif
import qualified Data.Set as S
import Data.Traversable (forM)
import Data.Word (Word64)
import GHC.Conc
#if MIN_VERSION_base(4,6,0)
import GHC.Stats
#endif
import System.CPUTime
import System.Mem
import Test.Tasty hiding (defaultMain)
import qualified Test.Tasty
import Test.Tasty.Ingredients
import Test.Tasty.Ingredients.ConsoleReporter
import Test.Tasty.Options
import Test.Tasty.Providers
import Test.Tasty.Runners
import Text.Printf
import System.IO
import System.IO.Unsafe

-- | In addition to @--stdev@ command-line option,
-- one can adjust target relative standard deviation
-- for individual benchmarks and groups of benchmarks
-- using 'adjustOption' and 'localOption'.
--
-- E. g., set target relative standard deviation to 2% as follows:
--
-- > localOption (RelStDev 0.02) (bgroup [...])
--
newtype RelStDev = RelStDev Double
  deriving (Show, Read, Typeable)

instance IsOption RelStDev where
  defaultValue = RelStDev 0.05
  parseValue = fmap RelStDev . parsePositivePercents
  optionName = pure "stdev"
  optionHelp = pure "Target relative standard deviation of measurements in percents (5 by default). Large values correspond to fast and loose benchmarks, and small ones to long and precise. If it takes far too long, consider setting --timeout, which will interrupt benchmarks, potentially before reaching the target deviation."

-- | In addition to @--fail-if-slower@ command-line option,
-- one can adjust an upper bound of acceptable slow down
-- in comparison to baseline for
-- individual benchmarks and groups of benchmarks
-- using 'adjustOption' and 'localOption'.
--
-- E. g., set upper bound of acceptable slow down to 10% as follows:
--
-- > localOption (FailIfSlower 0.10) (bgroup [...])
--
newtype FailIfSlower = FailIfSlower Double
  deriving (Show, Read, Typeable)

instance IsOption FailIfSlower where
  defaultValue = FailIfSlower (1.0 / 0.0)
  parseValue = fmap FailIfSlower . parsePositivePercents
  optionName = pure "fail-if-slower"
  optionHelp = pure "Upper bound of acceptable slow down in percents. If a benchmark is unacceptably slower than baseline (see --baseline), it will be reported as failed."

-- | In addition to @--fail-if-faster@ command-line option,
-- one can adjust an upper bound of acceptable speed up
-- in comparison to baseline for
-- individual benchmarks and groups of benchmarks
-- using 'adjustOption' and 'localOption'.
--
-- E. g., set upper bound of acceptable speed up to 10% as follows:
--
-- > localOption (FailIfFaster 0.10) (bgroup [...])
--
newtype FailIfFaster = FailIfFaster Double
  deriving (Show, Read, Typeable)

instance IsOption FailIfFaster where
  defaultValue = FailIfFaster (1.0 / 0.0)
  parseValue = fmap FailIfFaster . parsePositivePercents
  optionName = pure "fail-if-faster"
  optionHelp = pure "Upper bound of acceptable speed up in percents. If a benchmark is unacceptably faster than baseline (see --baseline), it will be reported as failed."

parsePositivePercents :: String -> Maybe Double
parsePositivePercents xs = do
  x <- safeRead xs
  guard (x > 0)
  pure (x / 100)

-- | Something that can be benchmarked, produced by 'nf', 'whnf', 'nfIO', 'whnfIO',
-- 'nfAppIO', 'whnfAppIO' below.
--
-- Drop-in replacement for 'Criterion.Benchmarkable' and 'Gauge.Benchmarkable'.
--
newtype Benchmarkable = Benchmarkable { _unBenchmarkable :: Int64 -> IO () }
  deriving (Typeable)

showPicos :: Word64 -> String
showPicos i
  | t < 995   = printf "%3.0f ps" t
  | t < 995e1 = printf "%3.1f ns" (t / 1e3)
  | t < 995e3 = printf "%3.0f ns" (t / 1e3)
  | t < 995e4 = printf "%3.1f μs" (t / 1e6)
  | t < 995e6 = printf "%3.0f μs" (t / 1e6)
  | t < 995e7 = printf "%3.1f ms" (t / 1e9)
  | t < 995e9 = printf "%3.0f ms" (t / 1e9)
  | otherwise = printf "%.1f s"   (t / 1e12)
  where
    t :: Double
    t = fromIntegral i

showBytes :: Word64 -> String
showBytes i
  | t < 1000          = printf "%3.0f B " t
  | t < 10189         = printf "%3.1f KB" (t / 1024)
  | t < 1023488       = printf "%3.0f KB" (t / 1024)
  | t < 10433332      = printf "%3.1f MB" (t / 1048576)
  | t < 1048051712    = printf "%3.0f MB" (t / 1048576)
  | t < 10683731149   = printf "%3.1f GB" (t / 1073741824)
  | t < 1073204953088 = printf "%3.0f GB" (t / 1073741824)
  | otherwise         = printf "%.1f TB"  (t / 1099511627776)
  where
    t :: Double
    t = fromIntegral i

data Measurement = Measurement
  { measTime   :: !Word64 -- ^ time in picoseconds
  , measAllocs :: !Word64 -- ^ allocations in bytes
  , measCopied :: !Word64 -- ^ copied bytes
  } deriving (Show, Read)

data Estimate = Estimate
  { estMean  :: !Measurement
  , estSigma :: !Word64  -- ^ stdev in picoseconds
  } deriving (Show, Read)

data Response = Response
  { respEstimate :: !Estimate
  , respIfSlower :: !FailIfSlower -- ^ saved value of --fail-if-slower
  , respIfFaster :: !FailIfFaster -- ^ saved value of --fail-if-faster
  } deriving (Show, Read)

prettyEstimate :: Estimate -> String
prettyEstimate (Estimate m sigma) =
  -- Two sigmas correspond to 95% probability,
  showPicos (measTime m) ++ " ± " ++ showPicos (2 * sigma)

prettyEstimateWithGC :: Estimate -> String
prettyEstimateWithGC (Estimate m sigma) =
  -- Two sigmas correspond to 95% probability,
  showPicos (measTime m) ++ " ± " ++ showPicos (2 * sigma)
  ++ ", " ++ showBytes (measAllocs m) ++ " allocated, "
  ++ showBytes (measCopied m) ++ " copied"

csvEstimate :: Estimate -> String
csvEstimate (Estimate m sigma) = show (measTime m) ++ "," ++ show (2 * sigma)

csvEstimateWithGC :: Estimate -> String
csvEstimateWithGC (Estimate m sigma) = show (measTime m) ++ "," ++ show (2 * sigma)
  ++ "," ++ show (measAllocs m) ++ "," ++ show (measCopied m)

predict
  :: Measurement -- ^ time for one run
  -> Measurement -- ^ time for two runs
  -> Estimate
predict (Measurement t1 a1 c1) (Measurement t2 a2 c2) = Estimate
  { estMean  = Measurement t a c
  , estSigma = truncate (sqrt d :: Double)
  }
  where
    sqr x = x * x
    d = sqr (fromIntegral t1 -     fromIntegral t)
      + sqr (fromIntegral t2 - 2 * fromIntegral t)
    t = (t1 + 2 * t2) `quot` 5
    a = (a1 + 2 * a2) `quot` 5
    c = (c1 + 2 * c2) `quot` 5

predictPerturbed :: Measurement -> Measurement -> Estimate
predictPerturbed t1 t2 = Estimate
  { estMean = estMean (predict t1 t2)
  , estSigma = max
    (estSigma (predict (lo t1) (hi t2)))
    (estSigma (predict (hi t1) (lo t2)))
  }
  where
    prec = max (fromInteger cpuTimePrecision) 1000000000 -- 1 ms
    hi meas = meas { measTime = measTime meas + prec }
    lo meas = meas { measTime = measTime meas - prec }

#if !MIN_VERSION_base(4,10,0)
getRTSStatsEnabled :: IO Bool
#if MIN_VERSION_base(4,6,0)
getRTSStatsEnabled = getGCStatsEnabled
#else
getRTSStatsEnabled = pure False
#endif
#endif

getAllocsAndCopied :: IO (Word64, Word64)
getAllocsAndCopied = do
  enabled <- getRTSStatsEnabled
  if not enabled then pure (0, 0) else
#if MIN_VERSION_base(4,10,0)
    (\s -> (allocated_bytes s, copied_bytes s)) <$> getRTSStats
#elif MIN_VERSION_base(4,6,0)
    (\s -> (fromIntegral $ bytesAllocated s, fromIntegral $ bytesCopied s)) <$> getGCStats
#else
    pure (0, 0)
#endif

measureTime :: Int64 -> Benchmarkable -> IO Measurement
measureTime n (Benchmarkable act) = do
  performGC
  startTime <- fromInteger <$> getCPUTime
  (startAllocs, startCopied) <- getAllocsAndCopied
  act n
  endTime <- fromInteger <$> getCPUTime
  (endAllocs, endCopied) <- getAllocsAndCopied
  pure $ Measurement
    { measTime   = endTime - startTime
    , measAllocs = endAllocs - startAllocs
    , measCopied = endCopied - startCopied
    }

measureTimeUntil :: Timeout -> RelStDev -> Benchmarkable -> IO Estimate
measureTimeUntil timeout (RelStDev targetRelStDev) b = do
  t1 <- measureTime 1 b
  go 1 t1 0
  where
    go :: Int64 -> Measurement -> Word64 -> IO Estimate
    go n t1 sumOfTs = do
      t2 <- measureTime (2 * n) b

      let Estimate (Measurement meanN allocN copiedN) sigmaN = predictPerturbed t1 t2
          isTimeoutSoon = case timeout of
            NoTimeout -> False
            -- multiplying by 1.2 helps to avoid accidental timeouts
            Timeout micros _ -> (sumOfTs + measTime t1 + 3 * measTime t2) * 12 >= fromInteger micros * 1000000 * 10
          isStDevInTargetRange = sigmaN < truncate (max 0 targetRelStDev * fromIntegral meanN)
          scale = (`quot` fromIntegral n)

      if isStDevInTargetRange || isTimeoutSoon
        then pure $ Estimate (Measurement (scale meanN) (scale allocN) (scale copiedN)) (scale sigmaN)
        else go (2 * n) t2 (sumOfTs + measTime t1)

instance IsTest Benchmarkable where
  testOptions = pure
    [ Option (Proxy :: Proxy RelStDev)
    -- FailIfSlower and FailIfFaster must be options of a test provider rather
    -- than options of an ingredient to allow setting them on per-test level.
    , Option (Proxy :: Proxy FailIfSlower)
    , Option (Proxy :: Proxy FailIfFaster)
    ]
  run opts b = const $ case getNumThreads (lookupOption opts) of
    1 -> do
      est <- measureTimeUntil (lookupOption opts) (lookupOption opts) b
      pure $ testPassed $ show (Response est (lookupOption opts) (lookupOption opts))
    _ -> pure $ testFailed "Benchmarks should be run in a single-threaded mode (--jobs 1)"

-- | Attach a name to 'Benchmarkable'.
--
-- This is actually a synonym of 'Test.Tasty.Providers.singleTest'
-- to provide an interface compatible with 'Criterion.bench' and 'Gauge.bench'.
--
bench :: String -> Benchmarkable -> Benchmark
bench = singleTest

-- | Attach a name to a group of 'Benchmark'.
--
-- This is actually a synonym of 'Test.Tasty.testGroup'
-- to provide an interface compatible with 'Criterion.bgroup'
-- and 'Gauge.bgroup'.
--
bgroup :: String -> [Benchmark] -> Benchmark
bgroup = testGroup

-- | Benchmarks are actually just a regular 'Test.Tasty.TestTree' in disguise.
--
-- This is a drop-in replacement for 'Criterion.Benchmark' and 'Gauge.Benchmark'.
--
type Benchmark = TestTree

-- | Run benchmarks and report results, providing
-- an interface compatible with 'Criterion.defaultMain'
-- and 'Gauge.defaultMain'.
--
defaultMain :: [Benchmark] -> IO ()
defaultMain = Test.Tasty.defaultMainWithIngredients benchIngredients . testGroup "All"

-- | List of default benchmark ingredients. This is what 'defaultMain' runs.
--
benchIngredients :: [Ingredient]
benchIngredients = [listingTests, composeReporters consoleBenchReporter csvReporter]

funcToBench :: (b -> c) -> (a -> b) -> a -> Benchmarkable
funcToBench frc = (Benchmarkable .) . go
  where
    go f x n
      | n <= 0    = pure ()
      | otherwise = do
        _ <- evaluate (frc (f x))
        go f x (n - 1)
{-# INLINE funcToBench #-}

-- | 'nf' @f@ @x@ measures time to compute
-- a normal form (by means of 'rnf') of an application of @f@ to @x@.
-- This does not include time to evaluate @f@ or @x@ themselves.
-- Ideally @x@ should be a primitive data type like 'Data.Int.Int'.
--
-- Here is a textbook antipattern: 'nf' 'sum' @[1..1000000]@.
-- Since an input list is shared by multiple invocations of 'sum',
-- it will be allocated in memory in full, putting immense pressure
-- on garbage collector. Also no list fusion will happen.
-- A better approach is 'nf' (@\\n@ @->@ 'sum' @[1..n]@) @1000000@.
--
-- If you are measuring an inlinable function,
-- it is prudent to ensure that its invocation is fully saturated,
-- otherwise inlining will not happen. That's why one can often
-- see 'nf' (@\\n@ @->@ @f@ @n@) @x@ instead of 'nf' @f@ @x@.
-- Same applies to rewrite rules.
--
-- While @tasty-bench@ is capable to perform micro- and even nanobenchmarks,
-- such measurements are noisy and involve an overhead. Results are more reliable
-- when @f@ @x@ takes at least several milliseconds.
--
-- Note that forcing a normal form requires an additional
-- traverse of the structure. In certain scenarios (imagine benchmarking 'tail'),
-- especially when 'NFData' instance is badly written,
-- this traversal may take non-negligible time and affect results.
--
-- Drop-in replacement for 'Criterion.nf' and 'Gauge.nf'.
--
nf :: NFData b => (a -> b) -> a -> Benchmarkable
nf = funcToBench rnf
{-# INLINE nf #-}

-- | 'whnf' @f@ @x@ measures time to compute
-- a weak head normal form of an application of @f@ to @x@.
-- This does not include time to evaluate @f@ or @x@ themselves.
-- Ideally @x@ should be a primitive data type like 'Data.Int.Int'.
--
-- Computing only a weak head normal form is
-- rarely what intuitively is meant by "evaluation".
-- Beware that many educational materials contain examples with 'whnf':
-- this is a wrong default.
-- Unless you understand precisely, what is measured,
-- it is recommended to use 'nf' instead.
--
-- Here is a textbook antipattern: 'whnf' ('Data.List.replicate' @1000000@) @1@.
-- This will succeed in a matter of nanoseconds, because weak head
-- normal form forces only the first element of the list.
--
-- Drop-in replacement for 'Criterion.whnf' and 'Gauge.whnf'.
--
whnf :: (a -> b) -> a -> Benchmarkable
whnf = funcToBench id
{-# INLINE whnf #-}

ioToBench :: (b -> c) -> IO b -> Benchmarkable
ioToBench frc act = Benchmarkable go
  where
    go n
      | n <= 0    = pure ()
      | otherwise = do
        val <- act
        _ <- evaluate (frc val)
        go (n - 1)
{-# INLINE ioToBench #-}

-- | 'nfIO' @x@ measures time to evaluate side-effects of @x@
-- and compute its normal form (by means of 'rnf').
--
-- Pure subexpression of an effectful computation @x@
-- may be evaluated only once and get cached; use 'nfAppIO'
-- to avoid this.
--
-- Note that forcing a normal form requires an additional
-- traverse of the structure. In certain scenarios,
-- especially when 'NFData' instance is badly written,
-- this traversal may take non-negligible time and affect results.
--
-- A typical use case is 'nfIO' ('readFile' @"foo.txt"@).
-- However, if you need I\/O only to read input data from a file,
-- consider using 'env'.
--
-- Drop-in replacement for 'Criterion.nfIO' and 'Gauge.nfIO'.
--
nfIO :: NFData a => IO a -> Benchmarkable
nfIO = ioToBench rnf
{-# INLINE nfIO #-}

-- | 'whnfIO' @x@ measures time to evaluate side-effects of @x@
-- and compute its weak head normal form.
--
-- Pure subexpression of an effectful computation @x@
-- may be evaluated only once and get cached; use 'whnfAppIO'
-- to avoid this.
--
-- Computing only a weak head normal form is
-- rarely what intuitively is meant by "evaluation".
-- Unless you understand precisely, what is measured,
-- it is recommended to use 'nfIO' instead.
--
-- Lazy I\/O is treacherous. If you need I\/O only
-- to read input data from a file, consider using 'env'.
--
-- Drop-in replacement for 'Criterion.whnfIO' and 'Gauge.whnfIO'.
--
whnfIO :: NFData a => IO a -> Benchmarkable
whnfIO = ioToBench id
{-# INLINE whnfIO #-}

ioFuncToBench :: (b -> c) -> (a -> IO b) -> a -> Benchmarkable
ioFuncToBench frc = (Benchmarkable .) . go
  where
    go f x n
      | n <= 0    = pure ()
      | otherwise = do
        val <- f x
        _ <- evaluate (frc val)
        go f x (n - 1)
{-# INLINE ioFuncToBench #-}

-- | 'nfAppIO' @f@ @x@ measures time to evaluate side-effects of
-- an application of @f@ to @x@.
-- and compute its normal form (by means of 'rnf').
-- This does not include time to evaluate @f@ or @x@ themselves.
-- Ideally @x@ should be a primitive data type like 'Data.Int.Int'.
--
-- Note that forcing a normal form requires an additional
-- traverse of the structure. In certain scenarios,
-- especially when 'NFData' instance is badly written,
-- this traversal may take non-negligible time and affect results.
--
-- A typical use case is 'nfAppIO' 'readFile' @"foo.txt"@.
-- However, if you need I\/O only to read input data from a file,
-- consider using 'env'.
--
-- Drop-in replacement for 'Criterion.nfAppIO' and 'Gauge.nfAppIO'.
--
nfAppIO :: NFData b => (a -> IO b) -> a -> Benchmarkable
nfAppIO = ioFuncToBench rnf
{-# INLINE nfAppIO #-}

-- | 'whnfAppIO' @f@ @x@ measures time to evaluate side-effects of
-- an application of @f@ to @x@.
-- and compute its weak head normal form.
-- This does not include time to evaluate @f@ or @x@ themselves.
-- Ideally @x@ should be a primitive data type like 'Data.Int.Int'.
--
-- Computing only a weak head normal form is
-- rarely what intuitively is meant by "evaluation".
-- Unless you understand precisely, what is measured,
-- it is recommended to use 'nfAppIO' instead.
--
-- Lazy I\/O is treacherous. If you need I\/O only
-- to read input data from a file, consider using 'env'.
--
-- Drop-in replacement for 'Criterion.whnfAppIO' and 'Gauge.whnfAppIO'.
--
whnfAppIO :: (a -> IO b) -> a -> Benchmarkable
whnfAppIO = ioFuncToBench id
{-# INLINE whnfAppIO #-}

-- | Run benchmarks in the given environment, usually reading large input data from file.
--
-- One might wonder why 'env' is needed,
-- when we can simply read all input data
-- before calling 'defaultMain'. The reason is that large data
-- dangling in the heap causes longer garbage collection
-- and slows down all benchmarks, even those which do not use it at all.
--
-- Provided only for the sake of compatibility with 'Criterion.env' and 'Gauge.env',
-- and involves 'unsafePerformIO'. Consider using 'withResource' instead.
--
env :: NFData env => IO env -> (env -> Benchmark) -> Benchmark
env res = envWithCleanup res (const $ pure ())

-- | Similar to 'env', but includes an additional argument
-- to clean up created environment.
--
-- Provided only for the sake of compatibility
-- with 'Criterion.envWithCleanup' and 'Gauge.envWithCleanup',
-- and involves 'unsafePerformIO'. Consider using 'withResource' instead.
--
envWithCleanup :: NFData env => IO env -> (env -> IO a) -> (env -> Benchmark) -> Benchmark
envWithCleanup res fin f = withResource
  (res >>= evaluate . force)
  (void . fin)
  (f . unsafePerformIO)

newtype CsvPath = CsvPath { _unCsvPath :: FilePath }
  deriving (Typeable)

instance IsOption (Maybe CsvPath) where
  defaultValue = Nothing
  parseValue = Just . Just . CsvPath
  optionName = pure "csv"
  optionHelp = pure "File to write results in CSV format"

-- | Run benchmarks and save results in CSV format.
-- It activates when @--csv@ @FILE@ command line option is specified.
--
csvReporter :: Ingredient
csvReporter = TestReporter [Option (Proxy :: Proxy (Maybe CsvPath))] $
  \opts tree -> do
    CsvPath path <- lookupOption opts
    let names = IM.fromDistinctAscList $ zip [0..] (testsNames opts tree)
    pure $ \smap -> do
      let augmented = IM.intersectionWith (,) names smap
      hasGCStats <- getRTSStatsEnabled
      bracket
        (do
          h <- openFile path WriteMode
          hSetBuffering h LineBuffering
          hPutStrLn h $ "Name,Mean (ps),2*Stdev (ps)" ++
            (if hasGCStats then ",Allocated,Copied" else "")
          pure h
        )
        hClose
        (`csvOutput` augmented)
      pure $ const ((== 0) . statFailures <$> computeStatistics smap)

csvOutput :: Handle -> IntMap (TestName, TVar Status) -> IO ()
csvOutput h = traverse_ $ \(name, tv) -> do
  hasGCStats <- getRTSStatsEnabled
  let csv = if hasGCStats then csvEstimateWithGC else csvEstimate
  r <- atomically $ readTVar tv >>= \s -> case s of Done r -> pure r; _ -> retry
  case safeRead (resultDescription r) of
    Nothing -> pure ()
    Just (Response est _ _) -> do
      msg <- formatMessage $ csv est
      hPutStrLn h (encodeCsv name ++ ',' : msg)

encodeCsv :: String -> String
encodeCsv xs
  | any (`elem` xs) ",\"\n\r"
  = '"' : concatMap (\x -> if x == '"' then "\"\"" else [x]) xs ++ "\""
  | otherwise = xs

newtype BaselinePath = BaselinePath { _unBaselinePath :: FilePath }
  deriving (Typeable)

instance IsOption (Maybe BaselinePath) where
  defaultValue = Nothing
  parseValue = Just . Just . BaselinePath
  optionName = pure "baseline"
  optionHelp = pure "File with baseline results in CSV format to compare against"

-- | Run benchmarks and report results
-- in a manner similar to 'consoleTestReporter'.
--
-- If @--baseline@ @FILE@ command line option is specified,
-- compare results against an earlier run and mark
-- too slow / too fast benchmarks as failed in accordance to
-- bounds specified by @--fail-if-slower@ @PERCENT@ and @--fail-if-faster@ @PERCENT@.
--
consoleBenchReporter :: Ingredient
consoleBenchReporter = modifyConsoleReporter [Option (Proxy :: Proxy (Maybe BaselinePath))] $ \opts -> do
  baseline <- case lookupOption opts of
    Nothing -> pure S.empty
    Just (BaselinePath path) -> S.fromList . lines <$> (readFile path >>= evaluate . force)
  hasGCStats <- getRTSStatsEnabled
  let pretty = if hasGCStats then prettyEstimateWithGC else prettyEstimate
  pure $ \name r -> case safeRead (resultDescription r) of
    Nothing  -> r
    Just (Response est (FailIfSlower ifSlow) (FailIfFaster ifFast)) ->
      (if isAcceptable then id else forceFail)
      r { resultDescription = pretty est ++ formatSlowDown slowDown }
      where
        slowDown = compareVsBaseline baseline name est
        isAcceptable -- ifSlow/ifFast may be infinite, so we cannot 'truncate'
          =  fromIntegral slowDown <=  100 * ifSlow
          && fromIntegral slowDown >= -100 * ifFast

compareVsBaseline :: S.Set TestName -> TestName -> Estimate -> Int64
compareVsBaseline baseline name (Estimate m sigma) = case mOld of
  Nothing -> 0
  Just (oldTime, oldDoubleSigma)
    | abs (time - oldTime) < max (2 * fromIntegral sigma) oldDoubleSigma -> 0
    | otherwise -> 100 * (time - oldTime) `quot` oldTime
  where
    time = fromIntegral $ measTime m
    mOld = do
      let prefix = encodeCsv name ++ ","
      line <- lookupGE prefix baseline
      (timeCell, ',' : rest) <- span (/= ',') <$> stripPrefix prefix line
      let doubleSigmaCell = takeWhile (/= ',') rest
      (,) <$> safeRead timeCell <*> safeRead doubleSigmaCell

formatSlowDown :: Int64 -> String
formatSlowDown n = case n `compare` 0 of
  LT -> printf ", %2i%% faster than baseline" (-n)
  EQ -> ""
  GT -> printf ", %2i%% slower than baseline" n

forceFail :: Result -> Result
forceFail r = r { resultOutcome = Failure TestFailed, resultShortDescription = "FAIL" }

#if !MIN_VERSION_containers(0,5,0)
lookupGE :: TestName -> S.Set TestName -> Maybe TestName
lookupGE x = fmap fst . S.minView . S.filter (x `isPrefixOf`)
#endif

modifyConsoleReporter :: [OptionDescription] -> (OptionSet -> IO (TestName -> Result -> Result)) -> Ingredient
modifyConsoleReporter desc' iof = TestReporter (desc ++ desc') $ \opts tree ->
  let names = IM.fromDistinctAscList $ zip [0..] (testsNames opts tree)
      modifySMap = (iof opts >>=) . flip postprocessResult . IM.intersectionWith (,) names
  in (modifySMap >=>) <$> cb opts tree
  where
    TestReporter desc cb = consoleTestReporter

postprocessResult :: (TestName -> Result -> Result) -> IntMap (TestName, TVar Status) -> IO StatusMap
postprocessResult f src = do
  paired <- forM src $ \(name, tv) -> (name, tv,) <$> newTVarIO NotStarted
  let doUpdate = atomically $ do
        (Any anyUpdated, All allDone) <-
          getApp $ flip foldMap paired $ \(name, newTV, oldTV) -> Ap $ do
            old <- readTVar oldTV
            case old of
              Done{} -> pure (Any False, All True)
              _ -> do
                new <- readTVar newTV
                case new of
                  Done res -> do
                    writeTVar oldTV (Done (f name res))
                    pure (Any True, All True)
                  -- ignoring Progress nodes, we do not report any
                  -- it would be helpful to have instance Eq Status
                  _ -> pure (Any False, All False)
        if anyUpdated || allDone then pure allDone else retry
      adNauseam = doUpdate >>= (`unless` adNauseam)
  _ <- forkIO adNauseam
  pure $ fmap (\(_, _, a) -> a) paired
