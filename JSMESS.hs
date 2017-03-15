module JSMESS where

import Propellor
import System.Posix.Files
import Utility.FileMode
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Sudo as Sudo

foldi            :: (a -> a -> a) -> a -> [a] -> a
foldi f z []     = z
foldi f z (x:xs) = f x (foldi f z (pairs f xs))

pairs            :: (a -> a -> a) -> [a] -> [a]
pairs f (x:y:t)  = f x y : pairs f t
pairs f t        = t

admin :: User -> [Ssh.PubKeyText] -> Property DebianLike
admin u@(User n) ks = propertyList ("admin user " ++ n) $ props
    & User.accountFor u
    & User.hasGroup u (Group "staff")
    & Sudo.enabledFor u
    & foldi (before) (RevertableProperty doNothing doNothing) (map (Ssh.authorizedKey u) ks)
    & foldi (before) (RevertableProperty doNothing doNothing) (map (Ssh.authorizedKey (User "root")) ks)

staffOwned :: FilePath -> Property UnixLike
staffOwned path = propertyList ("path "++ path ++" is owned by staff") $ props
    & File.dirExists path
    & File.ownerGroup path (User "root") (Group "staff")
    & File.mode path (combineModes (readModes ++ executeModes ++
                                    [ ownerWriteMode
                                    , groupWriteMode
                                    , setGroupIDMode
                                    ]))
