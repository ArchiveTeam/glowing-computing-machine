{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Propellor.Property.List (
	props,
	Props,
	toProps,
	propertyList,
	combineProperties,
) where

import Propellor.Types
import Propellor.Types.MetaTypes
import Propellor.PropAccum
import Propellor.Engine
import Propellor.Exception

import Data.Monoid

toProps :: [Property (MetaTypes metatypes)] -> Props (MetaTypes metatypes)
toProps ps = Props (map toChildProperty ps)

-- | Combines a list of properties, resulting in a single property
-- that when run will run each property in the list in turn,
-- and print out the description of each as it's run. Does not stop
-- on failure; does propagate overall success/failure.
--
-- For example:
--
-- > propertyList "foo" $ props
-- > 	& bar
-- > 	& baz
propertyList :: SingI metatypes => Desc -> Props (MetaTypes metatypes) -> Property (MetaTypes metatypes)
propertyList desc (Props ps) = 
	property desc (ensureChildProperties cs)
		`modifyChildren` (++ cs)
  where
	cs = map toChildProperty ps

-- | Combines a list of properties, resulting in one property that
-- ensures each in turn. Stops if a property fails.
combineProperties :: SingI metatypes => Desc -> Props (MetaTypes metatypes) -> Property (MetaTypes metatypes)
combineProperties desc (Props ps) = 
	property desc (combineSatisfy cs NoChange)
		`modifyChildren` (++ cs)
  where
	cs = map toChildProperty ps

combineSatisfy :: [ChildProperty] -> Result -> Propellor Result
combineSatisfy [] rs = return rs
combineSatisfy (p:ps) rs = do
	r <- catchPropellor $ getSatisfy p
	case r of
		FailedChange -> return FailedChange
		_ -> combineSatisfy ps (r <> rs)
