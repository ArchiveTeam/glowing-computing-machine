module JSMESS where

import Propellor
import System.Posix.Files
import Utility.FileMode
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Sudo as Sudo

admin :: User -> Ssh.PubKeyText -> Property DebianLike
admin u@(User n) k = propertyList ("admin user " ++ n) $ props
    & User.accountFor u
    & User.hasGroup u (Group "staff")
    & Sudo.enabledFor u
    & Ssh.authorizedKey u k
    & Ssh.authorizedKey (User "root") k

staffOwned :: FilePath -> Property UnixLike
staffOwned path = propertyList ("path "++ path ++" is owned by staff") $ props
    & File.dirExists path
    & File.ownerGroup path (User "root") (Group "staff")
    & File.mode path (combineModes (readModes ++ executeModes ++
                                    [ ownerWriteMode
                                    , groupWriteMode
                                    , setGroupIDMode
                                    ]))
