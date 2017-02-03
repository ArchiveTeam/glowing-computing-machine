{-# LANGUAGE FlexibleInstances #-}

module Propellor.Property.File where

import Propellor.Base
import Utility.FileMode

import qualified Data.ByteString.Lazy as L
import Data.List (isInfixOf, isPrefixOf)
import System.Posix.Files
import System.Exit
import Data.Char

type Line = String

-- | Replaces all the content of a file.
hasContent :: FilePath -> [Line] -> Property UnixLike
f `hasContent` newcontent = fileProperty
	("replace " ++ f)
	(\_oldcontent -> newcontent) f

-- | Ensures that a line is present in a file, adding it to the end if not.
containsLine :: FilePath -> Line -> Property UnixLike
f `containsLine` l = f `containsLines` [l]

-- | Ensures that a list of lines are present in a file, adding any that are not
-- to the end of the file.
--
-- Note that this property does not guarantee that the lines will appear
-- consecutively, nor in the order specified.  If you need either of these, use
-- 'File.containsBlock'.
containsLines :: FilePath -> [Line] -> Property UnixLike
f `containsLines` ls = fileProperty (f ++ " contains:" ++ show ls) go f
  where
	go content = content ++ filter (`notElem` content) ls

-- | Ensures that a block of consecutive lines is present in a file, adding it
-- to the end if not.  Revert to ensure that the block is not present (though
-- the lines it contains could be present, non-consecutively).
containsBlock :: FilePath -> [Line] -> RevertableProperty UnixLike UnixLike
f `containsBlock` ls =
	fileProperty (f ++ " contains block:" ++ show ls) add f
	<!> fileProperty (f ++ " lacks block:" ++ show ls) remove f
  where
	add content
		| ls `isInfixOf` content = content
		| otherwise              = content ++ ls
	remove [] = []
	remove content@(x:xs)
		| ls `isPrefixOf` content = remove (drop (length ls) content)
		| otherwise = x : remove xs

-- | Ensures that a line is not present in a file.
-- Note that the file is ensured to exist, so if it doesn't, an empty
-- file will be written.
lacksLine :: FilePath -> Line -> Property UnixLike
f `lacksLine` l = fileProperty (f ++ " remove: " ++ l) (filter (/= l)) f

lacksLines :: FilePath -> [Line] -> Property UnixLike
f `lacksLines` ls = fileProperty (f ++ " remove: " ++ show [ls]) (filter (`notElem` ls)) f

-- | Replaces all the content of a file, ensuring that its modes do not
-- allow it to be read or written by anyone other than the current user
hasContentProtected :: FilePath -> [Line] -> Property UnixLike
f `hasContentProtected` newcontent = fileProperty' ProtectedWrite
	("replace " ++ f)
	(\_oldcontent -> newcontent) f

-- | Ensures a file has contents that comes from PrivData.
--
-- The file's permissions are preserved if the file already existed.
-- Otherwise, they're set to 600.
hasPrivContent :: IsContext c => FilePath -> c -> Property (HasInfo + UnixLike)
hasPrivContent f = hasPrivContentFrom (PrivDataSourceFile (PrivFile f) f) f

-- | Like hasPrivContent, but allows specifying a source
-- for PrivData, rather than using `PrivDataSourceFile`.
hasPrivContentFrom :: (IsContext c, IsPrivDataSource s) => s -> FilePath -> c -> Property (HasInfo + UnixLike)
hasPrivContentFrom = hasPrivContent' ProtectedWrite

-- | Leaves the file at its default or current mode,
-- allowing "private" data to be read.
--
-- Use with caution!
hasPrivContentExposed :: IsContext c => FilePath -> c -> Property (HasInfo + UnixLike)
hasPrivContentExposed f = hasPrivContentExposedFrom (PrivDataSourceFile (PrivFile f) f) f

hasPrivContentExposedFrom :: (IsContext c, IsPrivDataSource s) => s -> FilePath -> c -> Property (HasInfo + UnixLike)
hasPrivContentExposedFrom = hasPrivContent' NormalWrite

hasPrivContent' :: (IsContext c, IsPrivDataSource s) => FileWriteMode -> s -> FilePath -> c -> Property (HasInfo + UnixLike)
hasPrivContent' writemode source f context = 
	withPrivData source context $ \getcontent -> 
		property' desc $ \o -> getcontent $ \privcontent -> 
			ensureProperty o $ fileProperty' writemode desc
				(\_oldcontent -> privDataByteString privcontent) f
  where
	desc = "privcontent " ++ f

-- | Replaces the content of a file with the transformed content of another file
basedOn :: FilePath -> (FilePath, [Line] -> [Line]) -> Property UnixLike
f `basedOn` (f', a) = property' desc $ \o -> do
	tmpl <- liftIO $ readFile f'
	ensureProperty o $ fileProperty desc (\_ -> a $ lines $ tmpl) f
  where
	desc = f ++ " is based on " ++ f'

-- | Removes a file. Does not remove symlinks or non-plain-files.
notPresent :: FilePath -> Property UnixLike
notPresent f = check (doesFileExist f) $ property (f ++ " not present") $ 
	makeChange $ nukeFile f

-- | Ensures a directory exists.
dirExists :: FilePath -> Property UnixLike
dirExists d = check (not <$> doesDirectoryExist d) $ property (d ++ " exists") $
	makeChange $ createDirectoryIfMissing True d

-- | The location that a symbolic link points to.
newtype LinkTarget = LinkTarget FilePath

-- | Creates or atomically updates a symbolic link.
--
-- Does not overwrite regular files or directories.
isSymlinkedTo :: FilePath -> LinkTarget -> Property UnixLike
link `isSymlinkedTo` (LinkTarget target) = property desc $
	go =<< (liftIO $ tryIO $ getSymbolicLinkStatus link)
  where
	desc = link ++ " is symlinked to " ++ target
	go (Right stat) =
		if isSymbolicLink stat
			then checkLink
			else nonSymlinkExists
	go (Left _) = makeChange $ createSymbolicLink target link

	nonSymlinkExists = do
		warningMessage $ link ++ " exists and is not a symlink"
		return FailedChange
	checkLink = do
		target' <- liftIO $ readSymbolicLink link
		if target == target'
			then noChange
			else makeChange updateLink
	updateLink = createSymbolicLink target `viaStableTmp` link

-- | Ensures that a file is a copy of another (regular) file.
isCopyOf :: FilePath -> FilePath -> Property UnixLike
f `isCopyOf` f' = property desc $ go =<< (liftIO $ tryIO $ getFileStatus f')
  where
	desc = f ++ " is copy of " ++ f'
	go (Right stat) = if isRegularFile stat
		then gocmp =<< (liftIO $ cmp)
		else warningMessage (f' ++ " is not a regular file") >>
			return FailedChange
	go (Left e) = warningMessage (show e) >> return FailedChange

	cmp = safeSystem "cmp" [Param "-s", Param "--", File f, File f']
	gocmp ExitSuccess = noChange
	gocmp (ExitFailure 1) = doit
	gocmp _ = warningMessage "cmp failed" >> return FailedChange

	doit = makeChange $ copy f' `viaStableTmp` f
	copy src dest = unlessM (runcp src dest) $ errorMessage "cp failed"
	runcp src dest = boolSystem "cp"
		[Param "--preserve=all", Param "--", File src, File dest]

-- | Ensures that a file/dir has the specified owner and group.
ownerGroup :: FilePath -> User -> Group -> Property UnixLike
ownerGroup f (User owner) (Group group) = p `describe` (f ++ " owner " ++ og)
  where
	p = cmdProperty "chown" [og, f]
		`changesFile` f
	og = owner ++ ":" ++ group

-- | Ensures that a file/dir has the specfied mode.
mode :: FilePath -> FileMode -> Property UnixLike
mode f v = p `changesFile` f
  where
	p = property (f ++ " mode " ++ show v) $ do
		liftIO $ modifyFileMode f (const v)
		return NoChange

class FileContent c where
	emptyFileContent :: c
	readFileContent :: FilePath -> IO c
	writeFileContent :: FileWriteMode -> FilePath -> c -> IO ()

data FileWriteMode = NormalWrite | ProtectedWrite

instance FileContent [Line] where
	emptyFileContent = []
	readFileContent f = lines <$> readFile f
	writeFileContent NormalWrite f ls = writeFile f (unlines ls)
	writeFileContent ProtectedWrite f ls = writeFileProtected f (unlines ls)

instance FileContent L.ByteString where
	emptyFileContent = L.empty
	readFileContent = L.readFile
	writeFileContent NormalWrite f c = L.writeFile f c
	writeFileContent ProtectedWrite f c = 
		writeFileProtected' f (`L.hPutStr` c)

-- | A property that applies a pure function to the content of a file.
fileProperty :: (FileContent c, Eq c) => Desc -> (c -> c) -> FilePath -> Property UnixLike
fileProperty = fileProperty' NormalWrite
fileProperty' :: (FileContent c, Eq c) => FileWriteMode -> Desc -> (c -> c) -> FilePath -> Property UnixLike
fileProperty' writemode desc a f = property desc $ go =<< liftIO (doesFileExist f)
  where
	go True = do
		old <- liftIO $ readFileContent f
		let new = a old
		if old == new
			then noChange
			else makeChange $ updatefile new `viaStableTmp` f
	go False = makeChange $ writer f (a emptyFileContent)

	-- Replicate the original file's owner and mode.
	updatefile content dest = do
		writer dest content
		s <- getFileStatus f
		setFileMode dest (fileMode s)
		setOwnerAndGroup dest (fileOwner s) (fileGroup s)
	
	writer = writeFileContent writemode

-- | A temp file to use when writing new content for a file.
--
-- This is a stable name so it can be removed idempotently.
--
-- It ends with "~" so that programs that read many config files from a
-- directory will treat it as an editor backup file, and not read it.
stableTmpFor :: FilePath -> FilePath
stableTmpFor f = f ++ ".propellor-new~"

-- | Creates/updates a file atomically, running the action to create the
-- stable tmp file, and then renaming it into place.
viaStableTmp :: (MonadMask m, MonadIO m) => (FilePath -> m ()) -> FilePath -> m ()
viaStableTmp a f = bracketIO setup cleanup go
  where
	setup = do
		createDirectoryIfMissing True (takeDirectory f)
		let tmpfile = stableTmpFor f
		nukeFile tmpfile
		return tmpfile
	cleanup tmpfile = tryIO $ removeFile tmpfile
	go tmpfile = do
		a tmpfile
		liftIO $ rename tmpfile f

-- | Generates a base configuration file name from a String, which
-- can be put in a configuration directory, such as
-- </etc/apt/sources.list.d/>
--
-- The generated file name is limited to using ASCII alphanumerics,
-- \'_\' and \'.\' , so that programs that only accept a limited set of
-- characters will accept it. Any other characters will be encoded
-- in escaped form.
--
-- Some file extensions, such as ".old" may be filtered out by
-- programs that use configuration directories. To avoid such problems,
-- it's a good idea to add an static prefix and extension to the 
-- result of this function. For example:
--
-- > aptConf foo = "/etc/apt/apt.conf.d" </> "propellor_" ++ configFileName foo <.> ".conf"
configFileName :: String -> FilePath
configFileName = concatMap escape
  where
	escape c
		| isAscii c && isAlphaNum c = [c]
		| c == '.' = [c]
		| otherwise = '_' : show (ord c)

-- | Applies configFileName to any value that can be shown.
showConfigFileName :: Show v => v -> FilePath
showConfigFileName = configFileName . show

-- | Inverse of showConfigFileName.
readConfigFileName :: Read v => FilePath -> Maybe v
readConfigFileName = readish . unescape
  where
	unescape [] = []
	unescape ('_':cs) = case break (not . isDigit) cs of
		([], _) -> '_' : unescape cs
		(ns, cs') -> case readish ns of
			Nothing -> '_' : ns ++ unescape cs'
			Just n -> chr n : unescape cs'
	unescape (c:cs) = c : unescape cs
