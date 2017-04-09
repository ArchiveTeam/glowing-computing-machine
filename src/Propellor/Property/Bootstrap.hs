module Propellor.Property.Bootstrap (RepoSource(..), bootstrappedFrom, clonedFrom) where

import Propellor.Base
import Propellor.Bootstrap
import Propellor.Property.Chroot

import Data.List

-- | Where a propellor repository should be bootstrapped from.
data RepoSource
	= GitRepoUrl String
	| GitRepoOutsideChroot

-- | Bootstraps a propellor installation into
-- /usr/local/propellor/
--
-- Normally, propellor is already bootstrapped when it runs, so this
-- property is not useful. However, this can be useful inside a
-- chroot used to build a disk image, to make the disk image
-- have propellor installed.
--
-- The git repository is cloned (or pulled to update if it already exists).
--
-- All build dependencies are installed, using distribution packages
-- or falling back to using cabal.
bootstrappedFrom :: RepoSource -> Property Linux
bootstrappedFrom reposource = go `requires` clonedFrom reposource
  where
	go :: Property Linux
	go = property "Propellor bootstrapped" $ do
		system <- getOS
		assumeChange $ exposeTrueLocaldir $ runShellCommand $ buildShellCommand
			[ "cd " ++ localdir
			, bootstrapPropellorCommand system
			]

-- | Clones the propellor repeository into /usr/local/propellor/
--
-- GitRepoOutsideChroot can be used when this is used in a chroot.
-- In that case, it clones the /usr/local/propellor/ from outside the
-- chroot into the same path inside the chroot.
--
-- If the propellor repo has already been cloned, pulls to get it
-- up-to-date.
clonedFrom :: RepoSource -> Property Linux
clonedFrom reposource = property ("Propellor repo cloned from " ++ originloc) $ do
	ifM needclone
		( do
			let tmpclone = localdir ++ ".tmpclone"
			system <- getOS
			assumeChange $ exposeTrueLocaldir $ runShellCommand $ buildShellCommand
				[ installGitCommand system
				, "rm -rf " ++ tmpclone
				, "git clone " ++ shellEscape originloc ++ " " ++ tmpclone
				, "mkdir -p " ++ localdir
				-- This is done rather than deleting
				-- the old localdir, because if it is bound
				-- mounted from outside the chroot, deleting
				-- it after unmounting in unshare will remove
				-- the bind mount outside the unshare.
				, "(cd " ++ tmpclone ++ " && tar c) | (cd " ++ localdir ++ " && tar x)"
				, "rm -rf " ++ tmpclone
				]
		, assumeChange $ exposeTrueLocaldir $ runShellCommand $ buildShellCommand
			[ "cd " ++ localdir
			, "git pull"
			]
		)
  where
	needclone = (inChroot <&&> truelocaldirisempty)
		<||> (liftIO (not <$> doesDirectoryExist localdir))
	truelocaldirisempty = exposeTrueLocaldir $ runShellCommand $
		"test ! -d " ++ localdir ++ "/.git"
	originloc = case reposource of
		GitRepoUrl s -> s
		GitRepoOutsideChroot -> localdir

-- | Runs an action with the true localdir exposed,
-- not the one bind-mounted into a chroot.
--
-- In a chroot, this is accomplished by temporily bind mounting the localdir
-- to a temp directory, to preserve access to the original bind mount. Then
-- we unmount the localdir to expose the true localdir. Finally, to cleanup,
-- the temp directory is bind mounted back to the localdir.
exposeTrueLocaldir :: IO a -> Propellor a
exposeTrueLocaldir a = ifM inChroot
	( liftIO $ withTmpDirIn (takeDirectory localdir) "propellor.tmp" $ \tmpdir ->
		bracket_
			(movebindmount localdir tmpdir)
			(movebindmount tmpdir localdir)
			a
	, liftIO a
	)
  where
	movebindmount from to = do
		run "mount" [Param "--bind", File from, File to]
		-- Have to lazy unmount, because the propellor process
		-- is running in the localdir that it's unmounting..
		run "umount" [Param "-l", File from]
	run cmd ps = unlessM (boolSystem cmd ps) $
		error $ "exposeTrueLocaldir failed to run " ++ show (cmd, ps)

assumeChange :: Propellor Bool -> Propellor Result
assumeChange a = do
	ok <- a
	return (cmdResult ok <> MadeChange)

buildShellCommand :: [String] -> String
buildShellCommand = intercalate "&&" . map (\c -> "(" ++ c ++ ")")

runShellCommand :: String -> IO Bool
runShellCommand s = liftIO $ boolSystem "sh" [ Param "-c", Param s]
