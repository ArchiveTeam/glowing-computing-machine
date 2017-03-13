module JSMESS where

import Utility.FileMode

admin :: User -> Ssh.PubKeyText -> Property DebianLike
admin u@(User n) k = propertyList ("admin user " ++ n) $ props
	& User.accountFor u
	& User.hasGroup u (Group "staff")
	& Sudo.enabledFor u
	& Ssh.authorizedKey u k
	& Ssh.authorizedKey (User "root") k

staffOwnedGid :: FileMode.FilePath -> Property DebianLike
staffOwnedGid path = File.dirExists path
    & File.ownerGroup path (User "root") (Group "staff")
    & File.mode path (combineModes (readModes ++ executeModes ++
                                    [ ownerWriteMode
                                    , groupWriteMode
                                    , setGroupIDMode
                                    ]))
