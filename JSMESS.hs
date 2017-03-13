module JSMESS where

admin :: User -> Ssh.PubKeyText -> Property DebianLike
admin u@(User n) k = propertyList ("admin user " ++ n) $ props
	& User.accountFor u
	& User.hasGroup u (Group "staff")
	& Sudo.enabledFor u
	& Ssh.authorizedKey u k
	& Ssh.authorizedKey (User "root") k
