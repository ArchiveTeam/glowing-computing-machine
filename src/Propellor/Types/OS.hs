{-# LANGUAGE DeriveDataTypeable #-}

module Propellor.Types.OS (
	System(..),
	Distribution(..),
	DebianSuite(..),
	isStable,
	Release,
	Architecture,
	HostName,
	UserName,
	User(..),
	Group(..),
	userGroup,
	Port(..),
) where

import Network.BSD (HostName)
import Data.Typeable

-- | High level description of a operating system.
data System = System Distribution Architecture
	deriving (Show, Eq, Typeable)

data Distribution
	= Debian DebianSuite
	| Ubuntu Release
	deriving (Show, Eq)

-- | Debian has several rolling suites, and a number of stable releases,
-- such as Stable "jessie".
data DebianSuite = Experimental | Unstable | Testing | Stable Release
	deriving (Show, Eq)

isStable :: DebianSuite -> Bool
isStable (Stable _) = True
isStable _ = False

type Release = String
type Architecture = String

type UserName = String

newtype User = User UserName
	deriving (Eq, Ord, Show)

newtype Group = Group String
	deriving (Eq, Ord, Show)

-- | Makes a Group with the same name as the User.
userGroup :: User -> Group
userGroup (User u) = Group u

newtype Port = Port Int
	deriving (Eq, Show)
