{-# LANGUAGE PackageImports #-}
{-# LANGUAGE GADTs #-}

module Propellor.Engine (
	mainProperties,
	runPropellor,
	ensureProperty,
	ensureProperties,
	fromHost,
	fromHost',
	onlyProcess,
) where

import System.Exit
import System.IO
import Data.Monoid
import Control.Applicative
import "mtl" Control.Monad.RWS.Strict
import System.PosixCompat
import System.Posix.IO
import System.FilePath
import System.Directory

import Propellor.Types
import Propellor.Message
import Propellor.Exception
import Propellor.Info
import Propellor.Property
import Utility.Exception

-- | Gets the Properties of a Host, and ensures them all,
-- with nice display of what's being done.
mainProperties :: Host -> IO ()
mainProperties host = do
	ret <- runPropellor host $
		ensureProperties [ignoreInfo $ infoProperty "overall" (ensureProperties ps) mempty mempty]
	messagesDone
	case ret of
		FailedChange -> exitWith (ExitFailure 1)
		_ -> exitWith ExitSuccess
  where
	ps = map ignoreInfo $ hostProperties host

-- | Runs a Propellor action with the specified host.
--
-- If the Result is not FailedChange, any EndActions
-- that were accumulated while running the action
-- are then also run.
runPropellor :: Host -> Propellor Result -> IO Result
runPropellor host a = do
	(res, endactions) <- evalRWST (runWithHost a) host ()
	endres <- mapM (runEndAction host res) endactions
	return $ mconcat (res:endres)

runEndAction :: Host -> Result -> EndAction -> IO Result
runEndAction host res (EndAction desc a) = actionMessageOn (hostName host) desc $ do
	(ret, _s, _) <- runRWST (runWithHost (catchPropellor (a res))) host ()
	return ret

-- | Ensures a list of Properties, with a display of each as it runs.
ensureProperties :: [Property NoInfo] -> Propellor Result
ensureProperties ps = ensure ps NoChange
  where
	ensure [] rs = return rs
	ensure (p:ls) rs = do
		hn <- asks hostName
		r <- actionMessageOn hn (propertyDesc p) (ensureProperty p)
		ensure ls (r <> rs)

-- | Lifts an action into the context of a different host.
--
-- > fromHost hosts "otherhost" Ssh.getHostPubKey
fromHost :: [Host] -> HostName -> Propellor a -> Propellor (Maybe a)
fromHost l hn getter = case findHost l hn of
	Nothing -> return Nothing
	Just h -> Just <$> fromHost' h getter

fromHost' :: Host -> Propellor a -> Propellor a
fromHost' h getter = do
	(ret, _s, runlog) <- liftIO $ runRWST (runWithHost getter) h ()
	tell runlog
	return ret

onlyProcess :: FilePath -> IO a -> IO a
onlyProcess lockfile a = bracket lock unlock (const a)
  where
	lock = do
		createDirectoryIfMissing True (takeDirectory lockfile)
		l <- createFile lockfile stdFileMode
		setLock l (WriteLock, AbsoluteSeek, 0, 0)
			`catchIO` const alreadyrunning
		return l
	unlock = closeFd
	alreadyrunning = error "Propellor is already running on this host!"
