# Example

Our api under test:

```haskell
-- Obligatory fancy-types pragma tax
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards #-}

import Roboservant
import Test.Hspec
import Servant
import GHC.Generics
import Data.Typeable
import Data.Hashable

newtype A = A Int
  deriving (Generic, Eq, Show, Typeable)
  deriving newtype (Hashable, FromHttpApiData, ToHttpApiData)

newtype B = B Int
  deriving (Generic, Eq, Show, Typeable)
  deriving newtype (Hashable, FromHttpApiData, ToHttpApiData)

type Api =
  "item" :> Get '[JSON] A
    :<|> "itemAdd" :> Capture "one" B :> Capture "two" B :> Get '[JSON] B
    :<|> "item" :> Capture "itemId" B :> Get '[JSON] ()

goodServer = server (pure $ A 0)
badServer = server (pure $ A 1)

server introduce = introduce :<|> combine :<|> eliminate
  where
    combine (B i) (B j) = pure $ B (i + j)
    eliminate (B i)
      | i > 10 = error "give up, eleven is way too big and probably not even real"
      | otherwise = pure ()
```

Our tests would usually be in a separate file:

```haskell


defaultConfig :: Config
defaultConfig = Config {
  -- you can pass extra values in using the seed argument. This can be useful
  -- for things that might not be produceable within the api, like auth tokens.
    seed = []
  , maxRuntime = 0.5
  -- if we get to 1000 interactions with the api, call it quits.
  , maxReps = 1000
  -- if you're using this inside quickcheck or hedgehog, you might want to set this
  -- from their seed to make sure it stays deterministic
  , rngSeed = 0
  -- 0 to 100: fail tests if we hit less than this percentage of endpoints.
  , coverageThreshold = 0
  }

spec = describe "example" $ do
  it "good server should not fail" $ do
    fuzz @Api goodServer defaultConfig { coverageThreshold = 0.99 } (pure ())
      >>= (`shouldSatisfy` isNothing)
  it "bad server should fail" $ do
    fuzz @Api badServer defaultConfig { coverageThreshold = 0.99 } (pure ())
      >>= (`shouldSatisfy` serverFailure)
```

And unless we want to ship roboservant and all its dependencies to production, we also need
some orphan instances: because As are the only value we can get without
an input, we need to be able to break them down.

```haskell
deriving via (Compound A) instance Breakdown A
-- if we wanted to assemble As from parts as well, we'd derive using Compound
deriving via (Atom A) instance BuildFrom A

```

Similarly, to generate the first B from the Ints we got from inside the A, we need to be able to
build it up from components.

```haskell
deriving via (Compound B) instance BuildFrom B
deriving via (Atom B) instance Breakdown B


main = hspec spec
```

finally some uninteresting utilities

```haskell
serverFailure :: Maybe Report -> Bool
serverFailure c = case c of
  Just Report{..} ->
    let RoboservantException{..} = rsException
    in failureReason /= NoPossibleMoves
  _ -> False

isNothing x = case x of
  Nothing -> True
  _ -> False
```