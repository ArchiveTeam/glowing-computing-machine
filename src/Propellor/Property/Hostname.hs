module Propellor.Property.Hostname where

import Propellor.Base
import qualified Propellor.Property.File as File
import Propellor.Property.Chroot (inChroot)

import Data.List
import Data.List.Utils

-- | Ensures that the hostname is set using best practices, to whatever
-- name the `Host` has.
--
-- Configures both </etc/hostname> and the current hostname.
-- (However, when used inside a chroot, avoids setting the current hostname
-- as that would impact the system outside the chroot.)
--
-- Configures </etc/mailname> with the domain part of the hostname.
--
-- </etc/hosts> is also configured, with an entry for 127.0.1.1, which is
-- standard at least on Debian to set the FDQN.
--
-- Also, the </etc/hosts> 127.0.0.1 line is set to localhost. Putting any
-- other hostnames there is not best practices and can lead to annoying
-- messages from eg, apache.
sane :: Property NoInfo
sane = sane' extractDomain

sane' :: ExtractDomain -> Property NoInfo
sane' extractdomain = property ("sane hostname") $
	ensureProperty . setTo' extractdomain =<< asks hostName

-- Like `sane`, but you can specify the hostname to use, instead
-- of the default hostname of the `Host`.
setTo :: HostName -> Property NoInfo
setTo = setTo' extractDomain

setTo' :: ExtractDomain -> HostName -> Property NoInfo
setTo' extractdomain hn = combineProperties desc go
  where
	desc = "hostname " ++ hn
	basehost = takeWhile (/= '.') hn
	domain = extractdomain hn

	go = catMaybes
		[ Just $ "/etc/hostname" `File.hasContent` [basehost]
		, if null domain
			then Nothing 
			else Just $ trivial $ hostsline "127.0.1.1" [hn, basehost]
		, Just $ trivial $ hostsline "127.0.0.1" ["localhost"]
		, Just $ trivial $ check (not <$> inChroot) $
			cmdProperty "hostname" [basehost]
		, Just $ "/etc/mailname" `File.hasContent`
			[if null domain then hn else domain]
		]
	
	hostsline ip names = File.fileProperty desc
		(addhostsline ip names)
		"/etc/hosts"
	addhostsline ip names ls =
		(ip ++ "\t" ++ (unwords names)) : filter (not . hasip ip) ls
	hasip ip l = headMaybe (words l) == Just ip

-- | Makes </etc/resolv.conf> contain search and domain lines for 
-- the domain that the hostname is in.
searchDomain :: Property NoInfo
searchDomain = searchDomain' extractDomain

searchDomain' :: ExtractDomain -> Property NoInfo
searchDomain' extractdomain = property desc (ensureProperty . go =<< asks hostName)
  where
	desc = "resolv.conf search and domain configured"
	go hn =
		let domain = extractdomain hn
		in  File.fileProperty desc (use domain) "/etc/resolv.conf"
	use domain ls = filter wanted $ nub (ls ++ cfgs)
	  where
		cfgs = ["domain " ++ domain, "search " ++ domain]
		wanted l
			| l `elem` cfgs = True
			| "domain " `isPrefixOf` l = False
			| "search " `isPrefixOf` l = False
			| otherwise = True

-- | Function to extract the domain name from a HostName.
type ExtractDomain = HostName -> String

-- | hostname of foo.example.com has a domain of example.com.
-- But, when the hostname is example.com, the domain is
-- example.com too.
--
-- This doesn't work for eg, foo.co.uk, or when foo.sci.uni.edu
-- is in a sci.uni.edu subdomain. If you are in such a network,
-- provide your own ExtractDomain function to the properties above.
extractDomain :: ExtractDomain
extractDomain hn = 
	let bits = split "." hn
	in intercalate "." $
		if length bits > 2
			then drop 1 bits
			else bits
