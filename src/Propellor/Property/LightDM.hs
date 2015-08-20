{-# LANGUAGE FlexibleInstances #-}

module Propellor.Property.LightDM where

import Propellor
import qualified Propellor.Property.ConfFile as ConfFile

-- | Configures LightDM to skip the login screen and autologin as a user.
autoLogin :: User -> Property NoInfo
autoLogin (User u) = "/etc/lightdm/lightdm.conf" `ConfFile.containsIniPair`
	                 ("SeatDefaults", "autologin-user", u)
	                 `describe` "lightdm autologin"
